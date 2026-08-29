/// 收藏与歌单（cl46 全局数据层 UI）。
///
/// 两个 Tab：
/// - 收藏：全部全局收藏歌曲，点播、长按加入歌单 / 取消收藏。
/// - 歌单：全局歌单卡片（自定义名称 / 相册背景图 / 排序方式），
///   点进详情可排序、增删歌曲。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/paths.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../services/stats/track_stats_db.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/app_confirm_dialog.dart';
import 'playlist_detail_page.dart';

// ════════════════════════════════════════════════════════════════════════
// 收藏与歌单主页
// ════════════════════════════════════════════════════════════════════════

class FavoritesAndPlaylistsPage extends ConsumerStatefulWidget {
  const FavoritesAndPlaylistsPage({super.key});

  @override
  ConsumerState<FavoritesAndPlaylistsPage> createState() =>
      _FavoritesAndPlaylistsPageState();
}

class _FavoritesAndPlaylistsPageState
    extends ConsumerState<FavoritesAndPlaylistsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl =
      TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _checkMergeCandidate();
  }

  /// 自动收录：打开本页时扫描听歌历史，发现相似歌名/歌手则询问用户归并。
  Future<void> _checkMergeCandidate() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final MergeCandidate? c =
          await ref.read(pendingMergeCandidateProvider.future);
      if (!mounted || c == null) return;
      final bool? merge = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text('检测到相似歌曲', style: ctx.appText.title),
          content: Text(
            '「${c.source.title} · ${c.source.artist}」\n与已收录的\n「${c.canonical.title} · ${c.canonical.artist}」\n\n歌手一致、歌名相似，是否为同一首？',
            style: ctx.appText.body,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('跳过', style: ctx.appText.body),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('是，归并',
                  style: ctx.appText.body.copyWith(color: ctx.appColors.accent)),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (merge == true) {
        await confirmMerge(ref, c);
      } else {
        await dismissMergeCandidate(ref, c);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      appBar: AppBar(
        backgroundColor: context.appColors.bgPage,
        title: Text('收藏与歌单',
            style: context.appText.title.copyWith(color: context.appColors.textPrimary)),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: context.appColors.accent,
          unselectedLabelColor: context.appColors.textSecondary,
          indicatorColor: context.appColors.accent,
          tabs: const <Tab>[Tab(text: '收藏'), Tab(text: '歌单')],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: <Widget>[
          _FavoritesTab(),
          _PlaylistsTab(),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 收藏 Tab
// ════════════════════════════════════════════════════════════════════════

class _FavoritesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FavoriteEntry>> favs = ref.watch(favoritesProvider);
    return favs.when(
      loading: () => const LoadingView(label: '收藏加载中…'),
      error: (Object e, StackTrace st) => ErrorView(
        message: '收藏加载失败，请稍后重试',
        onRetry: () => ref.invalidate(favoritesProvider),
      ),
      data: (List<FavoriteEntry> list) {
        if (list.isEmpty) {
          return const EmptyView(
            title: '还没有收藏',
            message: '播放中点心形即可收藏',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpace.md),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (BuildContext context, int i) =>
              _FavoriteTile(entry: list[i]),
        );
      },
    );
  }
}

class _FavoriteTile extends ConsumerWidget {
  const _FavoriteTile({required this.entry});

  final FavoriteEntry entry;

  Future<Track?> _match(WidgetRef ref) async {
    final List<Track> all = await ref.read(effectiveMusicLibraryProvider.future);
    final String key = trackKeyOf(entry.title, entry.artist, entry.sourceId);
    for (final Track t in all) {
      if (trackKeyOf(t.title, t.artist, t.sourceId) == key) return t;
    }
    return null;
  }

  Future<void> _addToPlaylist(BuildContext context, WidgetRef ref) async {
    final String key = trackKeyOf(entry.title, entry.artist, entry.sourceId);
    final List<Playlist> pls = await ref.read(playlistsProvider.future);
    if (!context.mounted) return;
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext c) => _PlaylistPicker(playlists: pls),
    );
    if (picked == null) return;
    await ref
        .read(trackStatsDbProvider)
        .addToPlaylist(picked, key, entry.title, entry.artist, entry.sourceId);
    ref.invalidate(playlistTracksProvider(picked));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已加入歌单', style: context.appText.caption),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String key = trackKeyOf(entry.title, entry.artist, entry.sourceId);
    final Widget tile = ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: entry.coverUrl != null
            ? Image.network(
                entry.coverUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _FavFallback(),
              )
            : const _FavFallback(),
      ),
      title: Text(entry.title,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: context.appText.trackName),
      subtitle: Text(entry.artist,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: context.appText.artist),
      onTap: () async {
        final Track? t = await _match(ref);
        if (t == null || !context.mounted) return;
        await ref.read(audioServiceProvider).playMusic(t);
      },
      onLongPress: () => _showMenu(context, ref, key),
    );
    return Material(
      color: Colors.transparent,
      child: tile,
    );
  }

  Future<void> _showMenu(
      BuildContext context, WidgetRef ref, String key) async {
    final TrackStatsDb db = ref.read(trackStatsDbProvider);
    final int? choice = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text('加入歌单', style: c.appText.body),
              onTap: () => Navigator.pop(c, 0),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_rounded),
              title: Text('取消收藏', style: c.appText.body),
              onTap: () => Navigator.pop(c, 1),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 1) {
      await db.toggleFavorite(key, entry.title, entry.artist, entry.sourceId, entry.coverUrl);
      ref.invalidate(favoritesProvider);
      ref.invalidate(isFavoriteProvider(key));
    } else {
      await _addToPlaylist(context, ref);
    }
  }
}

