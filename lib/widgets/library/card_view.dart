import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/track.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../widgets/common/album_card.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/notification/app_notify.dart';

/// 卡片视图（v2 M3 · P0-M3-2）：单曲卡片网格。
///
/// 竖屏 2 列 / 横屏 4 列（`SliverGridDelegateWithMaxCrossAxisExtent`），
/// 点击即播（走 [playbackActionsProvider]，C6）。
class CardView extends ConsumerWidget {
  const CardView({super.key, required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) {
      return const LibraryEmptyView();
    }
    final double width = MediaQuery.sizeOf(context).width;
    final bool landscape = width >= AppSize.landscapeBreakpoint;

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: landscape ? 220 : 200,
        mainAxisSpacing: AppSpace.gridRowGap,
        crossAxisSpacing: AppSpace.xl,
        childAspectRatio: 0.92,
      ),
      itemCount: tracks.length,
      itemBuilder: (BuildContext context, int i) {
        final Track t = tracks[i];
        return AlbumCard(
          track: t,
          onTap: () => _play(ref, context, t),
        );
      },
    );
  }

  Future<void> _play(WidgetRef ref, BuildContext context, Track t) async {
    final String msg = await ref.read(playbackActionsProvider).playTrack(t);
    if (msg.isNotEmpty && context.mounted) {
      appNotify(context, msg);
    }
  }
}

/// 曲库空态（三视图共用，P1-M3-6）。
class LibraryEmptyView extends StatelessWidget {
  const LibraryEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyView(
      title: '曲库为空',
      message: '请先在设置页「音源」中添加本地目录或服务器，\n或在探索实验室体验演示内容。',
      actionLabel: Terms.source,
    );
  }
}
