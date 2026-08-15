import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_version.dart';
import 'core/theme/app_theme_colors.dart';
import 'core/theme/light_tokens.dart';
import 'models/scene.dart';
import 'models/track.dart';
import 'pages/explore/explore_page.dart';
import 'pages/oobe/oobe_page.dart';
import 'pages/home/home_page.dart';
import 'pages/library/library_page.dart';
import 'pages/world/world_page.dart';
import 'pages/settings/settings_page.dart';
import 'providers/audio/audio_providers.dart';
import 'providers/audio/equalizer_providers.dart';
import 'providers/scene/scene_providers.dart';
import 'providers/settings/notification_providers.dart';
import 'providers/settings/ota_download_provider.dart';
import 'providers/settings/performance_providers.dart';
import 'providers/settings/settings_persistence_providers.dart';
import 'providers/settings/settings_layout_provider.dart';
import 'providers/shell/liquid_glass_capture_provider.dart';
import 'providers/shell/shell_providers.dart';
import 'repositories/settings_repository.dart';
import 'widgets/companion/companion_global_fab.dart';
import 'widgets/notification/app_notify.dart';
import 'widgets/shell/app_dock.dart';
import 'widgets/shell/content_container.dart';
import 'widgets/playback/music_card.dart';
import 'widgets/notification/global_notification_toast.dart';
import 'widgets/noise_texture.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 星璃 · 应用外壳（浅色扁平化重构版）
/// ════════════════════════════════════════════════════════════════════════
///
/// 依据 `docs/ARCHITECTURE_UI_重构.md` §1.2「AppShell 结构」。
///
/// ### 与旧版的根本差异（约定 C3 / 门禁 G1）
/// 旧 Shell 把画布页的沉浸式资产（场景渐变背景、噪点纹理、反应式粒子、
/// 调色盘面板、底部控制栏、更多面板、音量条）提升到了全局，
/// 导致 4 个内容 Tab 全都套着一层深色画布。
///
/// 重构后这些资产**一个都不出现在本文件**——它们的消费者收缩回
/// `pages/canvas/canvas_page.dart` 这座「暗色孤岛」。
///
/// ⚠️ 门禁 G1 用 grep 扫本文件的**全文**（含注释），因此这里刻意只写中文
/// 描述、不写那些资产的类名，避免注释把门禁扫红。
/// 本文件只负责三件事：
///
/// ```
/// Scaffold(#FFFFFF)
/// └ SafeArea(top)
///   ├ Expanded → ContentContainer → IndexedStack(5 页，全部保活)
///   ├ MiniPlayer（全局唯一一份，5 页持续可见）
///   └ SafeArea(bottom) → AppDock（5 Tab）
/// ```
///
/// 🚫 **禁止**在本文件 import 任何暗色画布资产：`core/theme/` 下的动态派生
/// 主题与派生色板、`widgets/` 根目录下的噪点 / 粒子 / 调色盘 / 控制栏 /
/// 更多面板 / 音量条。取色一律走 `core/theme/light_tokens.dart`。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// 软键盘弹出时，内容区至少保留的高度（低于此值不再继续压缩，
  /// 否则 `Padding` 会把 `IndexedStack` 约束成负高度）。
  static const double _minContentHeight = 120;

  /// 5 个常驻页面，顺序**必须**与 [ShellPage] 常量一一对应。
  ///
  /// 全部 `const`：配合 [IndexedStack] 实现「切 Tab 不重建、滚动位置不丢」
  /// （P0-B10 / 约定 C11）。
  /// v3 调整：曲库提前到 Tab 1、探索后移到 Tab 2（用户需求）。
  static const List<Widget> _pages = <Widget>[
    HomePage(), //       0 · 主页（场景内容 + 音乐卡）
    LibraryPage(), //    1 · 曲库
    WorldPage(), //      2 · 世界（星璃世界入口）
    ExplorePage(), //    3 · 探索
    SettingsPage(), //   4 · 设置
  ];

  @override
  void initState() {
    super.initState();
    // 冷启动播放当前场景的环境音景。
    //
    // 该副作用原先寄生在 CanvasPage.initState —— 重构后 CanvasPage 变成
    // 按需 push 的沉浸页，不再随 App 启动挂载，因此必须上提到 Shell，
    // 否则「开 App 就有环境声」这一既有能力会倒退。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final Scene scene = ref.read(activeSceneProvider);
      unawaited(ref.read(audioServiceProvider).switchSoundscape(scene));
      // R10：冷启动恢复用户设置（音量/主题/EQ/场景/上次曲目等）
      unawaited(restoreSettings(ref));
      // 布局整理：尝试读 assets/settings_layout.json 覆盖默认布局（随包分发）。
      unawaited(loadSettingsLayoutAsset(ref));
      // F4：版本升级后弹询问是否重走初始化流程（仅当已完成为 true 且版本变高）。
      unawaited(_maybeAskReOobe(context));
    });
  }

  /// F4：版本升级检测——仅当「已完成 OOBE 且记录过上次构建号」且
  /// 上次构建号 < 当前构建号时才弹询问（cl58：老用户无记录 / 已跳过
  /// 当前版本 → 不再打扰，避免每次启动反复弹）。
  Future<void> _maybeAskReOobe(BuildContext context) async {
    try {
      final bool done = ref.read(oobeDoneProvider);
      if (!done) return; // 首次走 OOBE，不弹。
      final SettingsRepository repo = ref.read(settingsRepositoryProvider);
      final int? last = repo.oobeLastBuild;
      // cl58：老用户（从未记录过完成版本）不弹；已处理过当前版本不弹。
      if (last == null || last >= AppVersion.buildCount) return;
      if (!mounted) return;
      // 延迟片刻，避免与冷启动动画抢屏。
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: const Text('版本已更新'),
          content: const Text(
            '检测到应用已升级（新版本已包含最新功能）。\n'
            '是否重新走一遍初始化流程？\n\n'
            '提示：重走流程只会合并设置，不会清除任何数据。',
            style: TextStyle(fontSize: 13),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('跳过'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('重新初始化'),
            ),
          ],
        ),
      );
      // cl58：无论用户选跳过还是重走，都记录「当前版本已处理过」，
      // 避免下次启动再次弹窗打扰。
      repo.setOobeLastBuild(AppVersion.buildCount);
      if (!mounted || go != true) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const OobePage()),
      );
    } catch (_) {
      // 升级弹窗失败不阻塞启动。
    }
  }

  @override
  Widget build(BuildContext context) {
    // R26fx：OOBE 首次启动引导——未完成时覆盖全屏，完成后进入主界面。
    if (!ref.watch(oobeDoneProvider)) {
      return const OobePage();
    }
    // 「我的世界」主题音效调度：场景切换时自动启停（同样是全局副作用）
    ref.listen<Scene>(activeSceneProvider, (Scene? previous, Scene next) {
      unawaited(ref.read(minecraftSfxServiceProvider).ensureScene(next.id));
      // v2 A5：通知中心自动记录场景事件（P2-M6-4）
      if (previous == null || previous.id != next.id) {
        ref.read(recentNotificationsProvider.notifier).append(
              '场景',
              '切换到「${next.name}」',
            );
      }
    });

    // v2 A5：自动记录播放事件（P2-M6-4）
    ref.listen<Track?>(nowPlayingProvider, (Track? previous, Track? next) {
      if (next != null && previous?.uri != next.uri) {
        ref.read(recentNotificationsProvider.notifier).append(
              '播放',
              '${next.title} · ${next.artist}',
            );
      }
    });

    // cl61：OTA 后台下载完成 / 失败 → 全局通知（页面可已关闭，AppShell 常驻监听）。
    ref.listen<OtaDownloadState>(
      otaDownloadProvider,
      (OtaDownloadState? previous, OtaDownloadState next) {
        if (previous == null || previous.isDownloading == false) return;
        if (next.isDone) {
          appNotify(context, '新版本 ${next.tag} 已下载并通过校验，可安装更新');
        } else if (next.isError) {
          appNotify(context, '更新下载失败：${next.error ?? '未知错误'}');
        }
      },
    );

    final int pageIndex = ref.watch(shellPageIndexProvider);
    final int? selectedTab = ref.watch(selectedTabIndexProvider);
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    // 低端设备优化：省电模式关闭全屏噪点层（最大渲染开销之一）
    final bool noiseOn = ref.watch(noiseEnabledProvider);

    // R10/R11：运行期同步写回持久化（唯一触发点）
    ref.watch(settingsSyncProvider);
    // R4：EQ 播放开始补应用（唯一触发点）
    ref.watch(eqReapplyOnPlayProvider);
    // 歌名/曲名真源桥接：把引擎实际加载的曲目镜像进 nowPlayingProvider
    // （消除「选曲即写」与「加载成功才写」错位，修复曲名对不上）。
    ref.watch(nowPlayingBridgeProvider);

    return Scaffold(
      // R16：跟随全局明暗主题（不再是固定浅色 bgPage）
      backgroundColor: context.appColors.bgPage,
      // 【裁决 A3】关闭系统自动避让：Dock + MiniPlayer 是固定底部结构，
      // 让 Scaffold 整体上顶会把它们挤变形。改为只给内容区补 padding.bottom。
      resizeToAvoidBottomInset: false,
      body: LiquidGlassCapture(
        child: Stack(
        children: <Widget>[
          // ── 玻璃背景层：极淡的场景主色 + 噪点 ──
          // 一层就够了：让玻璃组件透出"背景是场景色 + 颗粒"的干净质感。
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      context.appColors.accent.withValues(alpha: 0.10),
                      context.appColors.bgPage,
                    ],
                    stops: const <double>[0, 0.6],
                  ),
                ),
              ),
            ),
          ),
          if (noiseOn)
            Positioned.fill(
              child: IgnorePointer(child: NoiseTexture(seed: 11)),
            ),
          // 主内容层
          SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  // 键盘补偿：最多压缩到只剩 _minContentHeight，避免负约束
                  final double room =
                      (constraints.maxHeight - _minContentHeight)
                          .clamp(0.0, double.infinity);
                  final double bottomPad = keyboardInset.clamp(0.0, room);

                  // 布局对齐场景页：内容(弹性) + 底部播放器(带边距)。
                  // 播放器在 ContentContainer 内部、IndexedStack 下方，
                  // 与场景页 PageScaffold.body 的「内容 + 播放面板」同构；
                  // 仅非场景页显示（场景页自带播放面板，避免双播放器）。
                  return ContentContainer(
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: bottomPad),
                            // cl53-E：非主页内容区底部做圆角（与音乐卡/玻璃
                            // 表面衔接），主页内容自带场景视频背景不裁。
                            child: pageIndex == ShellPage.home
                                ? IndexedStack(
                                    index: pageIndex,
                                    children: _pages,
                                  )
                                : ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      bottom:
                                          Radius.circular(AppRadius.lg),
                                    ),
                                    child: IndexedStack(
                                      index: pageIndex,
                                      children: _pages,
                                    ),
                                  ),
                          ),
                        ),
                        if (pageIndex != ShellPage.home) ...<Widget>[
                          const SizedBox(height: AppSpace.sm),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpace.md,
                              AppSpace.sm,
                              AppSpace.md,
                              AppSpace.sm,
                            ),
                            child: const MusicCard(),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── 底部 Dock ────────────────────────────────────
            // 【裁决 A7】手势条机型交给 SafeArea 让位；
            // 无手势条机型（padding.bottom == 0）用 minimum 兜 2dp，
            // 保证药丸不会直接贴死屏幕下沿。
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 2),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSize.shellEdgeInset,
                ),
                child: AppDock(
                  selectedIndex: selectedTab,
                  onTabSelected: (int index) => setShellPage(ref, index),
                  density: ref.watch(uiDensityProvider),
                ),
              ),
            ),
          ],
        ),
        ),
          // ── AI 陪伴全局浮层（FAB，浮在 Dock 上方）──
          //
          // ⚠️ 必须挂在**外层 Stack**，不能放进上面的 Column：
          // Column 给 child 的是无界高度，而 FAB 内部是 Stack，
          // 会触发 "A Stack requires bounded constraints" 断言。
          const Positioned.fill(child: CompanionGlobalFab()),
          // ── 全局通知 toast（右上角 3s 滑入/上浮/滑出）──
          const GlobalNotificationToast(),
        ],
      ),
      ),
    );
  }
}
