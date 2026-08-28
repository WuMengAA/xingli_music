import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../pages/sources/aggregate_search_page.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/library/library_view_providers.dart';
import '../../providers/shell/shell_providers.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../widgets/common/album_card.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/library/card_view.dart';
import '../../widgets/notification/app_notify.dart';
import '../../widgets/shell/app_search_bar.dart';

/// 曲库浏览分类筛选（null = 全部，#421）。
///
/// 画布「Screen · 曲库」筛选条：歌曲 / 专辑 / 在线 / 音景。
/// 数据模型仅有 [TrackSource]（本地 / 在线 / 音景）三类，故「歌曲」= 全部、
/// 「专辑」复用本地源（音景/在线直接对应），保证四个筛选都接入真实数据。
final libraryCategoryProvider = StateProvider<TrackSource?>((_) => null);

/// 曲库页（#421 重构 · 对齐画布 3:147）
///
/// 单屏滚动，自上而下：
/// 1. 顶部聚合搜索入口（本地 / 网易云 / B站 三源合一）
/// 2. 搜索栏（搜歌曲 / 歌手 / 专辑）
/// 3. 分类筛选条（歌曲 / 专辑 / 在线 / 音景）
/// 4. 「最近播放」+ 视图切换（卡片 / 列表）→ 曲库列表
/// 5. 时光沉底横幅（累计听歌时长）
/// 6. 「听歌排行」→ 播放排行
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String query = ref.watch(searchQueryProvider(ShellPage.library));
    final LibraryViewStyle style = ref.watch(libraryViewStyleProvider);
    final TrackSource? cat = ref.watch(libraryCategoryProvider);
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);
    final AsyncValue<List<TrackStats>> stats =
        ref.watch(playStatsProvider);

    final bool landscape =
        MediaQuery.of(context).size.width >= AppSize.landscapeBreakpoint;

    return PageScaffold(
      title: Terms.library,
      // 顶部聚合搜索入口（本地 / 网易云 / B站 三源合一）。
      actions: const <Widget>[_AggregateSearchButton()],
      search: AppSearchBar(
        hintText: Terms.librarySearchHint,
        query: query,
        onChanged: (String v) =>
            ref.read(searchQueryProvider(ShellPage.library).notifier).state =
                v,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 8),
                // 分类筛选条（歌曲 / 专辑 / 在线 / 音景）。
                const _FilterChips(),
                const SizedBox(height: 20),
                // 「最近播放」+ 视图切换（卡片 / 列表）。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: Text(Terms.recentlyPlayed,
                          style: context.appText.title),
                    ),
                    const _ViewToggle(),
                  ],
                ),
                const SizedBox(height: 12),
                // 曲库列表（卡片 / 列表随样式切换）。
                library.when(
                  loading: () =>
                      const LoadingView(label: Terms.loading),
                  error: (Object e, StackTrace st) => ErrorView(
                    message: Terms.loadFailed,
                    onRetry: () =>
                        ref.invalidate(effectiveMusicLibraryProvider),
                  ),
                  data: (List<Track> all) {
                    final List<Track> shown = _filter(all, query, cat);
                    if (shown.isEmpty) return const LibraryEmptyView();
                    if (style == LibraryViewStyle.card) {
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: landscape ? 220 : 200,
                          mainAxisSpacing: AppSpace.gridRowGap,
                          crossAxisSpacing: AppSpace.xl,
                          childAspectRatio: 0.92,
                        ),
                        itemCount: shown.length,
                        itemBuilder: (BuildContext c, int i) =>
                            AlbumCard(
                          track: shown[i],
                          onTap: () =>
                              _playTrack(ref, context, shown[i]),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (int i = 0; i < shown.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _TrackRowCard(
                              track: shown[i],
                              onTap: () =>
                                  _playTrack(ref, context, shown[i]),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                // 时光沉底横幅（累计听歌时长）。
                _TimeSinkBanner(totalMs: ref.watch(totalPlayMsProvider)),
                const SizedBox(height: 20),
                // 「听歌排行」。
                Text(Terms.topCharts, style: context.appText.title),
                const SizedBox(height: 12),
                stats.when(
                  loading: () =>
                      const LoadingView(label: Terms.topChartsLoading),
                  error: (Object e, StackTrace st) => ErrorView(
                    message: Terms.loadFailed,
                    onRetry: () => ref.invalidate(playStatsProvider),
                  ),
                  data: (List<TrackStats> list) {
                    if (list.isEmpty) {
                      return const EmptyView(
                        title: Terms.noPlayHistory,
                        message: Terms.noPlayHistoryMsg,
                      );
                    }
                    final List<TrackStats> top = list.take(10).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (int i = 0; i < top.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i < top.length - 1 ? 16 : 0,
                            ),
                            child: _RankRowCard(
                              rank: i + 1,
                              stats: top[i],
                              onTap: () =>
                                  _playStats(ref, context, top[i]),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Track> _filter(List<Track> all, String query, TrackSource? cat) {
    final String q = query.trim().toLowerCase();
    Iterable<Track> it = all;
    if (cat != null) it = it.where((Track t) => t.source == cat);
    if (q.isNotEmpty) {
      it = it.where((Track t) =>
          t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          (t.album ?? '').toLowerCase().contains(q));
    }
    return it.toList();
  }

  Future<void> _playTrack(
      WidgetRef ref, BuildContext context, Track t) async {
    final String msg = await ref.read(playbackActionsProvider).playTrack(t);
    if (msg.isNotEmpty && context.mounted) appNotify(context, msg);
  }

  /// 在曲库中按归一化键匹配真实 [Track] 后播放（听歌排行复用）。
  Future<void> _playStats(
      WidgetRef ref, BuildContext context, TrackStats s) async {
    final List<Track> all =
        await ref.read(effectiveMusicLibraryProvider.future);
    Track? matched;
    for (final Track t in all) {
      if (trackKeyOf(t.title, t.artist, t.sourceId) ==
          trackKeyOf(s.title, s.artist, s.sourceId)) {
        matched = t;
        break;
      }
    }
    if (matched == null || !context.mounted) {
      if (context.mounted) appNotify(context, Terms.trackNotFound);
      return;
    }
    final String msg =
        await ref.read(playbackActionsProvider).playTrack(matched);
    if (msg.isNotEmpty && context.mounted) appNotify(context, msg);
  }
}

/// 顶部聚合搜索按钮（画布 btn-聚合搜索 92×32 r16）。
class _AggregateSearchButton extends StatelessWidget {
  const _AggregateSearchButton();

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => showAggregateSearchSheet(context),
      icon: const Icon(Icons.travel_explore_rounded, size: 16),
      label: Text(Terms.aggregateSearch),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}

/// 分类筛选条（画布 chip / chip-active 64×34 r17）。
class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  static const List<_ChipDef> _chips = <_ChipDef>[
    _ChipDef(label: Terms.filterTracks, source: null),
    _ChipDef(label: Terms.filterAlbums, source: TrackSource.local),
    _ChipDef(label: Terms.filterOnline, source: TrackSource.stream),
    _ChipDef(label: Terms.filterSoundscape, source: TrackSource.soundscape),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrackSource? sel = ref.watch(libraryCategoryProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < _chips.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            _Chip(
              label: _chips[i].label,
              selected: sel == _chips[i].source,
              onTap: () => ref
                  .read(libraryCategoryProvider.notifier)
                  .state = _chips[i].source,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipDef {
  const _ChipDef({required this.label, required this.source});
  final String label;
  final TrackSource? source;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    // cl04：去 Material ChoiceChip → iOS 分段胶囊 / WinUI SegmentedControl 原生质感。
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? c.accent : c.border,
            ),
          ),
          child: Text(
            label,
            style: (selected ? context.appText.button : context.appText.caption)
                .copyWith(color: selected ? c.onAccent : c.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// 视图切换（画布 view-toggle 121×28 r14：卡片 / 列表）。
///
/// 直连 [libraryViewStyleProvider]，切换卡片 / 列表两种曲库呈现。
class _ViewToggle extends ConsumerWidget {
  const _ViewToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryViewStyle style = ref.watch(libraryViewStyleProvider);
    return SegmentedButton<LibraryViewStyle>(
      selected: <LibraryViewStyle>{style},
      onSelectionChanged: (Set<LibraryViewStyle> sel) =>
          ref.read(libraryViewStyleProvider.notifier).setStyle(sel.first),
      segments: const <ButtonSegment<LibraryViewStyle>>[
        ButtonSegment<LibraryViewStyle>(
          value: LibraryViewStyle.card,
          label: Text(Terms.viewCard),
        ),
        ButtonSegment<LibraryViewStyle>(
          value: LibraryViewStyle.list,
          label: Text(Terms.viewList),
        ),
      ],
    );
  }
}

/// 列表式歌曲行（画布 track-row 345×64 r16）。
class _TrackRowCard extends StatelessWidget {
  const _TrackRowCard({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    // cl04：iOS 分组卡 + Fluent Card 质感——浅色卡片底 + 1px 描边分层。
    return Container(
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: <Widget>[
                _RowCover(track: track),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.appText.trackName),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.appText.caption,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.play_circle_rounded,
                    size: 22, color: c.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 封面（48×48 r12，无图回退）。
class _RowCover extends StatelessWidget {
  const _RowCover({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final Widget fallback = ColoredBox(
      color: c.accentSoft,
      child: Icon(Icons.music_note_rounded, size: 22, color: c.accent),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: 48,
        height: 48,
        child: track.coverUrl != null && track.coverUrl!.isNotEmpty
            ? Image.network(
                track.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
                loadingBuilder: (BuildContext c2, Widget child,
                        ImageChunkEvent? p) =>
                    p == null ? child : fallback,
              )
            : fallback,
      ),
    );
  }
}

/// 听歌排行行（画布 rank-row 345×48 r16）。
class _RankRowCard extends StatelessWidget {
  const _RankRowCard({
    required this.rank,
    required this.stats,
    required this.onTap,
  });

  final int rank;
  final TrackStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final bool top = rank <= 3;
    // cl04：前三名奖牌金 / 银 / 铜（iOS 风格分层色）。
    final Color rankColor = switch (rank) {
      1 => const Color(0xFFD9A441),
      2 => const Color(0xFFB8BEC9),
      3 => const Color(0xFFC97B4E),
      _ => c.textTertiary,
    };
    return Container(
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 28,
                  child: Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: context.appText.title.copyWith(
                      color: rankColor,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(stats.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.appText.trackName),
                      const SizedBox(height: 2),
                      Text(
                        '${stats.artist} · 播 ${stats.playCount} 次 · ${stats.totalLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.appText.caption,
                      ),
                    ],
                  ),
                ),
                if (top)
                  Icon(Icons.emoji_events_rounded, size: 18, color: rankColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 时光沉底横幅（画布 time-sink-banner 345×72 r18）。
class _TimeSinkBanner extends StatelessWidget {
  const _TimeSinkBanner({required this.totalMs});
  final AsyncValue<int> totalMs;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              c.accent.withValues(alpha: 0.25),
              c.accent.withValues(alpha: 0.08),
            ],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(Terms.totalPlaytime,
                style: context.appText.caption
                    .copyWith(color: c.textSecondary)),
            const SizedBox(height: 6),
            totalMs.when(
              data: (int v) => Text(
                v < 3600000
                    ? '${(v / 60000).round()} 分钟'
                    : '${(v / 3600000).toStringAsFixed(1)} 小时',
                style: context.appText.title.copyWith(
                  color: c.accent,
                  fontSize: 24,
                ),
              ),
              loading: () => SizedBox(
                height: 24,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.accent,
                  ),
                ),
              ),
              error: (_, __) => Text('—',
                  style: context.appText.title.copyWith(color: c.accent)),
            ),
          ],
        ),
      ),
    );
  }
}
