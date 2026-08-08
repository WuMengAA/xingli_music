import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';

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

/// 4 个 Tab 的顺序 —— 必须与 `ShellPage` 枚举前 4 项严格一致（P0-B2）
const List<DockItem> kDockItems = <DockItem>[
  DockItem(
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome,
    label: '场景',
  ),
  DockItem(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
    label: '探索',
  ),
  DockItem(
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music,
    label: '曲库',
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
  });

  /// 当前高亮 Tab；`null` = 无 Tab 选中（Home 隐藏页，P0-B9 / V6）
  final int? selectedIndex;

  /// Tab 点击回调
  final ValueChanged<int> onTabSelected;

  /// Tab 定义（默认 [kDockItems]，注入点仅为可测试性保留）
  final List<DockItem> items;

  /// 药丸圆角 = 高度一半，由 Token 派生而非字面量（C1）
  static const double _dockRadius = AppSize.heightDock / 2;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_dockRadius),
      child: Container(
        height: AppSize.heightDock,
        decoration: BoxDecoration(
          color: AppColors.bgDock,
          borderRadius: BorderRadius.circular(_dockRadius),
          border: Border.all(color: AppColors.borderDock),
        ),
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
                    onTap: () => onTabSelected(i),
                  ),
                ),
            ],
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
class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final DockItem item;
  final bool selected;
  final VoidCallback onTap;

  static const Duration _duration = Duration(milliseconds: 200);
  static const Curve _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: AppSize.heightDock,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: _duration,
              curve: _curve,
              width: AppSize.tabIndicator,
              height: AppSize.tabIndicator,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 未选中必须是 transparent 而非 null，否则不做补间
                color: selected ? AppColors.accent : Colors.transparent,
              ),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: AppSize.icon,
                color: selected
                    ? AppColors.iconOnAccent
                    : AppColors.iconInactive,
              ),
            ),
            const SizedBox(height: 1),
            AnimatedDefaultTextStyle(
              duration: _duration,
              curve: _curve,
              style: AppText.tabLabel.copyWith(
                color: selected
                    ? AppColors.textAccent
                    : AppColors.textTertiary,
              ),
              child: Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
