import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_version.dart';
import 'core/terms/naming_dict.dart';
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
import 'providers/cast/now_playing_providers.dart';
import 'providers/scene/scene_providers.dart';
import 'providers/settings/notification_providers.dart';
import 'providers/settings/ota_download_provider.dart';
import 'providers/settings/offline_providers.dart';
import 'providers/settings/performance_providers.dart';
import 'providers/settings/settings_layout_provider.dart';
import 'providers/settings/settings_persistence_providers.dart';
import 'providers/shell/liquid_glass_capture_provider.dart';
import 'providers/shell/shell_providers.dart';
import 'repositories/settings_repository.dart';
import 'services/ota_service.dart';
import 'services/ota_install.dart';
import 'widgets/companion/companion_global_fab.dart';
import 'widgets/notification/app_notify.dart';
import 'widgets/shell/app_dock.dart';
import 'widgets/shell/content_container.dart';
import 'widgets/shell/frost_edge_bar.dart';
import 'widgets/shell/responsive_floating_layer.dart';
import 'widgets/shell/scroll_blur.dart';
import 'widgets/shell/tab_switch_blur.dart';
import 'widgets/playback/music_card.dart';
import 'widgets/social/order_floating_card.dart';
import 'widgets/notification/global_notification_toast.dart';
import 'widgets/common/app_confirm_dialog.dart';

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
/// Scaffold(bgPage)
/// └ Stack
///   ├ Positioned.fill → 极光渐变背景层
///   ├ Positioned.fill → 噪点层（可关）
///   ├ SafeArea(bottom:false) → ContentContainer → IndexedStack(5 页，全部保活)
///   └ ResponsiveFloatingLayer（叠加·脱离文档流）→ 播放控件 + AppDock（5 Tab）
/// ```
///
/// 播放控件与 dock 栏位于**外层 Stack 的叠加层**，不再占据 Column 文档流
/// 空间；5 个 Tab 页面自身的布局边界 / 结构 / 占位完全不受影响。为避免遮挡
/// 下层内容，内容区在 [ContentContainer] 处补等量 `bottom` 预留（高度按视口
/// 与密度估算）。叠加层随底部安全区与软键盘自适应抬升。
///
/// 🚫 **禁止**在本文件 import 任何暗色画布资产：`core/theme/` 下的动态派生
/// 主题与派生色板、`widgets/` 根目录下的噪点 / 粒子 / 调色盘 / 控制栏 /
/// 更多面板 / 音量条。取色一律走 `core/theme/light_tokens.dart`。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with SingleTickerProviderStateMixin {
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

  /// 切 Tab 的「上浮淡入」过渡（批3 #580 · B）。
  /// 仅驱动内容层渲染变换，不重建 IndexedStack（_pages 为 const，保活滚动位置）。
  late final AnimationController _tabAnim;

  @override
  void initState() {
    super.initState();
    _tabAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
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
      // 2026-08-17 渠道化：重启后检测渠道切换标记 → OOBE·升级阶段引导。
      unawaited(_maybeAskChannelGuide(context));
      // cl08：离线模式（不依靠官方服务器）→ 跳过 OTA 更新日志拉取与检查。
      if (!ref.read(offlineModeProvider)) {
        // 2026-08-17 渠道化：每次启动拉取当前渠道最新更新日志并缓存本地。
        unawaited(OtaService.instance
            .refreshCachedNotes(channel: ref.read(settingsRepositoryProvider).updateChannel));
        // cl74：启动自动检查 OTA（仅已完成为 true 的老用户；首次走 OOBE 不弹）。
        // 有新版本弹全局提示，用户可前往 设置 → 关于 → 版本更新 处理。
        if (ref.read(oobeDoneProvider)) {
          unawaited(_autoCheckOta(context));
        }
      }
    });
  }

  @override
  void dispose() {
    _tabAnim.dispose();
    super.dispose();
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
      final bool? go = await AppConfirmDialog.show(
        context: context,
        title: Terms.updated,
        content: Text(
          '检测到应用已升级（新版本已包含最新功能）。\n'
          '是否重新走一遍初始化流程？\n\n'
          '提示：重走流程只会合并设置，不会清除任何数据。',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: context.appColors.textSecondary,
          ),
        ),
        cancelLabel: Terms.skip,
        confirmLabel: Terms.reinitialize,
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

  /// 2026-08-17 渠道化：重启后检测到「渠道切换待确认」→ 弹 OOBE·升级阶段引导
  /// （说明渠道变更 + 提示检查更新），确认后清除标记。
  Future<void> _maybeAskChannelGuide(BuildContext context) async {
    try {
      final SettingsRepository repo = ref.read(settingsRepositoryProvider);
      if (!repo.channelSwitchPending) return;
      final UpdateChannel ch = repo.updateChannel;
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      await AppConfirmDialog.show(
        context: context,
        title: Terms.channelSwitched,
        content: Text(
          '已切换到「${ch.label}」。\n\n'
          '渠道决定 OTA 更新来源与更新日志：\n'
          '· Beta（稳定）：较稳定，默认推荐\n'
          '· Alpha（尝鲜）：功能更新更早\n\n'
          '可前往 设置 → 关于 → 版本更新 检查该渠道的最新版本。',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: context.appColors.textSecondary,
          ),
        ),
        cancelLabel: null,
        confirmLabel: Terms.gotIt,
      );
      await repo.setChannelSwitchPending(false);
    } catch (_) {
      // 引导失败不阻塞启动。
    }
  }

  /// cl74：启动自动检查 OTA（initState 的 post-frame 回调里调用一次）。
  /// 有新版本仅弹全局提示，不自动下载/安装；失败静默（不阻塞启动）。
  Future<void> _autoCheckOta(BuildContext context) async {
    // cl08：离线模式 → 不检查官方更新。
    if (ref.read(offlineModeProvider)) return;
    try {
      final UpdateChannel ch =
          ref.read(settingsRepositoryProvider).updateChannel;
      final OtaCheckResult r =
          await OtaService.instance.checkForUpdate(channel: ch);
      if (!context.mounted) return;
      if (r.hasUpdate && r.latestTag.isNotEmpty) {
        appNotify(context, '发现新版本 ${r.latestTag}，可前往 设置 → 关于 → 版本更新');
      }
    } catch (_) {
      // 启动检查失败不阻塞。
    }
  }

  /// cl74 / cl77：安装已下载并校验通过的更新包（供下载完成 SnackBar 的
  /// 「安装」动作；安卓 = APK 系统安装器，Windows 电脑版 = 解压替换自启）。
  Future<void> _installUpdate(String filePath) async {
    try {
      await OtaInstall.install(filePath);
    } on OtaException catch (e) {
      if (mounted) appNotify(context, e.message);
    } catch (e) {
      if (mounted) appNotify(context, '安装失败，请稍后重试');
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
              Terms.sceneSwitch,
              '切换到「${next.name}」',
            );
      }
    });

    // v2 A5：自动记录播放事件（P2-M6-4）
    ref.listen<Track?>(nowPlayingProvider, (Track? previous, Track? next) {
      if (next != null && previous?.uri != next.uri) {
        ref.read(recentNotificationsProvider.notifier).append(
                  Terms.play,
                  '${next.title} · ${next.artist}',
            );
      }
    });

    // cl61：OTA 后台下载完成 / 失败 → 全局通知（页面可已关闭，AppShell 常驻监听）。
    // cl74：下载完成直接给「安装」动作（此前只提示"可安装"却无入口）。
    ref.listen<OtaDownloadState>(
      otaDownloadProvider,
      (OtaDownloadState? previous, OtaDownloadState next) {
        if (previous == null || previous.isDownloading == false) return;
        if (next.isDone) {
          final String path = next.filePath;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('新版本 ${next.tag} 已下载并通过 SHA-256 校验'),
              action: SnackBarAction(
                label: Terms.install,
                onPressed: () => unawaited(_installUpdate(path)),
              ),
            ),
          );
        } else if (next.isError) {
          appNotify(context, '${Terms.downloadFailed}：${next.error ?? '未知错误'}');
        }
      },
    );

    final int pageIndex = ref.watch(shellPageIndexProvider);
    final double scale = ref.watch(motionScaleProvider);
    final int? selectedTab = ref.watch(selectedTabIndexProvider);
    // 批3 #580 · B：切 Tab 过渡时长跟随性能档（motionScale）。
    _tabAnim.duration = Duration(milliseconds: (280 * scale).round());
    // 批3 #580 · A：切 Tab 时复位滚动磨砂进度（新页尚未滚动，条边保持隐藏）。
    ref.listen<int>(shellPageIndexProvider, (int? _, int __) {
      ref.read(pageScrollBlurProvider.notifier).state = 0;
      // 批3 #580 · B：切 Tab 触发内容「上浮淡入」过渡（不重建页面，滚动位置保活）。
      _tabAnim.forward(from: 0);
    });

    // 悬浮层（播放控件 + dock）脱离文档流后的底部预留：保证下层 5 个 Tab
    // 页面内容不被遮挡，且页面自身布局 / 占位完全不变（仅 AppShell 这一层
    // 补高度）。dock 高度随密度收缩。
    final UiDensity density = ref.watch(uiDensityProvider);
    final double dockH =
        AppSize.heightDock * (density == UiDensity.compact ? 0.8 : 1.0);
    // R32：iOS26 悬浮 Dock——离底间隙（浮于底部之上），预留随间隙同步增高。
    final double dockFloatGap = AppSize.dockFloatGap;
    // R32 一.1：移除 Dock 上方的空白边界限制区域。
    // 播放控件是玻璃焦点（半透明模糊），内容滑入其下自然透出、与浮层浑然
    // 一体，无需再为它强制留白；仅保留 Dock 高度（实底选中态）的底部防遮挡。
    final double floatingReserve = dockH + dockFloatGap;

    // R10/R11：运行期同步写回持久化（唯一触发点）
    ref.watch(settingsSyncProvider);
    // R4：EQ 播放开始补应用（唯一触发点）
    ref.watch(eqReapplyOnPlayProvider);
    // 歌名/曲名真源桥接：把引擎实际加载的曲目镜像进 nowPlayingProvider
    // （消除「选曲即写」与「加载成功才写」错位，修复曲名对不上）。
    ref.watch(nowPlayingBridgeProvider);
    // clOTA/ClassIsland 联动：Windows 端常驻启动 NowPlaying 状态服务
    // （/nowplaying /health /control，协议见 docs/方案_ClassIsland联动.md）。
    ref.watch(nowPlayingLocalBridgeProvider);

    return Scaffold(
      // R16：跟随全局明暗主题（不再是固定浅色 bgPage）
      backgroundColor: context.appColors.bgPage,
      // 【裁决 A3】关闭系统自动避让：Dock + MiniPlayer 是固定底部结构，
      // 让 Scaffold 整体上顶会把它们挤变形。改为只给内容区补 padding.bottom。
      resizeToAvoidBottomInset: false,
      body: LiquidGlassCapture(
        child: Stack(
        children: <Widget>[
          // 主内容层（iOS 化：移除极光渐变 + 噪点背景层，Scaffold bgPage
          // 直接承担 systemBackground 底色，毛玻璃组件自带材质质感）
          SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  // 底部预留：等于悬浮层（播放控件 + dock）高度，保证下层内容
                  // 不被遮挡；键盘补偿已由此前 resizeToAvoidBottomInset:false
                  // 转为叠加层自行抬升，此处不再叠加 keyboardInset。
                  final double room =
                      (constraints.maxHeight - _minContentHeight)
                          .clamp(0.0, double.infinity);
                  final double bottomPad = floatingReserve.clamp(0.0, room);

                  // 内容区（弹性）承载 IndexedStack(5 页)。播放控件与 dock 已
                  // 移至外层 Stack 的叠加层（[ResponsiveFloatingLayer]），此处
                  // 仅补 bottom 预留；5 个 Tab 自身布局 / 占位完全不变。
                  return NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification n) {
                      // 批3 #580 · A：捕获活动页滚动，驱动顶部/底部磨砂边淡入。
                      final double px = n.metrics.pixels;
                      final double p = scrollBlurProgress(px);
                      if ((ref.read(pageScrollBlurProvider) - p).abs() > 0.01) {
                        ref.read(pageScrollBlurProvider.notifier).state = p;
                      }
                      return false;
                    },
                    child: ContentContainer(
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: bottomPad),
                            // R32 一.1：移除内容区底部圆角裁切（cl53-E 原为
                            // 与玻璃表面衔接，原生极简下玻璃表面已无，圆角仅是
                            // 多余的边角约束）；5 页统一无圆角直通。
                child: AnimatedBuilder(
                  animation: _tabAnim,
                  builder: (BuildContext context, Widget? _) {
                    // 批3 #580 · B：切 Tab 时内容上浮 10px + 淡入 0.82→1.0。
                    // IndexedStack 每帧以最新 pageIndex 重建，但 _pages 为 const，
                    // 子页 element 按位置 + 类型复用，滚动位置不丢（不破坏 C11）。
                    final double v = _tabAnim.value;
                    return Transform.translate(
                      offset: Offset(0, (1 - v) * 10),
                      child: Opacity(
                        opacity: 0.82 + 0.18 * v,
                        child: IndexedStack(
                          index: pageIndex,
                          children: _pages,
                        ),
                      ),
                    );
                  },
                ),
                          ),
                        ),
                      ],
                    ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        ),
          // ── 批3 #580 · A 顶部磨砂边（滑动模糊过渡 · 顶）──
          // 浮于内容上缘（状态栏下方），随活动页滚动淡入；停在顶部时自动隐藏。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: true,
              bottom: false,
              child: SizedBox(
                height: 22,
                child: const FrostEdgeBar(top: true),
              ),
            ),
          ),
          // ── 批3 #580 · A+B 底部 Dock 融合磨砂边（滚动磨砂 + 常驻羽化，单 BackdropFilter）──
          // 合并原底部 FrostEdgeBar(top:false) 与 DockTopFeather，省去两层重叠模糊采样。
          Positioned(
            left: 0,
            right: 0,
            bottom: floatingReserve,
            height: 22,
            child: const DockBlendEdge(),
          ),
          // ── 批3 #580 · C 切 Tab 进出场磨砂脉冲 ──
          // 绘于 Dock / 浮层之下，切换页面时对内容区做一次短暂整屏磨砂脉冲，
          // 让 Tab 切换柔和过渡（模糊过渡而非硬切）。
          const Positioned.fill(child: TabSwitchBlurPulse()),
          // ── 悬浮层：播放控件 + dock 栏（脱离文档流，叠加于内容之上）──
          // 两枚独立浮层（播放控件在上、dock 在下）由 [ResponsiveFloatingLayer]
          // 自适应锚定到屏幕底部：窄屏贴近边缘、宽屏收窄居中，随安全区/键盘抬升。
          // 绘制顺序在本层 → FAB → 通知 toast，故 FAB 仍浮于 dock 之上。
          ResponsiveFloatingLayer(
            bottomGap: dockFloatGap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // R32 ④：点歌悬浮窗——叠在底部媒体栏（MusicCard）之上方，
                // 浮出点歌卡片（DJ 审批 / 听众状态），不覆盖媒体控制区。
                Stack(
                  children: <Widget>[
                    const MusicCard(),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: AppSize.heightMiniGroup,
                      child: OrderFloatingCard(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                AppDock(
                  selectedIndex: selectedTab,
                  onTabSelected: (int index) => setShellPage(ref, index),
                  density: density,
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
