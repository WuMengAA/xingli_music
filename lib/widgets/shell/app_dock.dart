import 'package:flutter/material.dart';

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

/// 自定义底部导航 Dock（平面抽象风格 · 标准 BackdropFilter 透明模糊胶囊）
///
/// 2026-09-06 方向修正：原 [liquid_glass_compat] 的 [GlassDock]（WebGL 液态玻璃）
/// 在真机到处有显示 bug、不可用。改为常规 [Container] + [BackdropFilter] 的可靠
/// 透明胶囊，外观干净、跨平台零问题。
///
/// 结构（自外向内）：
/// ```
/// Container(透明填充 + 细描边 + 圆角)        ← 玻璃胶囊
/// └ ClipRRect + BackdropFilter               ← 背景模糊
///   └ Row → N × Expanded(_DockTab)           ← 严格等分 Tab
///     └ 图标 + 可选文字标签                    ← 选中态跟随皮肤主色
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

  /// 当前高亮 Tab 下标（0..5）。
  ///
  /// ### 隐藏页全灰约定（P0-B9 / V6）—— 唯一实现点
  /// 传入 `null` 表示「当前不在任何 Tab 页」（即处于 Home 隐藏页，
  /// 或已 push 到脱离 Shell 的沉浸画布）。此时下方 `selectedIndex == i`
  /// 对 6 个 Tab **全部为 false**，于是 6 个 Tab 一致渲染为未选中态：
  /// 灰图标、`textTertiary` 灰文字。
  final int? selectedIndex;

  /// Tab 点击回调
  final ValueChanged<int> onTabSelected;

  /// Tab 定义（默认 null → 按当前语言用 [buildDockItems] 构建；注入点仅为可测试性保留）
  final List<DockItem>? items;

  /// iOS TabBar 标准高度（紧凑态按比例收缩）。
  static const double kTabBarHeight = 50;

  @override
  Widget build(BuildContext context) {
    final ResponsiveLayout rl = ResponsiveLayout.of(context);
    final double dockH =
        kTabBarHeight * (density == UiDensity.compact ? 0.8 : 1.0);
    final List<DockItem> dockItems =
        items ?? buildDockItems(AppLocalizations.of(context));
    final bool showLabels = rl.dockShowLabels && density != UiDensity.compact;
    final Color accent = context.appColors.accent;
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: dockH,
      margin: EdgeInsets.symmetric(
        horizontal: density == UiDensity.compact ? 24 : 36,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(dockH / 2),
        border: Border.all(
          color: Colors.white.withValues(alpha: dark ? 0.16 : 0.5),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(dockH / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < dockItems.length; i++)
                _DockTab(
                  item: dockItems[i],
                  selected: selectedIndex == i,
                  showLabel: showLabels,
                  accent: accent,
                  onTap: () => onTabSelected(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个 Dock Tab（图标 + 可选文字标签，选中态跟随皮肤主色）。
class _DockTab extends StatelessWidget {
  final DockItem item;
  final bool selected;
  final bool showLabel;
  final Color accent;
  final VoidCallback onTap;

  const _DockTab({
    required this.item,
    required this.selected,
    required this.showLabel,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = selected
        ? accent
        : (dark ? Colors.white70 : Colors.black54);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                selected ? item.selectedIcon : item.icon,
                color: fg,
                size: 22,
              ),
              if (showLabel)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    item.label,
                    style: TextStyle(color: fg, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
