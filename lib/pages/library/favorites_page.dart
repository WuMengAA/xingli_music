/// 鏀惰棌涓庢瓕鍗曪紙cl46 鍏ㄥ眬鏁版嵁灞?UI锛夈€?
///
/// 涓や釜 Tab锛?
/// - 鏀惰棌锛氬叏閮ㄥ叏灞€鏀惰棌姝屾洸锛岀偣鎾€侀暱鎸夊姞鍏ユ瓕鍗?/ 鍙栨秷鏀惰棌銆?
/// - 姝屽崟锛氬叏灞€姝屽崟鍗＄墖锛堣嚜瀹氫箟鍚嶇О / 鐩稿唽鑳屾櫙鍥?/ 鎺掑簭鏂瑰紡锛夛紝
///   鐐硅繘璇︽儏鍙帓搴忋€佸鍒犳瓕鏇层€?
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
// 鏀惰棌涓庢瓕鍗曚富椤?
// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

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

  /// 鑷姩鏀跺綍锛氭墦寮€鏈〉鏃舵壂鎻忓惉姝屽巻鍙诧紝鍙戠幇鐩镐技姝屽悕/姝屾墜鍒欒闂敤鎴峰綊骞躲€?
  Future<void> _checkMergeCandidate() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final MergeCandidate? c =
          await ref.read(pendingMergeCandidateProvider.future);
      if (!mounted || c == null) return;
      final bool? merge = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text('妫€娴嬪埌鐩镐技姝屾洸', style: ctx.appText.title),
          content: Text(
            '銆?{c.source.title} 路 ${c.source.artist}銆峔n涓庡凡鏀跺綍鐨刓n銆?{c.canonical.title} 路 ${c.canonical.artist}銆峔n\n姝屾墜涓€鑷淬€佹瓕鍚嶇浉浼硷紝鏄惁涓哄悓涓€棣栵紵',
            style: ctx.appText.body,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('璺宠繃', style: ctx.appText.body),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('鏄紝褰掑苟',
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
        title: Text('鏀惰棌涓庢瓕鍗?,
            style: context.appText.title.copyWith(color: context.appColors.textPrimary)),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: context.appColors.accent,
          unselectedLabelColor: context.appColors.textSecondary,
          indicatorColor: context.appColors.accent,
          tabs: const <Tab>[Tab(text: '鏀惰棌'), Tab(text: '姝屽崟')],
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

// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
// 鏀惰棌 Tab
// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

class _FavoritesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FavoriteEntry>> favs = ref.watch(favoritesProvider);
    return favs.when(
      loading: () => const LoadingView(label: '鏀惰棌鍔犺浇涓€?),
      error: (Object e, StackTrace st) => ErrorView(
        message: '鏀惰棌鍔犺浇澶辫触锛岃绋嶅悗閲嶈瘯',
        onRetry: () => ref.invalidate(favoritesProvider),
      ),
      data: (List<FavoriteEntry> list) {
        if (list.isEmpty) {
          return const EmptyView(
            title: '杩樻病鏈夋敹钘?,
            message: '鎾斁涓偣蹇冨舰鍗冲彲鏀惰棌',
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
        content: Text('宸插姞鍏ユ瓕鍗?, style: context.appText.caption),
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
              title: Text('鍔犲叆姝屽崟', style: c.appText.body),
              onTap: () => Navigator.pop(c, 0),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_rounded),
              title: Text('鍙栨秷鏀惰棌', style: c.appText.body),
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

// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
// 姝屽崟 Tab
// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

class _PlaylistsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Playlist>> pls = ref.watch(playlistsProvider);
    return pls.when(
      loading: () => const LoadingView(label: '姝屽崟鍔犺浇涓€?),
      error: (Object e, StackTrace st) => ErrorView(
          message: '姝屽崟鍔犺浇澶辫触锛岃绋嶅悗閲嶈瘯',
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
          title: '鍒犻櫎姝屽崟銆?{playlist.name}銆嶏紵',
          message: '姝屽崟鍐呯殑姝屾洸涓嶄細浠庢洸搴撳垹闄ゃ€?,
          confirmLabel: '鍒犻櫎',
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
            Text('${playlist.trackCount} 棣?路 ${_sortLabel(playlist.sortMode)}',
                style: context.appText.caption.copyWith(color: Colors.white.withValues(alpha: 0.85))),
          ],
        ),
      ),
    );
  }

  static String _sortLabel(PlaylistSortMode m) => switch (m) {
        PlaylistSortMode.manual => '鎵嬪姩鎺掑簭',
        PlaylistSortMode.titleAsc => '姝屽悕 A鈫抁',
        PlaylistSortMode.titleDesc => '姝屽悕 Z鈫扐',
        PlaylistSortMode.playCountDesc => '鎸夋挱鏀炬鏁?,
        PlaylistSortMode.addedDesc => '鎸夋坊鍔犳椂闂?,
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
              Text('鏂板缓姝屽崟', style: context.appText.bodyMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 鏂板缓姝屽崟瀵硅瘽妗嗭細鍚嶇О + 鑳屾櫙鍥撅紙鏃?/ 鐩稿唽閫夊浘锛夈€?
Future<void> _showCreateDialog(
    BuildContext context, WidgetRef ref) async {
  final TextEditingController nameCtrl = TextEditingController();
  String? bgPath;

  await showDialog<void>(
    context: context,
    builder: (BuildContext c) => StatefulBuilder(
      builder: (BuildContext c, StateSetter setState) => AlertDialog(
        title: Text('鏂板缓姝屽崟', style: c.appText.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '姝屽崟鍚嶇О',
                labelText: '鍚嶇О',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text('鑳屾櫙鍥?, style: c.appText.body),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final String? path = await _pickBgImage();
                    if (path != null) setState(() => bgPath = path);
                  },
                  child: Text(bgPath == null ? '閫夋嫨鍥剧墖' : '宸查€夋嫨 鉁?,
                      style: c.appText.body.copyWith(color: c.appColors.accent)),
                ),
                if (bgPath != null)
                  TextButton(
                    onPressed: () => setState(() => bgPath = null),
                    child: Text('娓呴櫎', style: c.appText.bodyMuted),
                  ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('鍙栨秷', style: c.appText.body),
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
            child: Text('鍒涘缓', style: c.appText.body.copyWith(color: c.appColors.accent)),
          ),
        ],
      ),
    ),
  );
}

/// 鐢?file_picker 閫変竴寮犲浘鐗囷紝澶嶅埗鍒板簲鐢ㄦ枃妗ｇ洰褰曪紝杩斿洖鏈湴璺緞銆?
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
    return src; // 澶嶅埗澶辫触鍒欑洿鎺ョ敤鍘熻矾寰?
  }
}

String p_extension(String path) {
  final int i = path.lastIndexOf('.');
  return i < 0 ? '.png' : path.substring(i);
}

// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
// 鍔犲叆姝屽崟閫夋嫨鍣?
// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

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
            child: Text('鍔犲叆姝屽崟', style: context.appText.title),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Text('杩樻病鏈夋瓕鍗曪紝鍏堝幓姝屽崟椤垫柊寤?, style: context.appText.bodyMuted),
            )
          else
            ...list.map((Playlist p) => ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(p.name, style: context.appText.body),
                  subtitle: Text('${p.trackCount} 棣?,
                      style: context.appText.caption),
                  onTap: () => Navigator.pop(context, p.id),
                )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

