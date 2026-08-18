/// ════════════════════════════════════════════════════════════════════════
/// 场景评估底部弹层（预设组件 · Task #521）
/// ════════════════════════════════════════════════════════════════════════
///
/// 还原 Ardot 设计 `sheet-场景评估`（3:455 / 3:456）：
///   - 顶部抓手小条（grabber）+ 标题「场景评估」
///   - 多行「标签 / 取值」对照（随机种子、相机坐标、偏航俯仰、FOV、时相、音景…）
///   - 底部强调色「关闭」按钮
///
/// 外观完全跟随主题 / 皮肤：玻璃用 [LiquidGlass]（毛玻璃 / 液态玻璃双模式），
/// 所有颜色取自 `context.appColors`，不写死任何品牌色。
///
/// 用法：
/// ```dart
/// await SceneEvalSheet.show(
///   context: context,
///   title: '场景评估',
///   rows: <SceneEvalRow>[
///     SceneEvalRow(label: '随机种子', value: '0x7F3A9C'),
///     SceneEvalRow(label: '相机 X / Y / Z', value: '128 / 24 / -64'),
///   ],
/// );
/// ```
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../widgets/liquid_glass.dart';

/// 一行「标签 / 取值」对照数据。
class SceneEvalRow {
  const SceneEvalRow({required this.label, required this.value});

  final String label;
  final String value;
}

/// 场景评估底部弹层。
///
/// 纯展示型：标题 + 多行标签值 + 关闭按钮，颜色与玻璃质感全部跟随主题 / 皮肤。
class SceneEvalSheet extends StatelessWidget {
  const SceneEvalSheet({
    super.key,
    required this.title,
    required this.rows,
    this.closeLabel = '关闭',
    this.onClose,
  });

  final String title;
  final List<SceneEvalRow> rows;
  final String closeLabel;

  /// 关闭回调（点击关闭按钮或点遮罩 dismiss 后触发，先于 pop）。
  final VoidCallback? onClose;

  /// 以模态底部弹层形式展示，遮罩色跟随主题 [AppThemeColors.scrim]。
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<SceneEvalRow> rows,
    String closeLabel = '关闭',
    bool isDismissible = true,
  }) {
    final AppThemeColors colors = context.appColors;
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: colors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      builder: (BuildContext ctx) => SceneEvalSheet(
        title: title,
        rows: rows,
        closeLabel: closeLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    return LiquidGlass(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 抓手小条（grabber）
          Center(
            child: Container(
              width: 60,
              height: 5,
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ...rows.map(
            (SceneEvalRow r) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      r.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    r.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          _CloseButton(
            colors: colors,
            label: closeLabel,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

/// 底部强调色「关闭」按钮（与 AppConfirmDialog 的 confirm 按钮同源配色）。
class _CloseButton extends StatelessWidget {
  const _CloseButton({
    required this.colors,
    required this.label,
    this.onTap,
  });

  final AppThemeColors colors;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.accent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          onTap?.call();
          Navigator.of(context).pop();
        },
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.onAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
