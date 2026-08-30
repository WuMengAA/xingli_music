/// ════════════════════════════════════════════════════════════════════════
/// 曲目操作按钮（cl15）：投稿（电台点歌）+ 收藏，供聚合搜索 / 曲库等复用。
///
/// - 收藏：全局收藏（[toggleFavoriteTrack]），即时反映已收藏状态。
/// - 投稿：向当前电台房提交点歌（[NetSessionNotifier.submitOrder]）；
///   未在电台房内则提示先进入电台房（可一键跳转 [StationLobbyPage]）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../pages/social/station_lobby_page.dart';
import '../../providers/net/session_provider.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../notification/app_notify.dart';

/// 曲目「投稿 / 收藏」按钮组（紧凑图标按钮，放在结果行尾部）。
class TrackActionButtons extends ConsumerWidget {
  const TrackActionButtons({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors colors = context.appColors;
    final String key = trackKeyOf(track.title, track.artist, track.sourceId);
    final bool isFav = ref.watch(isFavoriteProvider(key)).valueOrNull ?? false;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 投稿：向电台房点歌队列提交。
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.campaign_outlined,
              size: 20, color: colors.textSecondary),
          tooltip: '投稿到电台',
          onPressed: () => _submit(ref, context),
        ),
        // 收藏。
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: isFav ? colors.accent : colors.textSecondary,
          ),
          tooltip: isFav ? '取消收藏' : '收藏',
          onPressed: () async {
            final bool now =
                await toggleFavoriteTrack(ref, track);
            if (context.mounted) {
              appNotify(context, now ? '已收藏' : '已取消收藏',
                  title: '收藏');
            }
          },
        ),
      ],
    );
  }

  void _submit(WidgetRef ref, BuildContext context) {
    final NetSessionState s = ref.read(netSessionProvider);
    final bool inRoom = s.status == ConnStatus.connected &&
        s.role != NetRole.offline &&
        (s.relayUrl?.isNotEmpty ?? false);
    if (!inRoom) {
      // 未入房：提示并给跳转入口。
      showDialog<void>(
        context: context,
        builder: (BuildContext dctx) => AlertDialog(
          title: const Text('投稿点歌'),
          content: const Text('需要先进入电台房才能投稿点歌。\n要现在去电台大厅看看吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const StationLobbyPage()),
                );
              },
              child: const Text('去电台大厅'),
            ),
          ],
        ),
      );
      return;
    }
    ref
        .read(netSessionProvider.notifier)
        .submitOrder(track, message: '', anonymous: false);
    appNotify(context, '已投稿，等待 DJ 审批', title: '点歌');
  }
}
