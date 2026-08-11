import '../../../core/theme/app_theme_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/track.dart';
import '../../../providers/audio/audio_providers.dart';
import '../../../providers/audio/playback_notifier.dart';
import '../../../providers/shell/shell_providers.dart';
import '../../../widgets/common/info_row.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_chip.dart';
import '../../../widgets/common/state_views.dart';
import '../../../widgets/shell/app_search_bar.dart';

/// 实验 B · 跨源 / 模糊搜索增强（v2 M2 · P0-M2-3）。
///
/// 在 `effectiveMusicLibraryProvider` 全量曲库上做模糊匹配：
/// 标题 / 歌手 / 专辑包含（大小写不敏感），并把「长度短 + 命中多字段」
/// 的排前面。
class SearchExperimentPage extends ConsumerWidget {
  const SearchExperimentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String query =
        ref.watch(searchQueryProvider(_searchPageKey));
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);

    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '跨源搜索',
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 4),
              child: StateChip(tone: ChipTone.stable, label: '实验'),
            ),
          ],
          search: AppSearchBar(
            hintText: '输入关键词，跨源模糊搜索',
            query: query,
            onChanged: (String v) =>
                ref.read(searchQueryProvider(_searchPageKey).notifier).state = v,
          ),
          body: library.when(
            data: (List<Track> all) {
              final List<Track> hits = _fuzzy(all, query);
              if (query.trim().isEmpty) {
                return const EmptyView(
                  title: '输入关键词开始搜索',
                  message: '支持按歌曲 / 歌手 / 专辑模糊匹配',
                );
              }
              if (hits.isEmpty) {
                return const EmptyView(
                  title: '没有找到结果',
                  message: '换个关键词试试',
                );
              }
              return ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: hits.length,
                itemBuilder: (BuildContext context, int i) {
                  final Track t = hits[i];
                  return InfoRow(
                    track: t,
                    onTap: () async {
                      final String msg = await ref
                          .read(playbackActionsProvider)
                          .playTrack(t);
                      if (msg.isNotEmpty && context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(msg)));
                      }
                    },
                  );
                },
              );
            },
            loading: () => const LoadingView(),
            error: (Object e, StackTrace st) => ErrorView(
              message: '搜索失败：$e',
              onRetry: () => ref.invalidate(effectiveMusicLibraryProvider),
            ),
          ),
        ),
      ),
    );
  }

  static const int _searchPageKey = 100;

  List<Track> _fuzzy(List<Track> all, String q) {
    final String query = q.trim().toLowerCase();
    if (query.isEmpty) return const <Track>[];
    final List<(Track, int)> scored = <(Track, int)>[];
    for (final Track t in all) {
      int score = 0;
      if (t.title.toLowerCase().contains(query)) score += 2;
      if (t.artist.toLowerCase().contains(query)) score += 1;
      if ((t.album ?? '').toLowerCase().contains(query)) score += 1;
      if (score > 0) scored.add((t, score));
    }
    scored.sort(((Track, int) a, (Track, int) b) => b.$2.compareTo(a.$2));
    return scored.map(((Track, int) e) => e.$1).toList();
  }
}
