/// ════════════════════════════════════════════════════════════════════════
/// 提醒横幅（预设组件 · Task #523）
/// ════════════════════════════════════════════════════════════════════════
///
/// 还原 Ardot 设计 `ui-提醒横幅`（3:569 / 3:570）：
///   - 左侧 5px 强调色竖条
///   - 渐变圆图标（跟随皮肤强调色）
///   - 标题（15 / SemiBold）+ 说明正文（12 / 次级）
///   - 强调色行动按钮
///
/// 外观完全跟随主题 / 皮肤：玻璃用 [LiquidGlass]，强调色与图标渐变取自
/// `context.appColors`，不写死任何品牌色。[accentColor] 可覆盖竖条 / 按钮色
/// （如警告场景传 [AppThemeColors.warning]）。
///
/// 用法：
/// ```dart
/// ReminderBanner(
///   title: '每日音乐推荐',
///   body: '为你精选 10 首舒缓曲目，适合夜晚聆听。',
///   actionLabel: '查看',
///   onAction: () => openDailyMix(),
/// )
/// ```
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../widgets/liquid_glass.dart';

/// 提醒横幅（预设）。
class ReminderBanner extends StatelessWidget {
  const ReminderBanner({
    super.key,
    this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    this.onAction,
    this.accentColor,
  });

  /// 左侧图标（默认渐变圆 + 喇叭）。
  final Widget? icon;

  /// 主标题。
  final String title;

  /// 说明正文。
  final String body;

  /// 行动按钮文案。
  final String actionLabel;

  /// 点击行动按钮回调。
  final VoidCallback? onAction;

  /// 强调色（默认 [AppThemeColors.accent]，可传 warning / success 等）。
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    final Color accent = accentColor ?? colors.accent;
    return LiquidGlass(
      radius: 16,
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(width: 5, color: accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  icon ?? _BannerIcon(colors: colors),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _BannerButton(
                          colors: colors,
                          accent: accent,
                          label: actionLabel,
                          onTap: onAction,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 默认左侧图标：强调色 → 强调色浅底渐变圆 + 喇叭。
class _BannerIcon extends StatelessWidget {
  const _BannerIcon({required this.colors});
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[colors.accent, colors.accentSoft],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(
        Icons.campaign_outlined,
        size: 22,
        color: colors.onAccent,
      ),
    );
  }
}

/// 强调色行动按钮。
class _BannerButton extends StatelessWidget {
  const _BannerButton({
    required this.colors,
    required this.accent,
    required this.label,
    this.onTap,
  });

  final AppThemeColors colors;
  final Color accent;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.onAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
