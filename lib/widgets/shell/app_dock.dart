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

/// 自定义底部导航 Dock（架构 §1.3 / PRD P0-B6）
///
/// 明确**放弃** Material `NavigationBar`：M3 的 indicator 固定为 64×32 的
/// `StadiumBorder`，容器是矩形，无法满足「满宽药丸 + 内部 Ø44 正圆」的设计。
///
/// 结构（自外向内）：
/// ```
/// LiquidGlass(forceGlass, r=38) ← ① 核心浮层白名单玻璃焦点（R32）
/// └ SizedBox h=76              ← ② 固定 Dock 高度
///   └ Material(transparency)   ← ③ InkWell 需要 Material 祖先
///     └ Row → 5 × Expanded     ← ④ 严格等分（热区 ≈97×76 ≫ 44×44）
/// ```
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
  /// 无紫圆、`iconInactive` 灰图标、`textTertiary` 灰文字。
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

  @override
  Widget build(BuildContext context) {
    // 方案 C（Q1 已裁决）：底部 Dock 横屏收窄、居中限宽；竖屏保持满宽。
    // UI 自适应：紧凑屏（手表等）Dock 几乎满宽且隐藏文字标签。
    // R21：界面密度由 AppShell 注入（本组件保持纯组件、可单测）。
    final ResponsiveLayout rl = ResponsiveLayout.of(context);
    final double dockH =
        AppSize.heightDock * (density == UiDensity.compact ? 0.8 : 1.0);
    // R32 玻璃焦点：Dock 为「极简基底 + 玻璃焦点」中的唯二玻璃之一。
    // 用 LiquidGlass(forceGlass) 白名单恢复玻璃药丸（毛玻璃模糊 + 半透明 +
    // 细描边，tint/border 跟随皮肤主色），模糊强度跟随全局性能模式
    // （省电=0 直通无玻璃，均衡/流畅恢复玻璃）；基底其余页面保持原生极简。
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: rl.dockMaxWidth),
        child: LiquidGlass(
          // R32 白名单：仅核心浮层放行玻璃
          forceGlass: true,
          // 药丸圆角 = 高度一半，取自 Token（AppSize.dockRadius）
          radius: AppSize.dockRadius,
          style: GlassStyle.frosted,
          // tint/borderColor 不写死白色，跟随皮肤主色派生的玻璃语义色
          tint: context.appColors.glassTint,
          borderColor: context.appColors.glassBorder,
          child: SizedBox(
            height: dockH,
            child: Material(
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
          ),
        ),
      ),
    );
  }
}

/// 单个 Tab：Ø44 紫圆 + 26dp 图标 + 10sp 标签
///
/// 垂直排布（架构 §1.3 几何裁定，合计精确 76dp）：
/// `0–5 留白 → 5–49 Ø44 圆 → 49–50 间隙 → 50–62 标签 → 62–76 留白`
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
        height: AppSize.heightDock,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: tabDur,
              curve: AppMotion.ease,
              width: AppSize.tabIndicator,
              height: AppSize.tabIndicator,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 未选中必须是 transparent 而非 null，否则不做补间
                color: selected ? c.accent : Colors.transparent,
              ),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: AppSize.icon,
                // R32 一.5：选中态用 onAccent 语义色（强调底上文字，随主题/皮肤）
                color: selected ? c.onAccent : c.iconInactive,
              ),
            ),
            // 紧凑屏（手表等）隐藏文字标签，只留图标
            if (showLabel) ...<Widget>[
              const SizedBox(height: 1),
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
