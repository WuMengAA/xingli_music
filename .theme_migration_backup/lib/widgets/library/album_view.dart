import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/track.dart';
import '../../pages/library/album_detail_page.dart';
import '../../widgets/common/track_cover.dart';
import 'card_view.dart' show LibraryEmptyView;

/// 专辑视图（v2 M3 · P0-M3-4）：按专辑聚合网格。
///
/// 竖屏 2 列 / 横屏 4 列；点开 → [AlbumDetailPage]（复用 [InfoRow]）。
class AlbumView extends StatelessWidget {
  const AlbumView({super.key, required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Track>> grouped = <String, List<Track>>{};
    for (final Track t in tracks) {
      final String key = (t.album ?? '未知专辑').isEmpty
          ? '未知专辑'
          : t.album!;
      grouped.putIfAbsent(key, () => <Track>[]).add(t);
    }
    if (grouped.isEmpty) {
      return const LibraryEmptyView();
    }
    final List<MapEntry<String, List<Track>>> albums =
        grouped.entries.toList()
          ..sort((MapEntry<String, List<Track>> a,
                  MapEntry<String, List<Track>> b) =>
              a.key.compareTo(b.key));
    final double width = MediaQuery.sizeOf(context).width;
    final bool landscape = width >= AppSize.landscapeBreakpoint;

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: landscape ? 220 : 200,
        mainAxisSpacing: AppSpace.gridRowGap,
        crossAxisSpacing: AppSpace.xl,
        childAspectRatio: 0.85,
      ),
      itemCount: albums.length,
      itemBuilder: (BuildContext context, int i) {
        final MapEntry<String, List<Track>> e = albums[i];
        final Track first = e.value.first;
        return Material(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AlbumDetailPage(
                  albumName: e.key,
                  artist: first.artist,
                  tracks: e.value,
                ),
              ),
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.borderDefault),
              ),
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Center(
                      child: TrackCover(
                        track: first,
                        size: 96,
                        radius: AppRadius.md,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    e.key,
                    style: AppTextStyles.trackName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    first.artist,
                    style: AppTextStyles.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${e.value.length} ${Terms.track}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
