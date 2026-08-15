/// 听歌排行（cl46）：全局播放次数 / 收听时长 Top 榜。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/notification/app_notify.dart';

class TopListPage extends ConsumerWidget {
  const TopListPage({super.key});

  Future<Track?> _match(
      WidgetRef ref, String title, String artist, String sourceId) async {
    final List<Track> all =
        await ref.read(effectiveMusicLibraryProvider.future);
    final String key = trackKeyOf(title, artist, sourceId);
    for (final Track t in all) {
      if (trackKeyOf(t.title, t.artist, t.sourceId) == key) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TrackStats>> stats = ref.watch(playStatsProvider);
    final AsyncValue<int> totalMs = ref.watch(totalPlayMsProvider);
    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      appBar: AppBar(
        backgroundColor: context.appColors.bgPage,
        title: Text('听歌排行',
            style: context.appText.title
                .copyWith(color: context.appColors.textPrimary)),
      ),
      body: stats.when(
        loading: () => const LoadingView(label: '排行加载中…'),
        error: (Object e, StackTrace st) => ErrorView(
          message: '排行加载失败：$e',
          onRetry: () => ref.invalidate(playStatsProvider),
        ),
        data: (List<TrackStats> list) {
          final int total = totalMs.value ?? 0;
          final String totalLabel = total < 3600000
              ? '${(total / 60000).round()} 分钟'
              : '${(total / 3600000).toStringAsFixed(1)} 小时';
          return Column(
            children: <Widget>[
              // 总时长横幅。
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(AppSpace.md),
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      context.appColors.accent.withValues(alpha: 0.25),
                      context.appColors.accent.withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('累计听歌时长',
                        style: context.appText.caption
                            .copyWith(color: context.appColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(totalLabel,
                        style: context.appText.title.copyWith(
                          color: context.appColors.accent,
                          fontSize: 26,
                        )),
                    const SizedBox(height: 2),
                    Text('共播放 ${list.length} 首不同歌曲',
                        style: context.appText.caption),
                  ],
                ),
              ),
              if (list.isEmpty)
                const Expanded(
                  child: EmptyView(
                    title: '还没有播放记录',
                    message: '播放几首歌后，这里会按播放次数排行',
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(
                        left: AppSpace.md, right: AppSpace.md, bottom: 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (BuildContext c, int i) {
                      final TrackStats s = list[i];
                      final int rank = i + 1;
                      return ListTile(
                        dense: true,
                        leading: SizedBox(
                          width: 32,
                          child: Text(
                            '$rank',
                            textAlign: TextAlign.center,
                            style: context.appText.title.copyWith(
                              color: rank <= 3
                                  ? context.appColors.accent
                                  : context.appColors.textTertiary,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        title: Text(s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.appText.trackName),
                        subtitle: Text(
                          '${s.artist} · 播 ${s.playCount} 次 · ${s.totalLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.appText.caption,
                        ),
                        trailing: rank <= 3
                            ? Icon(Icons.emoji_events_rounded,
                                size: 18, color: context.appColors.accent)
                            : null,
                        onTap: () async {
                          final Track? t = await _match(
                              ref, s.title, s.artist, s.sourceId);
                          // cl53-F5：报错通知走全局通知（与全局通知一致）。
                          if (t == null || !c.mounted) {
                            if (c.mounted) appNotify(c, '曲库中找不到该曲目');
                            return;
                          }
                          await ref.read(audioServiceProvider).playMusic(t);
                        },
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
