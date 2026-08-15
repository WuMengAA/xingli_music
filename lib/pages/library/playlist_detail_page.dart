/// 歌单详情页（cl46）：查看 / 排序 / 增删歌单内歌曲。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../services/stats/track_stats_db.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/notification/app_notify.dart';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final int playlistId;

  @override
  ConsumerState<PlaylistDetailPage> createState() =>
      _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  PlaylistSortMode _sortMode = PlaylistSortMode.manual;
  String _name = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Playlist> all = await ref.read(playlistsProvider.future);
    final Playlist? pl = all
        .where((Playlist p) => p.id == widget.playlistId)
        .firstOrNull;
    if (pl != null) {
      setState(() {
        _name = pl.name;
        _sortMode = pl.sortMode;
      });
    }
  }

  Future<Track?> _matchTrack(
      WidgetRef ref, String title, String artist, String sourceId) async {
    final List<Track> all =
        await ref.read(effectiveMusicLibraryProvider.future);
    final String key = trackKeyOf(title, artist, sourceId);
    for (final Track t in all) {
      if (trackKeyOf(t.title, t.artist, t.sourceId) == key) return t;
    }
    return null;
  }

  Future<void> _addTracks(BuildContext context) async {
    final List<Track> all =
        await ref.read(effectiveMusicLibraryProvider.future);
    if (!context.mounted) return;
    final List<Track>? picked = await showDialog<List<Track>>(
      context: context,
      builder: (BuildContext c) => _AddTracksDialog(all: all),
    );
    if (picked == null || picked.isEmpty) return;
    final TrackStatsDb db = ref.read(trackStatsDbProvider);
    for (final Track t in picked) {
      await db.addToPlaylist(widget.playlistId, trackKeyOf(t.title, t.artist, t.sourceId),
          t.title, t.artist, t.sourceId);
    }
    ref.invalidate(playlistTracksProvider(widget.playlistId));
    ref.invalidate(playlistsProvider);
  }

  Future<void> _setSort(PlaylistSortMode mode) async {
    setState(() => _sortMode = mode);
    await ref
        .read(trackStatsDbProvider)
        .updatePlaylist(widget.playlistId, sortMode: mode);
    ref.invalidate(playlistTracksProvider(widget.playlistId));
  }

  Future<void> _move(
      List<PlaylistTrack> list, int index, int delta) async {
    final int target = index + delta;
    if (target < 0 || target >= list.length) return;
    final List<PlaylistTrack> reordered = List<PlaylistTrack>.of(list);
    final PlaylistTrack t = reordered.removeAt(index);
    reordered.insert(target, t);
    await ref
        .read(trackStatsDbProvider)
        .reorderPlaylistTracks(widget.playlistId,
            reordered.map((PlaylistTrack x) => x.trackKey).toList());
    ref.invalidate(playlistTracksProvider(widget.playlistId));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<PlaylistTrack>> tracks =
        ref.watch(playlistTracksProvider(widget.playlistId));
    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      appBar: AppBar(
        backgroundColor: context.appColors.bgPage,
        title: Text(_name.isEmpty ? '歌单' : _name,
            style: context.appText.title.copyWith(color: context.appColors.textPrimary)),
        actions: <Widget>[
          PopupMenuButton<PlaylistSortMode>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: '排序方式',
            onSelected: _setSort,
            itemBuilder: (BuildContext c) => <PopupMenuEntry<PlaylistSortMode>>[
              for (final PlaylistSortMode m in PlaylistSortMode.values)
                PopupMenuItem<PlaylistSortMode>(
                  value: m,
                  child: Text(_sortLabel(m), style: c.appText.body),
                ),
            ],
          ),
          IconButton(
            tooltip: '添加歌曲',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _addTracks(context),
          ),
        ],
      ),
      body: tracks.when(
        loading: () => const LoadingView(label: '歌单加载中…'),
        error: (Object e, StackTrace st) => ErrorView(
          message: '加载失败：$e',
          onRetry: () =>
              ref.invalidate(playlistTracksProvider(widget.playlistId)),
        ),
        data: (List<PlaylistTrack> list) {
          if (list.isEmpty) {
            return const EmptyView(
              title: '歌单是空的',
              message: '点右上角 + 添加歌曲',
            );
          }
          return ReorderableListView.builder(
            itemCount: list.length,
            onReorder: _sortMode == PlaylistSortMode.manual
                ? (int oldIndex, int newIndex) {
                    final int target =
                        newIndex > oldIndex ? newIndex - 1 : newIndex;
                    _move(list, oldIndex, target);
                  }
                : null,
            itemBuilder: (BuildContext c, int i) {
              final PlaylistTrack t = list[i];
              return ListTile(
                key: ValueKey<String>(t.trackKey),
                leading: Text('${i + 1}',
                    style: context.appText.caption),
                title: Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.appText.trackName),
                subtitle: Text(t.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.appText.artist),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_sortMode == PlaylistSortMode.manual) ...<Widget>[
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up_rounded,
                            size: 18),
                        onPressed: () => _move(list, i, -1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            size: 18),
                        onPressed: () => _move(list, i, 1),
                      ),
                    ],
                    IconButton(
                      tooltip: '移除',
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                          size: 18),
                      onPressed: () async {
                        await ref
                            .read(trackStatsDbProvider)
                            .removeFromPlaylist(widget.playlistId, t.trackKey);
                        ref.invalidate(
                            playlistTracksProvider(widget.playlistId));
                        ref.invalidate(playlistsProvider);
                      },
                    ),
                  ],
                ),
                onTap: () async {
                  final Track? tr = await _matchTrack(
                      ref, t.title, t.artist, t.sourceId);
                  // cl53-F5：报错通知走全局通知（与全局通知一致）。
                  if (tr == null || !c.mounted) {
                    if (c.mounted) appNotify(c, '曲库中找不到该曲目');
                    return;
                  }
                  await ref.read(audioServiceProvider).playMusic(tr);
                },
              );
            },
          );
        },
      ),
    );
  }

  static String _sortLabel(PlaylistSortMode m) => switch (m) {
        PlaylistSortMode.manual => '手动排序',
        PlaylistSortMode.titleAsc => '歌名 A→Z',
        PlaylistSortMode.titleDesc => '歌名 Z→A',
        PlaylistSortMode.playCountDesc => '按播放次数',
        PlaylistSortMode.addedDesc => '按添加时间',
      };
}

