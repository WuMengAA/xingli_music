/// ════════════════════════════════════════════════════════════════════════
/// 全局通知 Toast（预设组件 · Task #522）
/// ════════════════════════════════════════════════════════════════════════
///
/// 还原 Ardot 设计 `ui-全局通知`（3:563 / 3:564）：
///   - 左侧渐变圆图标（跟随皮肤强调色）
///   - 标题（14 / SemiBold）+ 副标题（12 / 次级）
///   - 右侧「×」关闭按钮
///
/// 外观完全跟随主题 / 皮肤：玻璃用 [LiquidGlass]，渐变取自 `colors.accent` →
/// `colors.accentSoft`，所有颜色取自 `context.appColors`，不写死任何品牌色。
///
/// 用法（既可作为独立卡片，也可被 `GlobalNotificationToast` 复用为卡片视觉）：
/// ```dart
/// GlobalToast(
///   title: '世界存档已保存',
///   subtitle: '已同步至云端',
///   onClose: () => controller.hide(),
/// )
/// ```
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../widgets/liquid_glass.dart';

/// 全局通知 Toast 卡片（预设）。
class GlobalToast extends StatelessWidget {
  const GlobalToast({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.onClose,
    this.width = 320,
  });

  /// 左侧图标（默认渐变圆 + 铃铛）。
  final Widget? icon;

  /// 主标题。
  final String title;

  /// 副标题（可选）。
  final String? subtitle;

  /// 点击「×」回调（不传则不显示关闭按钮）。
  final VoidCallback? onClose;

  /// 卡片宽度（默认 320，与设计稿一致）。
  final double width;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    return LiquidGlass(
      radius: 16,
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: width,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            icon ?? _DefaultToastIcon(colors: colors),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (onClose != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GestureDetector(
                  onTap: onClose,
                  child: Icon(Icons.close, size: 18, color: colors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 默认左侧图标：强调色 → 强调色浅底渐变圆 + 铃铛。
class _DefaultToastIcon extends StatelessWidget {
  const _DefaultToastIcon({required this.colors});
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[colors.accent, colors.accentSoft],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.notifications_outlined,
        size: 18,
        color: colors.onAccent,
      ),
    );
  }
}
