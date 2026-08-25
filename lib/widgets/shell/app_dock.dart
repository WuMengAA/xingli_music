import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/terms/naming_dict.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/performance_providers.dart';
import '../liquid_glass.dart';

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
const List<DockItem> kDockItems = <DockItem>[
  DockItem(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: Terms.tabHome,
  ),
  DockItem(
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music,
    label: Terms.tabLibrary,
  ),
  DockItem(
    icon: Icons.public_outlined,
    selectedIcon: Icons.public,
    label: Terms.tabWorld,
  ),
  DockItem(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
    label: Terms.tabExplore,
  ),
  DockItem(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: Terms.tabSettings,
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
    this.items = kDockItems,
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

  /// Tab 定义（默认 [kDockItems]，注入点仅为可测试性保留）
  final List<DockItem> items;

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
    // 玻璃焦点：Dock 为「极简基底 + 玻璃焦点」中的唯二玻璃之一。
    // iOS TabBar 用整条 thick 毛玻璃（radius=0 直角条，顶部随浮层自然衔接），
    // 模糊强度跟随全局性能模式（省电=0 直通无玻璃，均衡/流畅恢复玻璃）。
    return LiquidGlass(
      // R32 白名单：仅核心浮层放行玻璃
      forceGlass: true,
      // 整条直角条（iOS TabBar 无圆角药丸）
      radius: 0,
      style: GlassStyle.frosted,
      // tint/borderColor 跟随 systemBlue 派生的玻璃语义色（去紫）
      tint: context.appColors.glassTint,
      // cl13：iOS TabBar 无四边框 —— 取消 LiquidGlass 的整框 Border.all，
      // 改为顶部 1px hairline 分隔线（iOS TabBar 特征）。
      borderColor: Colors.transparent,
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
                  for (int i = 0; i < items.length; i++)
                    Expanded(
                      child: _DockTab(
                        item: items[i],
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
