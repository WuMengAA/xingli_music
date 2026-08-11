/// ════════════════════════════════════════════════════════════════════════
/// 视角切换按钮（独立组件）
/// ════════════════════════════════════════════════════════════════════════
///
/// 只负责「触发视角切换」这一件事：点击调用 [onPressed]，由外部传入具体的
/// 切换实现（如循环 2.5D / 俯瞰 / 第一人称 / 第三人称）。
///
/// 设计要点（对应需求）：
/// - **独立封装**：不内嵌任何其它游戏控件逻辑，便于复用与单测。
/// - **清晰视觉标识**：胶囊外形 + 图标 + 文案；[active] 时用强调色高亮当前态。
/// - **可访问性**：`Semantics(button: true)` 标注语义角色 + [semanticsLabel]；
///   `Tooltip` 提供悬停 / 聚焦提示。
/// - **外部实现**：通过 [onPressed] 回调传入实际切换逻辑，本组件不依赖任何
///   具体视角枚举或页面状态。
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';

/// 视角切换按钮。
class ViewModeButton extends StatelessWidget {
  const ViewModeButton({
    super.key,
    required this.onPressed,
    this.icon = Icons.threesixty,
    this.label = '视角',
    this.tooltip,
    this.semanticsLabel,
    this.active = false,
    this.compact = false,
  });

  /// 点击回调：外部传入具体视角切换实现（本组件不直接切换视角）。
  final VoidCallback onPressed;

  /// 图标（默认用 360° 视角图标）。
  final IconData icon;

  /// 文案（默认「视角」；可传当前模式名如「俯瞰」「第一人称」）。
  final String label;

  /// 悬停 / 聚焦提示；缺省用 [label]。
  final String? tooltip;

  /// 无障碍标签；缺省用 [tooltip] 或 [label]。
  final String? semanticsLabel;

  /// 是否处于激活态（如当前正处于非默认视角），用于高亮提示。
  final bool active;

  /// 紧凑模式：只显示图标（省空间，触感区域仍 ≥ 44dp）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String semantic = semanticsLabel ?? tooltip ?? label;
    final Widget content = compact
        ? Icon(icon, size: 22)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20),
              const SizedBox(width: 6),
              Text(label),
            ],
          );

    return Semantics(
      button: true,
      label: semantic,
      child: Tooltip(
        message: tooltip ?? label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            splashColor: context.appColors.accent.withValues(alpha: 0.30),
            highlightColor: context.appColors.accent.withValues(alpha: 0.18),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: compact
                  ? const EdgeInsets.all(11)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: active
                    ? context.appColors.accent.withValues(alpha: 0.55)
                    : const Color(0x59000000),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x40FFFFFF)),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Color(0xFFF2F5FA),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
