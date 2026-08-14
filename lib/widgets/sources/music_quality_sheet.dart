/// 音乐源音质选择弹层（R26skel-b6）。
///
/// - 网易云（音乐源）：标准 / 高 / 无损 —— 无损需网易云 VIP（自动识别）；
/// - 哔哩哔哩（视频源）：自动 / 流畅 / 高清 / 超清 / 4K —— 超清与 4K 需
///   B站大会员（自动识别）。
///
/// 在音乐卡片 / 音乐面板 / 设置均可打开。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/audio/music_quality_provider.dart';

/// 打开音质选择弹层。
Future<void> showMusicQualitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.appColors.bgSurface,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _MusicQualitySheet(),
  );
}

class _MusicQualitySheet extends ConsumerWidget {
  const _MusicQualitySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MusicQuality mq = ref.watch(musicQualityProvider);
    final BiliVideoQuality bq = ref.watch(biliVideoQualityProvider);
    final bool neVip = ref.watch(neteaseVipProvider);
    final bool biVip = ref.watch(bilibiliVipProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.high_quality_rounded,
                    size: AppSize.icon, color: context.appColors.accent),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text('音质与清晰度', style: context.appText.subtitle),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: AppSize.iconSm,
                      color: context.appColors.iconInactive),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text('网易云（音乐源）${neVip ? '· VIP' : ''}',
                style: context.appText.body),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: <Widget>[
                for (final MusicQuality q in MusicQuality.values)
                  ChoiceChip(
                    label: Text(
                      q.label + (q == MusicQuality.lossless ? '${neVip ? "" : " · 需VIP"}' : ''),
                      style: context.appText.caption,
                    ),
                    selected: mq == q,
                    onSelected: q == MusicQuality.lossless && !neVip
                        ? null
                        : (_) => ref.read(musicQualityProvider.notifier).state = q,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Text('哔哩哔哩（视频源）${biVip ? '· 大会员' : ''}',
                style: context.appText.body),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: <Widget>[
                for (final BiliVideoQuality q in BiliVideoQuality.values)
                  ChoiceChip(
                    label: Text(
                      q.label +
                          ((q == BiliVideoQuality.ultra ||
                                  q == BiliVideoQuality.uhd4k) &&
                                  !biVip
                              ? ' · 需大会员'
                              : ''),
                      style: context.appText.caption,
                    ),
                    selected: bq == q,
                    onSelected:
                        (q == BiliVideoQuality.ultra ||
                                q == BiliVideoQuality.uhd4k) &&
                                !biVip
                            ? null
                            : (_) =>
                                ref.read(biliVideoQualityProvider.notifier).state = q,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text('未登录/无会员时高级档不可选；登录后自动识别会员权益。',
                style: context.appText.artist),
          ],
        ),
      ),
    );
  }
}