class _FavFallback extends StatelessWidget {
  const _FavFallback();

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        color: context.appColors.accent.withValues(alpha: 0.12),
        child: Icon(Icons.music_note_rounded,
            size: 22, color: context.appColors.accent),
      );
}

// ════════════════════════════════════════════════════════════════════════
// 歌单 Tab
// ════════════════════════════════════════════════════════════════════════

class _PlaylistsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Playlist>> pls = ref.watch(playlistsProvider);
    return pls.when(
      loading: () => const LoadingView(label: '歌单加载中…'),
      error: (Object e, StackTrace st) => ErrorView(
          message: '歌单加载失败，请稍后重试',
        onRetry: () => ref.invalidate(playlistsProvider),
      ),
      data: (List<Playlist> list) {
        return CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.all(AppSpace.md),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    if (i >= list.length) {
                      return _NewPlaylistCard();
                    }
                    return _PlaylistCard(playlist: list[i]);
                  },
                  childCount: list.length + 1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BoxDecoration bg = playlist.bgPath != null &&
            File(playlist.bgPath!).existsSync()
        ? BoxDecoration(
            image: DecorationImage(
              image: FileImage(File(playlist.bgPath!)),
              fit: BoxFit.cover,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          )
        : BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                context.appColors.accent.withValues(alpha: 0.55),
                context.appColors.accent.withValues(alpha: 0.20),
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          );

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailPage(playlistId: playlist.id!),
      )),
      onLongPress: () async {
        final bool? ok = await AppConfirmDialog.show(
          context: context,
          title: '删除歌单「${playlist.name}」？',
          message: '歌单内的歌曲不会从曲库删除。',
          confirmLabel: '删除',
          confirmDanger: true,
        );
        if (ok == true) {
          await ref.read(trackStatsDbProvider).deletePlaylist(playlist.id!);
          ref.invalidate(playlistsProvider);
        }
      },
      child: Container(
        decoration: bg,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Icon(Icons.queue_music_rounded,
                size: 22, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(height: 4),
            Text(playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appText.trackName.copyWith(color: Colors.white)),
            Text('${playlist.trackCount} 首 · ${_sortLabel(playlist.sortMode)}',
                style: context.appText.caption.copyWith(color: Colors.white.withValues(alpha: 0.85))),
          ],
        ),
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

class _NewPlaylistCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => _showCreateDialog(context, ref),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
              color: context.appColors.accent.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.add_circle_outline_rounded,
                  size: 28, color: context.appColors.accent),
              const SizedBox(height: 6),
              Text('新建歌单', style: context.appText.bodyMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 新建歌单对话框：名称 + 背景图（无 / 相册选图）。
Future<void> _showCreateDialog(
    BuildContext context, WidgetRef ref) async {
  final TextEditingController nameCtrl = TextEditingController();
  String? bgPath;

  await showDialog<void>(
    context: context,
    builder: (BuildContext c) => StatefulBuilder(
      builder: (BuildContext c, StateSetter setState) => AlertDialog(
        title: Text('新建歌单', style: c.appText.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '歌单名称',
                labelText: '名称',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text('背景图', style: c.appText.body),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final String? path = await _pickBgImage();
                    if (path != null) setState(() => bgPath = path);
                  },
                  child: Text(bgPath == null ? '选择图片' : '已选择 ✓',
                      style: c.appText.body.copyWith(color: c.appColors.accent)),
                ),
                if (bgPath != null)
                  TextButton(
                    onPressed: () => setState(() => bgPath = null),
                    child: Text('清除', style: c.appText.bodyMuted),
                  ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('取消', style: c.appText.body),
          ),
          TextButton(
            onPressed: () async {
              final String name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await ref.read(trackStatsDbProvider).createPlaylist(
                    name,
                    bgType: bgPath == null
                        ? PlaylistBgType.none
                        : PlaylistBgType.gallery,
                    bgPath: bgPath,
                  );
              ref.invalidate(playlistsProvider);
              if (c.mounted) Navigator.pop(c);
            },
            child: Text('创建', style: c.appText.body.copyWith(color: c.appColors.accent)),
          ),
        ],
      ),
    ),
  );
}

/// 用 file_picker 选一张图片，复制到应用文档目录，返回本地路径。
Future<String?> _pickBgImage() async {
  final FilePickerResult? result =
      await FilePicker.pickFiles(type: FileType.image);
  final String? src = result?.files.single.path;
  if (src == null) return null;
  try {
    final Directory dir = await appDataDir();
    final Directory bgDir = Directory('${dir.path}/playlist_bg');
    if (!bgDir.existsSync()) bgDir.createSync(recursive: true);
    final String name =
        'bg_${DateTime.now().millisecondsSinceEpoch}${p_extension(src)}';
    final String dst = '${bgDir.path}/$name';
    File(src).copySync(dst);
    return dst;
  } catch (_) {
    return src; // 复制失败则直接用原路径
  }
}

String p_extension(String path) {
  final int i = path.lastIndexOf('.');
  return i < 0 ? '.png' : path.substring(i);
}

// ════════════════════════════════════════════════════════════════════════
// 加入歌单选择器
// ════════════════════════════════════════════════════════════════════════

class _PlaylistPicker extends StatelessWidget {
  const _PlaylistPicker({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    final List<Playlist> list = playlists;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Text('加入歌单', style: context.appText.title),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Text('还没有歌单，先去歌单页新建', style: context.appText.bodyMuted),
            )
          else
            ...list.map((Playlist p) => ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(p.name, style: context.appText.body),
                  subtitle: Text('${p.trackCount} 首',
                      style: context.appText.caption),
                  onTap: () => Navigator.pop(context, p.id),
                )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
