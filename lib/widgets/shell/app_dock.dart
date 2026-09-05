import 'package:flutter/material.dart';
import 'package:liquid_glass_compat/liquid_glass_compat.dart';

import '../../l10n/app_localizations.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../providers/settings/performance_providers.dart' show UiDensity;

/// Dock 单个 Tab 的静态描述
@immutable
class DockItem {
  /// 未选中图标
  final IconData icon;

  /// 选中图标
  final IconData selectedIcon;

  /// 文字标签
  final String label;

  const DockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 6 个 Tab 的顺序 —— 必须与 `ShellPage` 的页面常量
/// （`home=0 / library=1 / world=2 / explore=3 / voicehub=4 / settings=5`）严格一致。
///
/// 注意 `ShellPage` 是 `abstract final class` 的 int 常量集合，**不是 Dart enum**，
/// 因此没有 `.values`，两边顺序只能靠本注释与 code review 约束。
/// cl07：标签文案由 l10n 提供（i18n，跟随当前语言）。
List<DockItem> buildDockItems(AppLocalizations l10n) => <DockItem>[
  DockItem(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: l10n.tabHome,
  ),
  DockItem(
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music,
    label: l10n.tabLibrary,
  ),
  DockItem(
    icon: Icons.public_outlined,
    selectedIcon: Icons.public,
    label: l10n.tabWorld,
  ),
  DockItem(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
    label: l10n.tabExplore,
  ),
  DockItem(
    icon: Icons.voice_chat_outlined,
    selectedIcon: Icons.voice_chat,
    label: l10n.tabVoiceHub,
  ),
  DockItem(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: l10n.tabSettings,
  ),
];

/// 自定义底部导航 Dock（液态玻璃底部标签栏 · WebGL 版）
///
/// 【WebGL 化】底层渲染改用 `liquid_glass_compat` 的 `GlassDock` ——
/// 移植自 `martin65536/liquid-glass-webgl`（WebGL 版）+ AndroidLiquidGlass：
/// - 整条 64dp 玻璃胶囊容器（G2 连续曲率 SDF 圆角）
/// - 选中指示器胶囊随 x 临界阻尼弹簧滑动（忠实 dampedDragAnimation）
/// - 玻璃容器 = 半透明 tint + 背景模糊 + 顶部高光带 + 细描边
///
/// 背景：此前用 `liquid_glass_widgets` 的 AdaptiveGlass，在 Android 真机走
/// Skia/GLES 回落，效果退化成接近原生 —— 用户实测"完全是原生效果"。
/// 本组件切换为 WebGL 移植实现，Dock 显示真实的液态玻璃底部标签栏。
///
/// 结构（自外向内）：
/// ```
/// GlassDock                                   ← ① WebGL 液态玻璃胶囊
/// └ GlassSurface(blur + tint + highlight)     ← ② 玻璃容器（G2 圆角）
///   └ Row → N × Expanded(_DockTab)            ← ③ 严格等分 Tab
///     └ 指示器胶囊（弹簧物理 + SDF 圆角）       ← ④ 选中指示器
/// ```
///
/// 宽度由外层 [ResponsiveFloatingLayer] 控制（窄屏满宽 / 大屏居中限宽），
/// 本组件只负责「玻璃胶囊 + 等分 Tab」，保持纯组件、可单测。
///
/// 本组件**不读任何 provider**（纯组件、可单测），状态由 `AppShell` 注入。
class AppDock extends StatelessWidget {
  const AppDock({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    this.items,
    this.density = UiDensity.standard,
  });

  /// 界面密度（R21：紧凑 0.8× 高度）。
  final UiDensity density;

  /// 当前高亮 Tab 下标（0..3）。
  ///
  /// ### 隐藏页全灰约定（P0-B9 / V6）—— 唯一实现点
  /// 传入 `null` 表示「当前不在任何 Tab 页」（即处于 Home 隐藏页，
  /// 或已 push 到脱离 Shell 的沉浸画布）。此时下方 `selectedIndex == i`
  /// 对 4 个 Tab **全部为 false**，于是 4 个 Tab 一致渲染为未选中态：
  /// 灰图标、`textTertiary` 灰文字。
  ///
  /// 这个「全灰」是 `null` 自然推导出来的结果，**不需要也禁止**再写
  /// `if (isHome)` 之类的特判分支——多一个分支就多一处不同步风险。
  ///
  /// 调用方必须传 `selectedTabIndexProvider` 的值（它已封装
  /// `isTab(page) ? page : null` 的派生逻辑），**禁止**直接传
  /// `shellPageIndexProvider`，否则 Home（index 4）会因为下标越界而
  /// 静默不高亮，看起来"碰巧对了"，实则绕过了契约。
  final int? selectedIndex;

  /// Tab 点击回调
  final ValueChanged<int> onTabSelected;

  /// Tab 定义（默认 null → 按当前语言用 [buildDockItems] 构建；注入点仅为可测试性保留）
  final List<DockItem>? items;

  /// iOS TabBar 标准高度（紧凑态按比例收缩）。
  static const double kTabBarHeight = 50;

  @override
  Widget build(BuildContext context) {
    // WebGL 液态玻璃底部标签栏：用 GlassDock（liquid-glass-webgl 移植）渲染。
    // R21：界面密度由 AppShell 注入（本组件保持纯组件、可单测）。
    final ResponsiveLayout rl = ResponsiveLayout.of(context);
    final double dockH =
        kTabBarHeight * (density == UiDensity.compact ? 0.8 : 1.0);
    // cl07：标签按当前语言构建（未注入 items 时）。
    final List<DockItem> dockItems =
        items ?? buildDockItems(AppLocalizations.of(context));

    return GlassDock(
      // 与旧满宽直角条不同：WebGL 玻璃胶囊自带左右留白（horizontalPadding），
      // 形状即"液态玻璃底部标签栏"（忠实 liquid-glass-webgl TABS_PAD）。
      items: <GlassDockItem>[
        for (final DockItem d in dockItems)
          GlassDockItem(
            icon: d.icon,
            selectedIcon: d.selectedIcon,
            label: d.label,
          ),
      ],
      // null → 隐藏页全灰（GlassDock 已支持 int? selectedIndex）。
      selectedIndex: selectedIndex,
      onSelected: (int index) => onTabSelected(index),
      // R21：紧凑密度收缩高度 + 隐藏文字标签（只留图标）。
      containerHeight: dockH,
      horizontalPadding: density == UiDensity.compact ? 24 : 36,
      showLabels: rl.dockShowLabels && density != UiDensity.compact,
      // 跟随皮肤主色派生语义色。
      accentColor: context.appColors.accent,
    );
  }
}
