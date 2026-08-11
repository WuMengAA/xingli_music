import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';

/// 状态徽标语气（v2 M1 · P0-M1-3 唯一实现）
///
/// M2 实验状态与 M4 音源健康共用。
enum ChipTone {
  /// 实验中（实验项 / 音源连接中语义复用）。
  experimenting,

  /// 稳定。
  stable,

  /// 已下线（附带置灰 + 禁入逻辑，由外层判断，不在 Chip 内）。
  retired,

  /// 连接中。
  connecting,

  /// 正常。
  ok,

  /// 失败。
  failed,
}

/// 状态徽标 `StateChip`（v2 M1 · P0-M1-3 唯一实现）
///
/// 用法：`StateChip(tone: ChipTone.experimenting, label: '实验中')`。
///
/// tone → 文案映射（架构 §7.4）：
/// - experimenting → 「实验中」/ stable → 「稳定」/ retired → 「已下线」
/// - connecting → 「连接中」/ ok → 「正常」/ failed → 「失败」
class StateChip extends StatelessWidget {
  const StateChip({
    super.key,
    required this.tone,
    required this.label,
  });

  /// 语气（决定配色）。
  final ChipTone tone;

  /// 展示文案（由调用方按业务语境给出，如「连接正常」「上次测试 12:03」）。
  final String label;

  /// tone → 文案缺省值（供便捷构造，可选覆盖）。
  static String defaultLabel(ChipTone tone) => switch (tone) {
        ChipTone.experimenting => '实验中',
        ChipTone.stable => '稳定',
        ChipTone.retired => '已下线',
        ChipTone.connecting => '连接中',
        ChipTone.ok => '正常',
        ChipTone.failed => '失败',
      };

  /// tone → 背景色。
  static Color _bg(ChipTone tone, AppThemeColors c) => switch (tone) {
        ChipTone.experimenting => c.accentSoft,
        ChipTone.stable => c.accentSoft,
        ChipTone.retired => c.bgSurfaceSunken,
        ChipTone.connecting => c.accentSoft,
        ChipTone.ok => c.accentSoft,
        ChipTone.failed => c.dangerSoft,
      };

  /// tone → 文字色。
  static Color _fg(ChipTone tone, AppThemeColors c) => switch (tone) {
        ChipTone.experimenting => c.accent,
        ChipTone.stable => c.success,
        ChipTone.retired => c.textTertiary,
        ChipTone.connecting => c.accent,
        ChipTone.ok => c.success,
        ChipTone.failed => c.danger,
      };

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _bg(tone, c),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: _fg(tone, c),
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
