import '../../core/theme/app_theme_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/track.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../widgets/common/info_row.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/notification/app_notify.dart';

/// 专辑曲目列表页（v2 M3 · P0-M3-4）。
///
/// 复用 [InfoRow]（P0-M1-3），点击即播。
class AlbumDetailPage extends ConsumerWidget {
  const AlbumDetailPage({
    super.key,
    required this.albumName,
    required this.artist,
    required this.tracks,
  });

  final String albumName;
  final String artist;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: albumName,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
          body: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: tracks.length + 1,
            itemBuilder: (BuildContext context, int i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Text(
                    '$artist · ${tracks.length} ${Terms.track}',
                    style: context.appText.bodyMuted,
                  ),
                );
              }
              final Track t = tracks[i - 1];
              return InfoRow(
                track: t,
                onTap: () async {
                  final String msg =
                      await ref.read(playbackActionsProvider).playTrack(t);
                  if (msg.isNotEmpty && context.mounted) {
                    appNotify(context, msg);
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
