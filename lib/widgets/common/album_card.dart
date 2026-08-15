import '../../core/theme/app_theme_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/utils/format.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../liquid_glass.dart';
import 'track_cover.dart';

/// 曲库卡片视图卡（v2 M3 · P0-M3-2）。
///
/// 几何沿用 v1 AlbumCard 规范：封面 72 左上角 + 3 行文本
/// （歌名 / 歌手 / 时长），白底 r24 / 1px 描边 / `AppShadow.card`。
/// cl46：时长下追加全局收录信息（播放次数 / 累计收听时长）。
class AlbumCard extends ConsumerWidget {
  const AlbumCard({
    super.key,
    required this.track,
    required this.onTap,
  });

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String key = trackKeyOf(track.title, track.artist, track.sourceId);
    final TrackStats? stats =
        ref.watch(statsMapProvider).value?[key];
    return LiquidGlass(
      radius: AppRadius.lg,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.appColors.border),
              boxShadow: AppShadow.cardList,
            ),
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TrackCover(
                  track: track,
                  size: AppSize.cover,
                  radius: AppRadius.md,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  track.title,
                  style: context.appText.trackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  style: context.appText.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  formatDuration(track.duration),
                  style: context.appText.caption,
                ),
                // cl46：全局收录信息——播放次数 / 累计收听时长。
                if (stats != null && (stats.playCount > 0 || stats.totalMs > 0))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      stats.playCount > 0
                          ? '已听 ${stats.playCount} 次 · ${stats.totalLabel}'
                          : stats.totalLabel,
                      style: context.appText.caption
                          .copyWith(color: context.appColors.accent),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