/// 添加歌曲对话框：搜索曲库 + 多选。
class _AddTracksDialog extends StatefulWidget {
  const _AddTracksDialog({required this.all});

  final List<Track> all;

  @override
  State<_AddTracksDialog> createState() => _AddTracksDialogState();
}

class _AddTracksDialogState extends State<_AddTracksDialog> {
  String _q = '';
  final Set<String> _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final List<Track> filtered = widget.all
        .where((Track t) =>
            _q.isEmpty ||
            t.title.toLowerCase().contains(_q.toLowerCase()) ||
            t.artist.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text('添加歌曲', style: context.appText.title),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          children: <Widget>[
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索歌曲 / 歌手',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (String v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (BuildContext c, int i) {
                  final Track t = filtered[i];
                  final String key =
                      trackKeyOf(t.title, t.artist, t.sourceId);
                  final bool on = _picked.contains(key);
                  return CheckboxListTile(
                    dense: true,
                    value: on,
                    title: Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.appText.body),
                    subtitle: Text(t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.appText.caption),
                    onChanged: (bool? v) => setState(() {
                      if (v == true) {
                        _picked.add(key);
                      } else {
                        _picked.remove(key);
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: context.appText.body),
        ),
        TextButton(
          onPressed: _picked.isEmpty
              ? null
              : () {
                  final List<Track> selected = filtered
                      .where((Track t) =>
                          _picked.contains(
                              trackKeyOf(t.title, t.artist, t.sourceId)))
                      .toList();
                  Navigator.pop(context, selected);
                },
          child: Text('添加（${_picked.length}）',
              style: context.appText.body.copyWith(color: context.appColors.accent)),
        ),
      ],
    );
  }
}
