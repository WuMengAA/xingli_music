/// 全局播放统计 / 收藏 / 歌单 / 听歌历史 的 SQLite 数据层（cl46）。
///
/// 单文件 `music_stats.db`（应用文档目录）承载五张表：
/// - `play_stats`：单曲播放次数与累计时长（收录信息 / 排行榜数据源）
/// - `listen_history`：每次播放的听歌历史（自动收录机制的数据源）
/// - `favorites`：全局收藏
/// - `playlists` + `playlist_tracks`：全局歌单
/// - `track_aliases`：自动归类的别名映射（相似曲目归并到主键）
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/track_stats.dart';

class TrackStatsDb {
  TrackStatsDb._();
  static final TrackStatsDb instance = TrackStatsDb._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final Directory dir = await getApplicationDocumentsDirectory();
    final String path = p.join(dir.path, 'music_stats.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: _create,
    );
    return _db!;
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE play_stats(
        track_key TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT DEFAULT '',
        source_id TEXT DEFAULT '',
        play_count INTEGER NOT NULL DEFAULT 0,
        total_ms INTEGER NOT NULL DEFAULT 0,
        last_played_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE listen_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_key TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT DEFAULT '',
        source_id TEXT DEFAULT '',
        played_at INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE favorites(
        track_key TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT DEFAULT '',
        source_id TEXT DEFAULT '',
        cover_url TEXT,
        added_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE playlists(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        bg_type INTEGER NOT NULL DEFAULT 0,
        bg_path TEXT,
        sort_mode INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE playlist_tracks(
        playlist_id INTEGER NOT NULL,
        track_key TEXT NOT NULL,
        sort_index INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(playlist_id, track_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE track_aliases(
        track_key TEXT PRIMARY KEY,
        canonical_key TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE merge_dismissed(
        track_key TEXT PRIMARY KEY,
        dismissed_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // 常用索引：历史按时间倒序、歌单内排序。
    await db.execute(
        'CREATE INDEX idx_history_played_at ON listen_history(played_at)');
    await db.execute(
        'CREATE INDEX idx_pl_sort ON playlist_tracks(playlist_id, sort_index)');
  }

  /// 把 trackKey 归一到它的正典 key（自动归类后指向主条目）。
  Future<String> canonicalKey(Database db, String trackKey) async {
    final List<Map<String, dynamic>> rows = await db.query(
      'track_aliases',
      columns: const <String>['canonical_key'],
      where: 'track_key = ?',
      whereArgs: <Object>[trackKey],
      limit: 1,
    );
    return rows.isEmpty ? trackKey : rows.first['canonical_key'] as String;
  }

  /// ── 播放统计 ──────────────────────────────────────────────────────────

  /// 记录一次播放结算：次数 +1、时长累加、更新时间。
  Future<void> addPlay(
    String trackKey,
    String title,
    String artist,
    String sourceId,
    int ms,
  ) async {
    final Database db = await database;
    final String canonical = await canonicalKey(db, trackKey);
    final int now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'play_stats',
      <String, Object?>{
        'track_key': canonical,
        'title': title,
        'artist': artist,
        'source_id': sourceId,
        'play_count': 1,
        'total_ms': ms < 0 ? 0 : ms,
        'last_played_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.rawUpdate(
      'UPDATE play_stats SET play_count = play_count + 1, '
      'total_ms = total_ms + ?, last_played_at = ? WHERE track_key = ?',
      <Object>[ms < 0 ? 0 : ms, now, canonical],
    );
  }

  /// 全部播放统计（按次数降序，排行用）。
  Future<List<TrackStats>> allStats() async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'play_stats',
      orderBy: 'play_count DESC, total_ms DESC',
    );
    return rows.map(TrackStats.fromRow).toList();
  }

  Future<TrackStats?> statOf(String trackKey) async {
    final Database db = await database;
    final String canonical = await canonicalKey(db, trackKey);
    final List<Map<String, dynamic>> rows = await db.query(
      'play_stats',
      where: 'track_key = ?',
      whereArgs: <Object>[canonical],
      limit: 1,
    );
    return rows.isEmpty ? null : TrackStats.fromRow(rows.first);
  }

  /// 全局听歌总时长（毫秒）。
  Future<int> totalPlayMs() async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db
        .rawQuery('SELECT COALESCE(SUM(total_ms), 0) AS t FROM play_stats');
    return rows.isEmpty ? 0 : rows.first['t'] as int;
  }

  // ── 听歌历史（自动收录数据源）─────────────────────────────────────────

  Future<void> addHistory(
    String trackKey,
    String title,
    String artist,
    String sourceId,
    int ms,
  ) async {
    final Database db = await database;
    await db.insert('listen_history', <String, Object?>{
      'track_key': trackKey,
      'title': title,
      'artist': artist,
      'source_id': sourceId,
      'played_at': DateTime.now().millisecondsSinceEpoch,
      'duration_ms': ms < 0 ? 0 : ms,
    });
  }

  Future<List<ListenEntry>> recentHistory({int limit = 200}) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'listen_history',
      orderBy: 'played_at DESC',
      limit: limit,
    );
    return rows.map(ListenEntry.fromRow).toList();
  }

  // ── 全局收藏 ──────────────────────────────────────────────────────────

  Future<void> toggleFavorite(
    String trackKey,
    String title,
    String artist,
    String sourceId,
    String? coverUrl,
  ) async {
    final Database db = await database;
    if (await isFavorite(trackKey)) {
      await db.delete('favorites', where: 'track_key = ?', whereArgs: <Object>[trackKey]);
    } else {
      await db.insert('favorites', <String, Object?>{
        'track_key': trackKey,
        'title': title,
        'artist': artist,
        'source_id': sourceId,
        'cover_url': coverUrl,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<bool> isFavorite(String trackKey) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'favorites',
      columns: const <String>['track_key'],
      where: 'track_key = ?',
      whereArgs: <Object>[trackKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<FavoriteEntry>> favorites() async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'favorites',
      orderBy: 'added_at DESC',
    );
    return rows.map(FavoriteEntry.fromRow).toList();
  }

  // ── 全局歌单 ──────────────────────────────────────────────────────────

  Future<int> createPlaylist(String name,
      {PlaylistBgType bgType = PlaylistBgType.none, String? bgPath}) async {
    final Database db = await database;
    return db.insert('playlists', <String, Object?>{
      'name': name,
      'bg_type': bgType.index,
      'bg_path': bgPath,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updatePlaylist(
    int id, {
    String? name,
    PlaylistBgType? bgType,
    String? bgPath,
    PlaylistSortMode? sortMode,
  }) async {
    final Database db = await database;
    final Map<String, Object?> values = <String, Object?>{};
    if (name != null) values['name'] = name;
    if (bgType != null) values['bg_type'] = bgType.index;
    if (bgPath != null) values['bg_path'] = bgPath;
    if (sortMode != null) values['sort_mode'] = sortMode.index;
    await db.update('playlists', values,
        where: 'id = ?', whereArgs: <Object>[id]);
  }

  Future<void> deletePlaylist(int id) async {
    final Database db = await database;
    await db.delete('playlists', where: 'id = ?', whereArgs: <Object>[id]);
    await db.delete('playlist_tracks',
        where: 'playlist_id = ?', whereArgs: <Object>[id]);
  }

  Future<List<Playlist>> playlists() async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT p.*, (SELECT COUNT(*) FROM playlist_tracks t
                   WHERE t.playlist_id = p.id) AS track_count
      FROM playlists p ORDER BY p.created_at DESC
    ''');
    return rows.map(Playlist.fromRow).toList();
  }

  /// 把歌曲加入歌单（去重）。
  Future<void> addToPlaylist(
    int playlistId,
    String trackKey,
    String title,
    String artist,
    String sourceId,
  ) async {
    final Database db = await database;
    final String canonical = await canonicalKey(db, trackKey);
    final List<Map<String, dynamic>> existing = await db.query(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_key = ?',
      whereArgs: <Object>[playlistId, canonical],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    final List<Map<String, dynamic>> maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_index), -1) AS m FROM playlist_tracks '
      'WHERE playlist_id = ?',
      <Object>[playlistId],
    );
    final int next = (maxRow.isEmpty ? -1 : maxRow.first['m'] as int) + 1;
    await db.insert('playlist_tracks', <String, Object?>{
      'playlist_id': playlistId,
      'track_key': canonical,
      'sort_index': next,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> removeFromPlaylist(int playlistId, String trackKey) async {
    final Database db = await database;
    await db.delete('playlist_tracks',
        where: 'playlist_id = ? AND track_key = ?',
        whereArgs: <Object>[playlistId, trackKey]);
  }

  Future<void> reorderPlaylistTracks(
      int playlistId, List<String> orderedKeys) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      for (int i = 0; i < orderedKeys.length; i++) {
        await txn.update(
          'playlist_tracks',
          <String, Object?>{'sort_index': i},
          where: 'playlist_id = ? AND track_key = ?',
          whereArgs: <Object>[playlistId, orderedKeys[i]],
        );
      }
    });
  }

  /// 按排序方式取歌单内曲目。
  Future<List<PlaylistTrack>> playlistTracks(int playlistId,
      {PlaylistSortMode sortMode = PlaylistSortMode.manual}) async {
    final Database db = await database;
    final String orderBy = switch (sortMode) {
      PlaylistSortMode.manual => 'sort_index ASC, added_at ASC',
      PlaylistSortMode.titleAsc => 'title COLLATE NOCASE ASC',
      PlaylistSortMode.titleDesc => 'title COLLATE NOCASE DESC',
      PlaylistSortMode.playCountDesc => 'play_count DESC',
      PlaylistSortMode.addedDesc => 'added_at DESC',
    };
    final String sortJoin = switch (sortMode) {
      PlaylistSortMode.playCountDesc =>
        'LEFT JOIN play_stats s ON s.track_key = t.track_key',
      _ => '',
    };
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT t.*, $sortJoin '
      'FROM playlist_tracks t $sortJoin WHERE t.playlist_id = ? ORDER BY $orderBy',
      <Object>[playlistId],
    );
    return rows.map(PlaylistTrack.fromRow).toList();
  }

  // ── 自动收录（别名归并）───────────────────────────────────────────────

  /// 记录一条别名映射：相似曲目归并到正典 key。
  Future<void> addAlias(String trackKey, String canonicalKey) async {
    final Database db = await database;
    await db.insert('track_aliases', <String, Object?>{
      'track_key': trackKey,
      'canonical_key': canonicalKey,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 标记「跳过归并询问」：该曲不再作为归并候选打扰用户。
  Future<void> dismissMerge(String trackKey) async {
    final Database db = await database;
    await db.insert('merge_dismissed', <String, Object?>{
      'track_key': trackKey,
      'dismissed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> isMergeDismissed(String trackKey) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'merge_dismissed',
      columns: const <String>['track_key'],
      where: 'track_key = ?',
      whereArgs: <Object>[trackKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
