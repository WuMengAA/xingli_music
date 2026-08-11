import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive_layout.dart';
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

/// 4 个 Tab 的顺序 —— 必须与 `ShellPage` 的前 4 个页面常量
/// （`scene=0 / library=1 / explore=2 / settings=3`）严格一致（P0-B2）。
///
/// v3 调整：曲库提前到第二位、探索后移（用户需求）。
/// 注意 `ShellPage` 是 `abstract final class` 的 int 常量集合，**不是 Dart enum**，
/// 因此没有 `.values`，两边顺序只能靠本注释与 code review 约束。
const List<DockItem> kDockItems = <DockItem>[
  DockItem(
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome,
    label: '场景',
  ),
  DockItem(
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music,
    label: '曲库',
  ),
  DockItem(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
    label: '探索',
  ),
  DockItem(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: '设置',
  ),
];

/// 自定义底部导航 Dock（架构 §1.3 / PRD P0-B6）
///
/// 明确**放弃** Material `NavigationBar`：M3 的 indicator 固定为 64×32 的
/// `StadiumBorder`，容器是矩形，无法满足「满宽药丸 + 内部 Ø44 正圆」的设计。
///
/// 结构（自外向内）：
/// ```
/// ClipRRect(r=38)            ← ① 水波纹裁剪兜底，必须在最外层
/// └ Container h=76 #E6E6E6 + 1px 白描边
///   └ Material(transparency) ← ② InkWell 需要 Material 祖先
///     └ Row → 4 × Expanded   ← ③ 严格等分（热区 ≈97×76 ≫ 44×44）
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
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: rl.dockMaxWidth),
        child: ClipRRect(
          // 药丸圆角 = 高度一半，取自 Token（AppSize.dockRadius），不另立常量
          borderRadius: BorderRadius.circular(AppSize.dockRadius),
          child: Container(
            height: dockH,
            // 液态玻璃：半透明 + 背景模糊 + 边缘高光
            decoration: BoxDecoration(
              color: Colors.transparent,
            ),
            clipBehavior: Clip.antiAlias,
              child: LiquidGlass(
                radius: AppSize.dockRadius,
                // 与统一播放器同为毛玻璃（frosted），背景透出 AppShell 玻璃层
                style: GlassStyle.frosted,
                // blur 跟随全局性能模式
                tint: const Color(0x1AFFFFFF),

                child: SizedBox(
                height: dockH,
                child: Material(
                  type: MaterialType.transparency,
                  child: Row(
                    // 4 个 Expanded 严格等分，中间不插 SizedBox —— 才能对齐
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
                color: selected ? Colors.white : c.iconInactive,
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
