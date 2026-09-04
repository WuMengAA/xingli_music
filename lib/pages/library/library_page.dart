import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../pages/sources/aggregate_search_page.dart';
import '../../pages/tools/calendar_page.dart';
import '../../pages/tools/classisland_page.dart';
import '../../pages/tools/tools_panel_page.dart';
import '../../pages/tools/weather_page.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/library/library_view_providers.dart';
import '../../providers/shell/shell_providers.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../widgets/common/album_card.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/track_action_buttons.dart';
import '../../widgets/library/card_view.dart';
import '../../widgets/notification/app_notify.dart';
import '../../widgets/shell/app_search_bar.dart';
import 'playlist_detail_page.dart';

/// 曲库四栏（cl15：歌曲 / 歌单 / 专辑 / 歌手）。
///
/// 数据模型仅有 [TrackSource]（本地 / 在线 / 音景），故「歌曲」= 全部曲目、
/// 「专辑」按 album 字段分组、「歌手」按 artist 字段分组、「歌单」读全局
/// 歌单（playlistsProvider）——四个 Tab 全部接入真实数据。
enum LibraryTab { tracks, playlists, albums, artists }

final libraryCategoryProvider = StateProvider<LibraryTab>((_) => LibraryTab.tracks);

/// 曲库页（cl15 四栏重构 · 对齐画布 3:147）
///
/// 单屏滚动，自上而下：
/// 1. 顶部聚合搜索入口（本地 / 网易云 / B站 三源合一）
/// 2. 搜索栏（搜歌曲 / 歌手 / 专辑）
/// 3. 四栏切换（歌曲 / 歌单 / 专辑 / 歌手）
/// 4. 当前栏内容：歌曲（最近播放 + 视图切换 + 列表/卡片 + 排行）、
///    歌单（全局歌单列表 + 新建）、专辑（按专辑分组 + 展开播放）、
///    歌手（按歌手分组 + 展开播放）
/// 5. 时光沉底横幅（累计听歌时长，歌曲栏底部）
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String query = ref.watch(searchQueryProvider(ShellPage.library));
    final LibraryTab tab = ref.watch(libraryCategoryProvider);

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
                // 四栏切换（歌曲 / 歌单 / 专辑 / 歌手）。
                const _CategoryTabs(),
                const SizedBox(height: 12),
                // 工具快捷入口（天气/日历/ClassIsland/工具面板）——
                // 曲库与新增功能联动：不切页即可直达各工具。
                const _ToolsQuickRow(),
                const SizedBox(height: 12),
                // 当前栏内容。
                switch (tab) {
                  LibraryTab.tracks => _TracksTab(query: query),
                  LibraryTab.playlists => _PlaylistsTab(query: query),
                  LibraryTab.albums => _AlbumsTab(query: query),
                  LibraryTab.artists => _ArtistsTab(query: query),
                },
                const SizedBox(height: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 曲库工具快捷入口：天气/日历/ClassIsland/工具面板 ——
/// 曲库与新增功能联动，不切 Tab 直达各工具。
class _ToolsQuickRow extends StatelessWidget {
  const _ToolsQuickRow();

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _toolChip(context, c, Icons.wb_sunny_outlined, '天气',
              () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const WeatherPage()),
                  )),
          const SizedBox(width: 8),
          _toolChip(context, c, Icons.calendar_month_outlined, '日历',
              () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const CalendarPage()),
                  )),
          const SizedBox(width: 8),
          _toolChip(context, c, Icons.school_outlined, 'ClassIsland',
              () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ClassIslandPage()),
                  )),
          const SizedBox(width: 8),
          _toolChip(context, c, Icons.grid_view_outlined, '全部工具',
              () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ToolsPanelPage()),
                  )),
        ],
      ),
    );
  }

  Widget _toolChip(BuildContext context, AppThemeColors c, IconData icon,
      String label, VoidCallback onTap) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: c.bgSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: c.accent),
              const SizedBox(width: 6),
              Text(label,
                  style: context.appText.caption
                      .copyWith(color: c.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 四栏切换条。
class _CategoryTabs extends ConsumerWidget {
  const _CategoryTabs();

  static const List<(String, LibraryTab)> _tabs = <(String, LibraryTab)>[
    (Terms.filterTracks, LibraryTab.tracks),
    (Terms.filterPlaylists, LibraryTab.playlists),
    (Terms.filterAlbums, LibraryTab.albums),
    (Terms.filterSingers, LibraryTab.artists),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryTab sel = ref.watch(libraryCategoryProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < _tabs.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            _Chip(
              label: _tabs[i].$1,
              selected: sel == _tabs[i].$2,
              onTap: () => ref
                  .read(libraryCategoryProvider.notifier)
                  .state = _tabs[i].$2,
            ),
          ],
        ],
      ),
    );
  }
}

