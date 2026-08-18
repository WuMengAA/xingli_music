/// ════════════════════════════════════════════════════════════════════════
/// 通用确认弹窗（Ardot 715993465945059 · 3:447「dlg-确认弹窗」）
/// ════════════════════════════════════════════════════════════════════════
///
/// 视觉：主题 / 皮肤感知的毛玻璃卡（[LiquidGlass]）+ 主题 scrim 遮罩。
/// 所有颜色走 [AppThemeColors] / token，绝不写死（约定 C1），
/// 因此弹窗随明暗主题与 6 套配色自动同步，并带液态玻璃质感。
///
/// 用法：
/// ```dart
/// final bool? confirmed = await AppConfirmDialog.show(
///   context: context,
///   title: '确认删除？',
///   message: '此操作不可撤销，确定要删除该世界存档吗？',
///   confirmLabel: '删除',
///   confirmDanger: true,   // 红底，破坏性操作
/// );
/// // 返回 true = 确认 / false = 取消 / null = 点遮罩或返回关闭
/// ```
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../widgets/liquid_glass.dart';

/// 通用确认弹窗。
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.cancelLabel = '取消',
    this.confirmLabel = '确定',
    this.confirmDanger = false,
  })  : assert(message != null || content != null,
            'message 与 content 至少提供一个');

  /// 标题（17 / w600）。
  final String title;

  /// 正文（单行 / 多行纯文本，13 / w400 / 次级色）。
  final String? message;

  /// 富文本正文（与 [message] 二选一；优先级高于 [message]）。
  final Widget? content;

  /// 取消按钮文案；为 `null` 时隐藏取消按钮（仅保留确认按钮）。
  final String? cancelLabel;

  /// 确认按钮文案。
  final String confirmLabel;

  /// 确认按钮是否危险态（红底，用于删除等破坏性操作）。
  final bool confirmDanger;

  /// 展示弹窗，返回 `true`=确认、`false`=取消、`null`=点遮罩 / 返回关闭。
  static Future<bool?> show({
    required BuildContext context,
    required String title,
    String? message,
    Widget? content,
    String? cancelLabel = '取消',
    String confirmLabel = '确定',
    bool confirmDanger = false,
    bool barrierDismissible = true,
  }) {
    final AppThemeColors colors =
        Theme.of(context).extension<AppThemeColors>() ?? AppThemeColors.light;
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: colors.scrim,
      builder: (BuildContext c) => AppConfirmDialog(
        title: title,
        message: message,
        content: content,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
        confirmDanger: confirmDanger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    final String? cancel = cancelLabel;
    final Widget body = content ??
        Text(
          message ?? '',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 1.4,
            color: colors.textSecondary,
          ),
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, minWidth: 280),
        child: SizedBox(
          width: 300,
          child: LiquidGlass(
            radius: 20,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 标题（17 / w600 / 主文字色）
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                // 正文
                body,
                const SizedBox(height: 16),
                // 操作按钮行（取消 / 确认）
                Row(
                  children: <Widget>[
                    if (cancel != null) ...<Widget>[
                      Expanded(child: _DialogButton.cancel(colors, cancel)),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: _DialogButton.confirm(
                        colors,
                        confirmLabel,
                        confirmDanger,
                        onTap: () => Navigator.of(context).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹窗操作按钮（胶囊，半径 18）。
class _DialogButton extends StatelessWidget {
  const _DialogButton.cancel(this.colors, this.label)
      : isConfirm = false,
        isDanger = false,
        onTap = null;

  const _DialogButton.confirm(
    this.colors,
    this.label,
    this.isDanger, {
    this.onTap,
  }) : isConfirm = true;

  final AppThemeColors colors;
  final String label;
  final bool isConfirm;
  final bool isDanger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color fill = isConfirm
        ? (isDanger ? colors.danger : colors.accent)
        : colors.bgSurface;
    final Color labelColor =
        isConfirm ? colors.onAccent : colors.textSecondary;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap ?? () => Navigator.of(context).pop(false),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: isConfirm
              ? null
              : BoxDecoration(
                  border: Border.all(color: colors.border, width: 1),
                  borderRadius: BorderRadius.circular(18),
                ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isConfirm ? FontWeight.w600 : FontWeight.w400,
              color: labelColor,
            ),
          ),
        ),
      ),
    );
  }
}
