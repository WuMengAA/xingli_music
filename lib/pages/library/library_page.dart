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
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/library/card_view.dart';
import '../../widgets/notification/app_notify.dart';
import '../../widgets/shell/app_search_bar.dart';

/// 曲库浏览分类筛选（null = 全部，#421）。
final libraryCategoryProvider = StateProvider<TrackSource?>((_) => null);

/// 曲库页（#421 重构：顶部聚合搜索 + 第一页歌曲一览 + 第二页时光沉底）。
///
/// - **顶部聚合搜索**：右上角入口拉起 [showAggregateSearchSheet]
///   （本地 / 网易云 / B站 三源合一）。
/// - **第一页 歌曲一览**：样式切换（卡片式 / 列表式）+ 分类筛选器
///   （全部 / 本地 / 在线 / 音景），数据源 [effectiveMusicLibraryProvider]。
/// - **第二页 时光沉底**：听歌情况（累计时长 + 播放排行）+ 历史记录
///   （复用 cl46 统计）。
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String query = ref.watch(searchQueryProvider(ShellPage.library));
    final LibraryViewStyle style = ref.watch(libraryViewStyleProvider);
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);

    return DefaultTabController(
      length: 2,
      child: PageScaffold(
        title: Terms.library,
        // 顶部聚合搜索入口（本地 / 网易云 / B站 三源合一）。
        actions: <Widget>[
          ActionChip(
            avatar: Icon(Icons.travel_explore_rounded,
                size: 16, color: context.appColors.accent),
            label: Text('聚合搜索', style: context.appText.caption),
            visualDensity: VisualDensity.compact,
            onPressed: () => showAggregateSearchSheet(context),
          ),
        ],
        search: AppSearchBar(
          hintText: '搜索歌曲、歌手、专辑',
          query: query,
          onChanged: (String v) =>
              ref.read(searchQueryProvider(ShellPage.library).notifier).state = v,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 固定头部（Tab）可滚动——800×500 横屏下正文被压缩时整体可上滚，
            // 避免 RenderFlex overflow（此前该尺寸必崩）。
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                child: TabBar(
                  labelColor: context.appColors.accent,
                  unselectedLabelColor: context.appColors.textSecondary,
                  indicatorColor: context.appColors.accent,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: const <Tab>[
                    Tab(text: '歌曲'),
                    Tab(text: '时光沉底'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: library.when(
                data: (List<Track> all) {
                  final List<Track> filtered = _filter(all, query);
                  return TabBarView(
                    children: <Widget>[
                      _SongPage(style: style, tracks: filtered),
                      const _TimeSinkPage(),
                    ],
                  );
                },
                loading: () => const SingleChildScrollView(
                  child: LoadingView(label: '曲库加载中…'),
                ),
                error: (Object e, StackTrace st) => SingleChildScrollView(
                  child: ErrorView(
                    message: '曲库加载失败：$e',
                    onRetry: () => ref.invalidate(effectiveMusicLibraryProvider),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Track> _filter(List<Track> all, String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((Track t) {
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          (t.album ?? '').toLowerCase().contains(q);
    }).toList();
  }
}

/// 第一页：歌曲一览（样式切换 + 分类筛选 + 列表）。
class _SongPage extends ConsumerWidget {
  const _SongPage({required this.style, required this.tracks});

  final LibraryViewStyle style;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrackSource? cat = ref.watch(libraryCategoryProvider);
    final List<Track> shown = cat == null
        ? tracks
        : tracks.where((Track t) => t.source == cat).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 控制条：样式切换（卡片 / 列表）+ 分类筛选器。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
          child: Row(
            children: <Widget>[
              SegmentedButton<LibraryViewStyle>(
                segments: const <ButtonSegment<LibraryViewStyle>>[
                  ButtonSegment<LibraryViewStyle>(
                    value: LibraryViewStyle.card,
                    icon: Icon(Icons.grid_view_rounded),
                    label: Text('卡片'),
                  ),
                  ButtonSegment<LibraryViewStyle>(
                    value: LibraryViewStyle.list,
                    icon: Icon(Icons.list_rounded),
                    label: Text('列表'),
                  ),
                ],
                selected: <LibraryViewStyle>{style},
                onSelectionChanged: (Set<LibraryViewStyle> s) {
                  ref
                      .read(libraryViewStyleProvider.notifier)
                      .setStyle(s.first);
                },
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final _Cat c in _Cat.values) ...<Widget>[
                        ChoiceChip(
                          label: Text(c.label, style: context.appText.caption),
                          selected: cat == c.source,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => ref
                              .read(libraryCategoryProvider.notifier)
                              .state = c.source,
                        ),
                        if (c != _Cat.values.last) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const LibraryEmptyView()
              : style == LibraryViewStyle.card
                  ? CardView(tracks: shown)
                  : _TrackListRows(tracks: shown),
        ),
      ],
    );
  }
}

/// 分类筛选选项（全部 / 本地 / 在线 / 音景，#421）。
class _Cat {
  const _Cat(this.source, this.label);
  final TrackSource? source; // null = 全部
  final String label;
  static const List<_Cat> values = <_Cat>[
    _Cat(null, '全部'),
    _Cat(TrackSource.local, '本地'),
    _Cat(TrackSource.stream, '在线'),
    _Cat(TrackSource.soundscape, '音景'),
  ];
}

/// 列表式歌曲行（替代旧 folder / album 视图，#421）。
class _TrackListRows extends ConsumerWidget {
  const _TrackListRows({required this.tracks});
  final List<Track> tracks;

  Future<void> _play(WidgetRef ref, BuildContext context, Track t) async {
    final String msg = await ref.read(playbackActionsProvider).playTrack(t);
    if (msg.isNotEmpty && context.mounted) appNotify(context, msg);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView.separated(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md, vertical: AppSpace.xs),
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (BuildContext _, int i) {
          final Track t = tracks[i];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                width: 44,
                height: 44,
                child: t.coverUrl != null && t.coverUrl!.isNotEmpty
                    ? Image.network(
                        t.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _RowCoverFallback(),
                        loadingBuilder: (BuildContext c, Widget child,
                                ImageChunkEvent? p) =>
                            p == null ? child : const _RowCoverFallback(),
                      )
                    : const _RowCoverFallback(),
              ),
            ),
            title: Text(t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appText.trackName),
            subtitle: Text(t.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appText.caption),
            trailing: Icon(Icons.play_circle_outline_rounded,
                color: context.appColors.accent),
            onTap: () => _play(ref, context, t),
          );
        },
      );
}

class _RowCoverFallback extends StatelessWidget {
  const _RowCoverFallback();
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: context.appColors.accentSoft,
        child: Icon(Icons.music_note_rounded,
            size: 22, color: context.appColors.accent),
      );
}

/// 第二页：时光沉底（听歌情况 + 历史记录），复用 cl46 统计（#421）。
class _TimeSinkPage extends ConsumerWidget {
  const _TimeSinkPage();

  /// 在历史 / 排行中按归一化键匹配曲库中的真实 [Track]。
  Future<Track?> _match(WidgetRef ref, String title, String artist,
      String sourceId) async {
    final List<Track> all =
        await ref.read(effectiveMusicLibraryProvider.future);
    final String key = trackKeyOf(title, artist, sourceId);
    for (final Track t in all) {
      if (trackKeyOf(t.title, t.artist, t.sourceId) == key) return t;
    }
    return null;
  }

  Future<void> _play(WidgetRef ref, BuildContext context, Track? t) async {
    if (t == null || !context.mounted) {
      // cl53-F5：报错通知走全局通知（与全局通知一致，多并行竖向排布），
      // 不再用 SnackBar（样式割裂、单条易被吞）。
      if (context.mounted) appNotify(context, '曲库中找不到该曲目');
      return;
    }
    final String msg = await ref.read(playbackActionsProvider).playTrack(t);
    if (msg.isNotEmpty && context.mounted) appNotify(context, msg);
  }

  String _timeAgo(DateTime t) {
    final Duration d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return '${(d.inDays / 30).floor()} 个月前';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> totalMs = ref.watch(totalPlayMsProvider);
    final AsyncValue<List<TrackStats>> stats = ref.watch(playStatsProvider);
    final AsyncValue<List<ListenEntry>> history =
        ref.watch(recentHistoryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── 听歌情况：累计时长横幅 ──
          Container(
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
                totalMs.when(
                  data: (int v) => Text(
                    v < 3600000
                        ? '${(v / 60000).round()} 分钟'
                        : '${(v / 3600000).toStringAsFixed(1)} 小时',
                    style: context.appText.title.copyWith(
                      color: context.appColors.accent,
                      fontSize: 26,
                    ),
                  ),
                  loading: () => const SizedBox(
                    height: 26,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const Text('—'),
                ),
                const SizedBox(height: 2),
                Text('在「歌曲」页播放的每一首都会计入',
                    style: context.appText.caption),
              ],
            ),
          ),

          // ── 听歌排行（Top 10）──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Text('听歌排行',
                style: context.appText.title
                    .copyWith(color: context.appColors.textPrimary)),
          ),
          const SizedBox(height: AppSpace.sm),
          stats.when(
            loading: () => const LoadingView(label: '排行加载中…'),
            error: (Object e, StackTrace st) => Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: ErrorView(
                message: '排行加载失败：$e',
                onRetry: () => ref.invalidate(playStatsProvider),
              ),
            ),
            data: (List<TrackStats> list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpace.md),
                  child: EmptyView(
                    title: '还没有播放记录',
                    message: '播放几首歌后，这里会按播放次数排行',
                  ),
                );
              }
              final List<TrackStats> top = list.take(10).toList();
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                itemCount: top.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (BuildContext c, int i) {
                  final TrackStats s = top[i];
                  final int rank = i + 1;
                  return ListTile(
                    dense: true,
                    leading: SizedBox(
                      width: 32,
                      child: Text('$rank',
                          textAlign: TextAlign.center,
                          style: context.appText.title.copyWith(
                            color: rank <= 3
                                ? context.appColors.accent
                                : context.appColors.textTertiary,
                            fontSize: 18,
                          )),
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
                      final Track? t =
                          await _match(ref, s.title, s.artist, s.sourceId);
                      if (!c.mounted) return;
                      await _play(ref, c, t);
                    },
                  );
                },
              );
            },
          ),

          // ── 历史记录（最近播放）──
          const SizedBox(height: AppSpace.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Text('最近播放',
                style: context.appText.title
                    .copyWith(color: context.appColors.textPrimary)),
          ),
          const SizedBox(height: AppSpace.sm),
          history.when(
            loading: () => const LoadingView(label: '历史加载中…'),
            error: (Object e, StackTrace st) => Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: ErrorView(
                message: '历史加载失败：$e',
                onRetry: () => ref.invalidate(recentHistoryProvider),
              ),
            ),
            data: (List<ListenEntry> list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpace.md),
                  child: EmptyView(
                    title: '还没有历史记录',
                    message: '开始听歌后，这里会显示最近播放',
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (BuildContext c, int i) {
                  final ListenEntry e = list[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.history_rounded,
                        size: 18, color: context.appColors.iconInactive),
                    title: Text(e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.appText.trackName),
                    subtitle: Text(
                      '${e.artist} · ${_timeAgo(e.playedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.appText.caption,
                    ),
                    onTap: () async {
                      final Track? t =
                          await _match(ref, e.title, e.artist, e.sourceId);
                      if (!c.mounted) return;
                      await _play(ref, c, t);
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: AppSpace.lg),
        ],
      ),
    );
  }
}
