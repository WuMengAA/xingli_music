/// ════════════════════════════════════════════════════════════════════════
/// 实验同意门（预设组件 · Task #524）
/// ════════════════════════════════════════════════════════════════════════
///
/// 还原 Ardot 设计 `dlg-实验同意门`（3:553 / 3:554）：
///   - 标题「实验功能」+ 说明正文
///   - 「我已了解相关风险」勾选框（未勾选时「开启实验」按钮禁用）
///   - 「暂不开启」(描边) / 「开启实验」(强调色) 双按钮
///
/// 外观完全跟随主题 / 皮肤：玻璃用 [LiquidGlass]，所有颜色取自 `context.appColors`，
/// 不写死任何品牌色。
///
/// 用法：
/// ```dart
/// final ExperimentConsentResult? r = await ExperimentConsentGate.show(
///   context: context,
///   message: '该实验功能仍在测试，可能产生不稳定表现。',
/// );
/// if (r == ExperimentConsentResult.accepted) { /* 开启实验 */ }
/// ```
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../widgets/liquid_glass.dart';

/// 实验同意门的结果。
enum ExperimentConsentResult {
  /// 已勾选风险声明并点击「开启实验」。
  accepted,

  /// 点击「暂不开启」。
  declined,
}

/// 实验同意门对话框。
class ExperimentConsentGate extends StatefulWidget {
  const ExperimentConsentGate({
    super.key,
    this.title = '实验功能',
    this.message = '该实验功能仍在测试，可能产生不稳定表现。',
    this.ackLabel = '我已了解相关风险',
    this.acceptLabel = '开启实验',
    this.declineLabel = '暂不开启',
  });

  final String title;
  final String message;
  final String ackLabel;
  final String acceptLabel;
  final String declineLabel;

  /// 以居中对话框展示，返回 [ExperimentConsentResult]，点遮罩关闭则为 `null`。
  static Future<ExperimentConsentResult?> show({
    required BuildContext context,
    String title = '实验功能',
    String message = '该实验功能仍在测试，可能产生不稳定表现。',
    String ackLabel = '我已了解相关风险',
    String acceptLabel = '开启实验',
    String declineLabel = '暂不开启',
    bool barrierDismissible = true,
  }) {
    final AppThemeColors colors = context.appColors;
    return showDialog<ExperimentConsentResult>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: colors.scrim,
      builder: (BuildContext c) => ExperimentConsentGate(
        title: title,
        message: message,
        ackLabel: ackLabel,
        acceptLabel: acceptLabel,
        declineLabel: declineLabel,
      ),
    );
  }

  @override
  State<ExperimentConsentGate> createState() => _ExperimentConsentGateState();
}

class _ExperimentConsentGateState extends State<ExperimentConsentGate> {
  bool _ack = false;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
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
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.message,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _AckRow(
                  colors: colors,
                  label: widget.ackLabel,
                  value: _ack,
                  onChanged: (bool v) => setState(() => _ack = v),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _GateButton.cancel(
                        colors: colors,
                        label: widget.declineLabel,
                        onTap: () =>
                            Navigator.of(context).pop(ExperimentConsentResult.declined),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GateButton.accept(
                        colors: colors,
                        label: widget.acceptLabel,
                        enabled: _ack,
                        onTap: _ack
                            ? () => Navigator.of(context)
                                .pop(ExperimentConsentResult.accepted)
                            : null,
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

/// 「我已了解相关风险」勾选行。
class _AckRow extends StatelessWidget {
  const _AckRow({
    required this.colors,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final AppThemeColors colors;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        children: <Widget>[
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: value ? colors.accent : Colors.transparent,
              border: Border.all(
                color: value ? colors.accent : colors.border,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: value
                ? Icon(Icons.check, size: 14, color: colors.onAccent)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 同意门按钮（取消=描边，开启=强调色；开启可禁用）。
class _GateButton extends StatelessWidget {
  const _GateButton.cancel({
    required this.colors,
    required this.label,
    this.onTap,
  })  : isAccept = false,
        enabled = true;

  const _GateButton.accept({
    required this.colors,
    required this.label,
    this.enabled = true,
    this.onTap,
  }) : isAccept = true;

  final AppThemeColors colors;
  final String label;
  final bool isAccept;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool active = isAccept && enabled;
    final Color fill = isAccept
        ? (enabled ? colors.accent : colors.accent.withValues(alpha: 0.4))
        : colors.bgSurface;
    final Color labelColor =
        isAccept ? colors.onAccent : colors.textSecondary;
    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isAccept ? fill : colors.border,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: 32,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isAccept ? FontWeight.w600 : FontWeight.w400,
                color: active || !isAccept ? labelColor : colors.onAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