/// 歌曲栏：曲库列表（卡片/列表切换 + 投稿/收藏按钮）+ 听歌排行 + 时光横幅。
class _TracksTab extends ConsumerWidget {
  const _TracksTab({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryViewStyle style = ref.watch(libraryViewStyleProvider);
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);
    final AsyncValue<List<TrackStats>> stats = ref.watch(playStatsProvider);
    final bool landscape =
        MediaQuery.of(context).size.width >= AppSize.landscapeBreakpoint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 「最近在听」+ 视图切换（卡片 / 列表）。
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Text(Terms.recentlyPlayed, style: context.appText.title),
            ),
            const _ViewToggle(),
          ],
        ),
        const SizedBox(height: 12),
        // 曲库列表（卡片 / 列表随样式切换）。
        library.when(
          loading: () => const LoadingView(label: Terms.loading),
          error: (Object e, StackTrace st) => ErrorView(
            message: Terms.loadFailed,
            onRetry: () => ref.invalidate(effectiveMusicLibraryProvider),
          ),
          data: (List<Track> all) {
            final List<Track> shown = _filter(all, query);
            if (shown.isEmpty) return const LibraryEmptyView();
            if (style == LibraryViewStyle.card) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: landscape ? 220 : 200,
                  mainAxisSpacing: AppSpace.gridRowGap,
                  crossAxisSpacing: AppSpace.xl,
                  childAspectRatio: 0.92,
                ),
                itemCount: shown.length,
                itemBuilder: (BuildContext c, int i) => AlbumCard(
                  track: shown[i],
                  onTap: () => _playTrack(ref, context, shown[i]),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < shown.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _TrackRowCard(
                      track: shown[i],
                      onTap: () => _playTrack(ref, context, shown[i]),
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
        // 「你的排行」。
        Text(Terms.topCharts, style: context.appText.title),
        const SizedBox(height: 12),
        stats.when(
          loading: () => const LoadingView(label: Terms.topChartsLoading),
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
                      bottom: i < top.length - 1 ? 10 : 0,
                    ),
                    child: _RankRowCard(
                      rank: i + 1,
                      stats: top[i],
                      onTap: () => _playStats(ref, context, top[i]),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 歌单栏：全局歌单列表（playlistsProvider）+ 新建。
class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Playlist>> pls = ref.watch(playlistsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(Terms.filterPlaylists, style: context.appText.title),
            ),
            // 新建歌单。
            TextButton.icon(
              onPressed: () => _createPlaylist(ref, context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(Terms.createPlaylist),
            ),
          ],
        ),
        const SizedBox(height: 12),
        pls.when(
          loading: () => const LoadingView(label: Terms.loading),
          error: (Object e, StackTrace st) => ErrorView(
            message: Terms.loadFailed,
            onRetry: () => ref.invalidate(playlistsProvider),
          ),
          data: (List<Playlist> list) {
            final String q = query.trim().toLowerCase();
            final List<Playlist> shown = q.isEmpty
                ? list
                : list
                    .where((Playlist p) =>
                        p.name.toLowerCase().contains(q))
                    .toList();
            if (shown.isEmpty) {
              return EmptyView(
                title: Terms.noPlaylist,
                message: Terms.playlistEmpty,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < shown.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PlaylistCard(
                      playlist: shown[i],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlaylistDetailPage(
                              playlistId: shown[i].id ?? -1),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _createPlaylist(WidgetRef ref, BuildContext context) async {
    final TextEditingController ctrl = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: const Text(Terms.createPlaylist),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '歌单名称'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dctx).pop(ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(trackStatsDbProvider).createPlaylist(name);
    ref.invalidate(playlistsProvider);
    if (context.mounted) {
      appNotify(context, '已创建歌单「$name」', title: '歌单');
    }
  }
}

/// 专辑栏：按 album 分组曲目（内嵌展开播放）。
class _AlbumsTab extends ConsumerStatefulWidget {
  const _AlbumsTab({required this.query});

  final String query;

  @override
  ConsumerState<_AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends ConsumerState<_AlbumsTab> {
  String? _expanded; // 展开的专辑名（null=全收起）

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);
    return library.when(
      loading: () => const LoadingView(label: Terms.loading),
      error: (Object e, StackTrace st) => ErrorView(
        message: Terms.loadFailed,
        onRetry: () => ref.invalidate(effectiveMusicLibraryProvider),
      ),
      data: (List<Track> all) {
        final String q = widget.query.trim().toLowerCase();
        // 按专辑名分组（album 非空），组内去重、排序稳定。
        final Map<String, List<Track>> groups = <String, List<Track>>{};
        for (final Track t in all) {
          final String album = (t.album ?? '').trim();
          if (album.isEmpty) continue;
          if (q.isNotEmpty &&
              !album.toLowerCase().contains(q) &&
              !t.artist.toLowerCase().contains(q)) {
            continue;
          }
          groups.putIfAbsent(album, () => <Track>[]).add(t);
        }
        if (groups.isEmpty) {
          return const EmptyView(
            title: '还没有专辑',
            message: '播放带专辑信息的歌曲后会自动归类',
          );
        }
        final List<String> names = groups.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('${Terms.filterAlbums}（${names.length}）',
                style: context.appText.title),
            const SizedBox(height: 12),
            for (int i = 0; i < names.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GroupCard(
                  title: names[i],
                  subtitle: '${groups[names[i]]!.length} 首',
                  coverUrl: _firstCover(groups[names[i]]!),
                  expanded: _expanded == names[i],
                  onTap: () => setState(() {
                    _expanded = _expanded == names[i] ? null : names[i];
                  }),
                  children: [
                    for (final Track t in groups[names[i]]!)
                      _TrackRowCard(
                        track: t,
                        onTap: () => _playTrack(ref, context, t),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String? _firstCover(List<Track> tracks) {
    for (final Track t in tracks) {
      if (t.coverUrl != null && t.coverUrl!.isNotEmpty) return t.coverUrl;
    }
    return null;
  }
}

/// 歌手栏：按 artist 分组曲目（内嵌展开播放）。
class _ArtistsTab extends ConsumerStatefulWidget {
  const _ArtistsTab({required this.query});

  final String query;

  @override
  ConsumerState<_ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends ConsumerState<_ArtistsTab> {
  String? _expanded; // 展开的歌手名（null=全收起）

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);
    return library.when(
      loading: () => const LoadingView(label: Terms.loading),
      error: (Object e, StackTrace st) => ErrorView(
        message: Terms.loadFailed,
        onRetry: () => ref.invalidate(effectiveMusicLibraryProvider),
      ),
      data: (List<Track> all) {
        final String q = widget.query.trim().toLowerCase();
        final Map<String, List<Track>> groups = <String, List<Track>>{};
        for (final Track t in all) {
          final String artist = t.artist.trim();
          if (artist.isEmpty) continue;
          if (q.isNotEmpty &&
              !artist.toLowerCase().contains(q) &&
              !t.title.toLowerCase().contains(q)) {
            continue;
          }
          groups.putIfAbsent(artist, () => <Track>[]).add(t);
        }
        if (groups.isEmpty) {
          return const EmptyView(
            title: '还没有歌手',
            message: '播放带歌手信息的歌曲后会自动归类',
          );
        }
        final List<String> names = groups.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('${Terms.filterSingers}（${names.length}）',
                style: context.appText.title),
            const SizedBox(height: 12),
            for (int i = 0; i < names.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GroupCard(
                  title: names[i],
                  subtitle: '${groups[names[i]]!.length} 首',
                  coverUrl: _firstCover(groups[names[i]]!),
                  expanded: _expanded == names[i],
                  onTap: () => setState(() {
                    _expanded = _expanded == names[i] ? null : names[i];
                  }),
                  children: [
                    for (final Track t in groups[names[i]]!)
                      _TrackRowCard(
                        track: t,
                        onTap: () => _playTrack(ref, context, t),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String? _firstCover(List<Track> tracks) {
    for (final Track t in tracks) {
      if (t.coverUrl != null && t.coverUrl!.isNotEmpty) return t.coverUrl;
    }
    return null;
  }
}

/// 专辑 / 歌手分组卡（基本信息 + 展开歌曲列表）。
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.expanded,
    required this.onTap,
    required this.children,
  });

  final String title;
  final String subtitle;
  final String? coverUrl;
  final bool expanded;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final Widget fallback = ColoredBox(
      color: c.accentSoft,
      child: Icon(Icons.album_rounded, size: 20, color: c.accent),
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 分组头。
          Container(
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: coverUrl != null && coverUrl!.isNotEmpty
                              ? Image.network(
                                  coverUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => fallback,
                                  loadingBuilder: (BuildContext c2,
                                          Widget child, ImageChunkEvent? p) =>
                                      p == null ? child : fallback,
                                )
                              : fallback,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.appText.trackName),
                            const SizedBox(height: 2),
                            Text(subtitle,
                                style: context.appText.caption),
                          ],
                        ),
                      ),
                      Icon(
                        expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: c.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 展开的歌曲列表。
          if (expanded) ...<Widget>[
            const SizedBox(height: 8),
            ...children,
          ],
        ],
      ),
    );
  }
}

/// 歌单卡片。
class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.onTap});

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(Icons.queue_music_rounded, color: c.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.appText.trackName),
                      const SizedBox(height: 2),
                      Text(
                        '${playlist.trackCount} 首',
                        style: context.appText.caption,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
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

/// 列表式歌曲行（画布 track-row 345×64 r16；cl15 补投稿/收藏按钮）。
class _TrackRowCard extends StatelessWidget {
  const _TrackRowCard({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
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
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
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
                // cl15：投稿 / 收藏。
                TrackActionButtons(track: track),
                Icon(Icons.play_circle_rounded, size: 22, color: c.accent),
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

// ═══════ 纯函数（可单测）═══════════════════════════════════════════════

/// 按关键词过滤曲目（歌名 / 歌手 / 专辑）。
List<Track> _filter(List<Track> all, String query) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  return all
      .where((Track t) =>
          t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          (t.album ?? '').toLowerCase().contains(q))
      .toList();
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
