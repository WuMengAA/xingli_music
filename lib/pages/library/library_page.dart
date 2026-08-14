import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/library/library_view_providers.dart';
import '../../providers/shell/shell_providers.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/library/album_view.dart';
import '../../widgets/library/card_view.dart';
import '../../widgets/library/folder_view.dart';
import '../../widgets/shell/app_search_bar.dart';

/// 曲库页 · 分页浏览（R26fx：歌曲 / 专辑 / 艺术家 三 Tab）。
///
/// - **歌曲** Tab：现有三形态浏览（卡片 / 文件夹 / 专辑）+ 搜索。
/// - **专辑** Tab：按专辑分组的列表（专辑名 → 曲数 / 首曲）。
/// - **艺术家** Tab：按歌手分组的列表（歌手名 → 曲数）。
/// - 同一数据源：`effectiveMusicLibraryProvider`。
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String query = ref.watch(searchQueryProvider(ShellPage.library));
    final LibraryViewStyle style = ref.watch(libraryViewStyleProvider);
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);

    return DefaultTabController(
      length: 3,
      child: PageScaffold(
        title: Terms.library,
        search: AppSearchBar(
          hintText: '搜索歌曲、歌手、专辑',
          query: query,
          onChanged: (String v) =>
              ref.read(searchQueryProvider(ShellPage.library).notifier).state = v,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // R26fx：曲库分页 Tab（歌曲 / 专辑 / 艺术家）。
            TabBar(
              labelColor: context.appColors.accent,
              unselectedLabelColor: context.appColors.textSecondary,
              indicatorColor: context.appColors.accent,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const <Tab>[
                Tab(text: '歌曲'),
                Tab(text: '专辑'),
                Tab(text: '艺术家'),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            // R26fx：样式切换器提到 TabBarView 外；紧凑视觉避免横屏溢出。
            SegmentedButton<LibraryViewStyle>(
                segments: const <ButtonSegment<LibraryViewStyle>>[
                  ButtonSegment<LibraryViewStyle>(
                    value: LibraryViewStyle.card,
                    icon: Icon(Icons.grid_view_rounded),
                    label: Text('卡片'),
                  ),
                  ButtonSegment<LibraryViewStyle>(
                    value: LibraryViewStyle.folder,
                    icon: Icon(Icons.folder_rounded),
                    label: Text('文件夹'),
                  ),
                  ButtonSegment<LibraryViewStyle>(
                    value: LibraryViewStyle.album,
                    icon: Icon(Icons.album_rounded),
                    label: Text('专辑'),
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
            Expanded(
              child: library.when(
                data: (List<Track> all) {
                  final List<Track> filtered = _filter(all, query);
                  return TabBarView(
                    children: <Widget>[
                      // 歌曲：三形态视图（切换器在 TabBarView 外）。
                      _buildView(style, filtered),
                      // 专辑分组。
                      _GroupListView(
                        title: '全部专辑',
                        groups: _groupByAlbum(filtered),
                        icon: Icons.album_rounded,
                      ),
                      // 艺术家分组。
                      _GroupListView(
                        title: '全部歌手',
                        groups: _groupByArtist(filtered),
                        icon: Icons.person_outline_rounded,
                      ),
                    ],
                  );
                },
                loading: () => const LoadingView(label: '曲库加载中…'),
                error: (Object e, StackTrace st) => ErrorView(
                  message: '曲库加载失败：$e',
                  onRetry: () => ref.invalidate(effectiveMusicLibraryProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildView(LibraryViewStyle style, List<Track> tracks) {
    return switch (style) {
      LibraryViewStyle.card => CardView(tracks: tracks),
      LibraryViewStyle.folder => FolderView(tracks: tracks),
      LibraryViewStyle.album => AlbumView(tracks: tracks),
    };
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

  /// 按专辑名分组（空专辑归入「未分类」）。
  List<(String, List<Track>)> _groupByAlbum(List<Track> tracks) {
    final Map<String, List<Track>> map = <String, List<Track>>{};
    for (final Track t in tracks) {
      final String k = (t.album == null || t.album!.isEmpty)
          ? '未分类'
          : t.album!;
      map.putIfAbsent(k, () => <Track>[]).add(t);
    }
    final List<String> keys = map.keys.toList()..sort();
    return <(String, List<Track>)>[
      for (final String k in keys) (k, map[k]!),
    ];
  }

  /// 按歌手名分组。
  List<(String, List<Track>)> _groupByArtist(List<Track> tracks) {
    final Map<String, List<Track>> map = <String, List<Track>>{};
    for (final Track t in tracks) {
      final String k = t.artist.isEmpty ? '未知歌手' : t.artist;
      map.putIfAbsent(k, () => <Track>[]).add(t);
    }
    final List<String> keys = map.keys.toList()..sort();
    return <(String, List<Track>)>[
      for (final String k in keys) (k, map[k]!),
    ];
  }
}

/// 分组列表（专辑 / 艺术家共用）。
class _GroupListView extends StatelessWidget {
  const _GroupListView({
    required this.title,
    required this.groups,
    required this.icon,
  });

  final String title;
  final List<(String, List<Track>)> groups;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const EmptyView(title: '暂无内容', message: '这里还没有条目');
    }
    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int i) {
        final (String name, List<Track> tracks) = groups[i];
        final Track first = tracks.first;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: context.appColors.accent.withValues(alpha: 0.18),
            child: Icon(icon, size: 18, color: context.appColors.accent),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${tracks.length} 首 · ${first.artist}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded, size: 18),
          onTap: () {},
        );
      },
    );
  }
}
