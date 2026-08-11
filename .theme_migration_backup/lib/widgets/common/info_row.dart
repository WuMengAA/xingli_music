import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/utils/format.dart';
import '../../models/track.dart';
import 'track_cover.dart';

/// 通用信息行（v2 M1 · P0-M1-3 唯一实现）
///
/// 封面 48（[TrackCover]）+ 歌名 + 歌手 + 右对齐时长。
/// 曲库 / 搜索 / 播放页 / 通知中心 / 专辑详情共用，
/// **禁止**各页自行拼行（架构 §7.3）。
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.track,
    this.onTap,
    this.trailing,
  });

  /// 目标曲目；`null` 时渲染占位文本。
  final Track? track;

  /// 点击回调（点击即播等）。
  final VoidCallback? onTap;

  /// 行尾自定义内容（默认显示时长）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Track? t = track;
    final String title = t?.title ?? '未知歌曲';
    final String artist = t?.artist ?? '未知歌手';
    final Duration? duration = t?.duration;

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        children: <Widget>[
          TrackCover(track: t, size: AppSize.infoCover, radius: AppRadius.sm),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: AppTextStyles.trackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  artist,
                  style: AppTextStyles.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          trailing ??
              Text(
                formatDuration(duration),
                style: AppTextStyles.caption,
              ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brSm,
        child: row,
      ),
    );
  }
}
