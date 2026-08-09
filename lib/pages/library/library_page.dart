import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 曲库页 · 三形态浏览（v2 M3 · P0-M3-1~6）。
///
/// - 同一数据源：`effectiveMusicLibraryProvider`（三视图全部 watch 它）。
/// - 样式切换器：卡片 / 文件夹 / 专辑（`SegmentedButton`），持久化。
/// - 搜索：三种样式下均过滤当前视图。
/// - 切样式不触碰 `nowPlayingProvider`，播放上下文保持（P1-M3-5）。
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String query = ref.watch(searchQueryProvider(ShellPage.library));
    final LibraryViewStyle style = ref.watch(libraryViewStyleProvider);
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);

    return PageScaffold(
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
          // 样式切换器（P0-M3-1）
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
            onSelectionChanged: (Set<LibraryViewStyle> selection) {
              ref
                  .read(libraryViewStyleProvider.notifier)
                  .setStyle(selection.first);
            },
            showSelectedIcon: false,
          ),
          const SizedBox(height: AppSpace.md),
          Expanded(
            child: library.when(
              data: (List<Track> all) {
                final List<Track> filtered = _filter(all, query);
                return _buildView(style, filtered);
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
}
