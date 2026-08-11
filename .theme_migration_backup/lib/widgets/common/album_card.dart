import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/utils/format.dart';
import '../../models/track.dart';
import '../liquid_glass.dart';
import 'track_cover.dart';

/// 曲库卡片视图卡（v2 M3 · P0-M3-2）。
///
/// 几何沿用 v1 AlbumCard 规范：封面 72 左上角 + 3 行文本
/// （歌名 / 歌手 / 时长），白底 r24 / 1px 描边 / `AppShadow.card`。
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.track,
    required this.onTap,
  });

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              border: Border.all(color: AppColors.borderDefault),
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
                  style: AppTextStyles.trackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  style: AppTextStyles.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  formatDuration(track.duration),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
