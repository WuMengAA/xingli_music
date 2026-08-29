import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/performance_providers.dart';

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

/// 5 个 Tab 的顺序 —— 必须与 `ShellPage` 的页面常量
/// （`home=0 / library=1 / world=2 / explore=3 / settings=4`）严格一致。
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
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: l10n.tabSettings,
  ),
];

/// 自定义底部导航 Dock（iOS 风格 TabBar · cl13）
///
/// 【iOS 化】对齐 iOS `UITabBar` 观感：整条满宽毛玻璃条（thick 材质），
/// 取消原「满宽药丸 + 内部 Ø44 正圆」设计；选中态不再是蓝圆底，
/// 而是**图标与文字直接变蓝**（systemBlue），与 iOS TabBar 一致。
///
/// 结构（自外向内）：
/// ```
/// LiquidGlass(forceGlass, radius:0) ← ① 整条毛玻璃（iOS TabBar 材质）
/// └ SizedBox h=50（紧凑 40）        ← ② iOS 标准 TabBar 高度
///   └ Material(transparency)        ← ③ InkWell 需要 Material 祖先
///     └ Row → N × Expanded          ← ④ 严格等分（热区 ≫ 44×44）
/// ```
///
/// 宽度由外层 [ResponsiveFloatingLayer] 控制（窄屏满宽 / 大屏居中限宽），
/// 本组件只负责「整条条 + 等分 Tab」，保持纯组件、可单测。
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
    // iOS 化：整条满宽 TabBar（取消药丸圆角 + 外边距），宽度由外层
    // ResponsiveFloatingLayer 自适应（窄屏满宽 / 大屏居中限宽）。
    // R21：界面密度由 AppShell 注入（本组件保持纯组件、可单测）。
    final ResponsiveLayout rl = ResponsiveLayout.of(context);
    final double dockH =
        kTabBarHeight * (density == UiDensity.compact ? 0.8 : 1.0);
    // cl07：标签按当前语言构建（未注入 items 时）。
    final List<DockItem> dockItems =
        items ?? buildDockItems(AppLocalizations.of(context));
    // 玻璃焦点：Dock 为「极简基底 + 玻璃焦点」中的唯二玻璃之一。
    // ⚠️ 稳定性修复（0.26.8.29 实测）：liquid_glass_widgets 的 AdaptiveGlass
    // 走 own-layer 合成，在 Windows 底部浮层里不稳定 → 整条 dock 不绘制。
    // 改回系统原生 BackdropFilter 磨砂条——这正是 iOS TabBar 本体（systemBar
    // 材质），双端稳定可见、零依赖第三方 layer 合成。模糊强度跟随全局性能模式。
    final Brightness bright = Theme.of(context).brightness;
    final Color barColor = bright == Brightness.dark
        ? const Color(0xB31C1C1E) // iOS dark systemBar
        : const Color(0xCCF2F2F7); // iOS light systemBar
    // 磨砂强度固定（dock 保持纯组件、可读 provider，便于单测）。
    const double blur = 18;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          color: barColor,
          child: SizedBox(
            height: dockH,
            child: Stack(
              children: <Widget>[
                // iOS TabBar 顶部 hairline（1px separator，跟随明暗主题）。
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    color: context.appColors.divider.withValues(alpha: 0.6),
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: Row(
                    // 各 Tab 严格等分（数量随 items 变化），中间不插 SizedBox —— 才能对齐
                    // 设计坐标 x=0/104/208/312（390dp 基准）。
                    children: <Widget>[
                      for (int i = 0; i < dockItems.length; i++)
                        Expanded(
                          child: _DockTab(
                            item: dockItems[i],
                            selected: selectedIndex == i,
                            // R22：紧凑密度强制隐藏文字标签（只留图标，效果明显）
                            showLabel: rl.dockShowLabels &&
                                density != UiDensity.compact,
                            onTap: () => onTabSelected(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个 Tab：图标 + 标签（iOS TabBar 风格）
///
/// 选中态：**图标 + 文字直接变蓝**（systemBlue），不再有 Ø44 圆底。
/// 未选中：灰图标 + `textTertiary` 灰文字。
class _DockTab extends ConsumerWidget {
  const _DockTab({
    required this.item,
    required this.selected,
    required this.onTap,
    this.showLabel = true,
  });

  final DockItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    // 省电模式：动画时长减半，接近瞬时（用户要求：去除动画、提流畅度）
    final double motionScale = ref.watch(motionScaleProvider);
    final Duration tabDur =
        AppMotion.tab * motionScale;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: AppDock.kTabBarHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              selected ? item.selectedIcon : item.icon,
              size: AppSize.icon,
              // iOS TabBar：选中 = systemBlue，未选中 = 灰
              color: selected ? c.accent : c.iconInactive,
            ),
            // 紧凑屏（手表等）隐藏文字标签，只留图标
            if (showLabel) ...<Widget>[
              // iOS TabBar 图标与标签间距约 2px。
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: tabDur,
                curve: AppMotion.ease,
                style: context.appText.tabLabel.copyWith(
                  color: selected ? c.accent : c.textTertiary,
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
