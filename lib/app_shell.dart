import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/light_tokens.dart';
import 'models/scene.dart';
import 'pages/explore/explore_page.dart';
import 'pages/home/home_page.dart';
import 'pages/library/library_page.dart';
import 'pages/now_playing/now_playing_page.dart';
import 'pages/scene/scene_page.dart';
import 'pages/settings/settings_page.dart';
import 'providers/audio/audio_providers.dart';
import 'providers/scene/scene_providers.dart';
import 'providers/shell/shell_providers.dart';
import 'widgets/shell/app_dock.dart';
import 'widgets/shell/content_container.dart';
import 'widgets/shell/mini_player.dart';

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
///   └ SafeArea(bottom) → AppDock（4 Tab）
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
  static const List<Widget> _pages = <Widget>[
    ScenePage(), //   0 · 场景
    ExplorePage(), // 1 · 探索
    LibraryPage(), // 2 · 曲库
    SettingsPage(), //3 · 设置
    HomePage(), //    4 · 首页（隐藏页，无 Tab 高亮）
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
    });
  }

  @override
  Widget build(BuildContext context) {
    // 「我的世界」主题音效调度：场景切换时自动启停（同样是全局副作用）
    ref.listen<Scene>(activeSceneProvider, (Scene? previous, Scene next) {
      unawaited(ref.read(minecraftSfxServiceProvider).ensureScene(next.id));
    });

    final int pageIndex = ref.watch(shellPageIndexProvider);
    final int? selectedTab = ref.watch(selectedTabIndexProvider);
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      // 【裁决 A3】关闭系统自动避让：Dock + MiniPlayer 是固定底部结构，
      // 让 Scaffold 整体上顶会把它们挤变形。改为只给内容区补 padding.bottom。
      resizeToAvoidBottomInset: false,
      body: SafeArea(
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

                  return ContentContainer(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomPad),
                      child: IndexedStack(
                        index: pageIndex,
                        children: _pages,
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── 迷你播放器（全局唯一，P0-D1 / V5）─────────────
            // 与下方 Dock 共用 shellEdgeInset：两者同为"贴边浮起的操作条"，
            // 必须同进同退。若只给 Dock 加边距，Token 一旦改成非 0
            // 就会出现"播放器满宽、Dock 内缩"的错位。
            const SizedBox(height: AppSpace.sm),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSize.shellEdgeInset,
              ),
              child: MiniPlayer(
                // T05：左胶囊点击 → 打开完整播放页（P1-04）
                onOpenNowPlaying: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NowPlayingPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpace.sm),

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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
