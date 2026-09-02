/// 鍏ㄥ眬鎾斁缁熻 / 鏀惰棌 / 姝屽崟 / 鍚瓕鍘嗗彶 鐨?SQLite 鏁版嵁灞傦紙cl46锛夈€?
///
/// 鍗曟枃浠?`music_stats.db`锛堝簲鐢ㄦ枃妗ｇ洰褰曪級鎵胯浇浜斿紶琛細
/// - `play_stats`锛氬崟鏇叉挱鏀炬鏁颁笌绱鏃堕暱锛堟敹褰曚俊鎭?/ 鎺掕姒滄暟鎹簮锛?
/// - `listen_history`锛氭瘡娆℃挱鏀剧殑鍚瓕鍘嗗彶锛堣嚜鍔ㄦ敹褰曟満鍒剁殑鏁版嵁婧愶級
/// - `favorites`锛氬叏灞€鏀惰棌
/// - `playlists` + `playlist_tracks`锛氬叏灞€姝屽崟
/// - `track_aliases`锛氳嚜鍔ㄥ綊绫荤殑鍒悕鏄犲皠锛堢浉浼兼洸鐩綊骞跺埌涓婚敭锛?
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import '../../core/paths.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/track_stats.dart';

class TrackStatsDb {
  TrackStatsDb._();
  static final TrackStatsDb instance = TrackStatsDb._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final Directory dir = await appDataDir();
    final String path = p.join(dir.path, 'music_stats.db');
    _db = await openDatabase(
      path,
      version: 3,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    return _db!;
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    // v1 鈫?v2锛氭柊澧炪€屽凡瑙ｆ瀽鐩撮摼缂撳瓨銆嶈〃锛堥噸鎾姞閫?/ 澶辨晥閲嶅尮閰嶏級銆?
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE resolved_links(
          track_key TEXT PRIMARY KEY,
          url TEXT NOT NULL,
          expire_at INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    // v2 鈫?v3锛歭isten_history 琛ュ叏鍙噸鎾瓧娈碉紙uri/cover/album/songId/extras锛夈€?
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE listen_history ADD COLUMN uri TEXT');
      await db.execute('ALTER TABLE listen_history ADD COLUMN cover_url TEXT');
      await db.execute('ALTER TABLE listen_history ADD COLUMN album TEXT');
      await db.execute('ALTER TABLE listen_history ADD COLUMN song_id TEXT');
      await db.execute('ALTER TABLE listen_history ADD COLUMN extras TEXT');
    }
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
    // v2锛氬凡瑙ｆ瀽鐩撮摼缂撳瓨锛堥噸鎾姞閫?/ 澶辨晥鑷姩閲嶅尮閰嶏級銆?
    await db.execute('''
      CREATE TABLE resolved_links(
        track_key TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        expire_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // 甯哥敤绱㈠紩锛氬巻鍙叉寜鏃堕棿鍊掑簭銆佹瓕鍗曞唴鎺掑簭銆?
    await db.execute(
        'CREATE INDEX idx_history_played_at ON listen_history(played_at)');
    await db.execute(
        'CREATE INDEX idx_pl_sort ON playlist_tracks(playlist_id, sort_index)');
  }

  /// 鎶?trackKey 褰掍竴鍒板畠鐨勬鍏?key锛堣嚜鍔ㄥ綊绫诲悗鎸囧悜涓绘潯鐩級銆?
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

  /// 鈹€鈹€ 鎾斁缁熻 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  /// 璁板綍涓€娆℃挱鏀剧粨绠楋細娆℃暟 +1銆佹椂闀跨疮鍔犮€佹洿鏂版椂闂淬€?
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

  /// 鍏ㄩ儴鎾斁缁熻锛堟寜娆℃暟闄嶅簭锛屾帓琛岀敤锛夈€?
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

  /// 鍏ㄥ眬鍚瓕鎬绘椂闀匡紙姣锛夈€?
  Future<int> totalPlayMs() async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db
        .rawQuery('SELECT COALESCE(SUM(total_ms), 0) AS t FROM play_stats');
    return rows.isEmpty ? 0 : rows.first['t'] as int;
  }

  // 鈹€鈹€ 鍚瓕鍘嗗彶锛堣嚜鍔ㄦ敹褰曟暟鎹簮锛夆攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  Future<void> addHistory(
    String trackKey,
    String title,
    String artist,
    String sourceId,
    int ms, {
    String? uri,
    String? coverUrl,
    String? album,
    String? songId,
    Map<String, dynamic>? extras,
  }) async {
    final Database db = await database;
    await db.insert('listen_history', <String, Object?>{
      'track_key': trackKey,
      'title': title,
      'artist': artist,
      'source_id': sourceId,
      'played_at': DateTime.now().millisecondsSinceEpoch,
      'duration_ms': ms < 0 ? 0 : ms,
      'uri': uri,
      'cover_url': coverUrl,
      'album': album,
      'song_id': songId,
      'extras': extras == null ? null : jsonEncode(extras),
    });
  }

  /// 銆屽惉杩囩殑姝屻€嶏細鎸?track_key 鍘婚噸锛堝彇鏈€杩戜竴娆℃挱鏀撅級锛屼緵鑷姩鍏ユ洸搴撱€?
  Future<List<ListenEntry>> heardTracks({int limit = 1000}) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT t1.* FROM listen_history t1
      WHERE t1.played_at = (
        SELECT MAX(t2.played_at) FROM listen_history t2
        WHERE t2.track_key = t1.track_key
      )
      ORDER BY t1.played_at DESC
      LIMIT ?
    ''', <Object>[limit]);
    return rows.map(ListenEntry.fromRow).toList();
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

  // 鈹€鈹€ 鍏ㄥ眬鏀惰棌 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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

  // 鈹€鈹€ 鍏ㄥ眬姝屽崟 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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

  /// 鎶婃瓕鏇插姞鍏ユ瓕鍗曪紙鍘婚噸锛夈€?
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

  /// 鎸夋帓搴忔柟寮忓彇姝屽崟鍐呮洸鐩€?
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

  // 鈹€鈹€ 鑷姩鏀跺綍锛堝埆鍚嶅綊骞讹級鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  /// 璁板綍涓€鏉″埆鍚嶆槧灏勶細鐩镐技鏇茬洰褰掑苟鍒版鍏?key銆?
  Future<void> addAlias(String trackKey, String canonicalKey) async {
    final Database db = await database;
    await db.insert('track_aliases', <String, Object?>{
      'track_key': trackKey,
      'canonical_key': canonicalKey,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 鏍囪銆岃烦杩囧綊骞惰闂€嶏細璇ユ洸涓嶅啀浣滀负褰掑苟鍊欓€夋墦鎵扮敤鎴枫€?
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

  // 鈹€鈹€ 宸茶В鏋愮洿閾剧紦瀛橈紙v2锛氶噸鎾姞閫?/ 澶辨晥閲嶅尮閰嶏級鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  /// 淇濆瓨鏌愭洸鏈€杩戜竴娆℃垚鍔熻В鏋愬嚭鐨勭洿閾句笌澶辨晥鏃堕棿锛坲psert锛夈€?
  Future<void> saveResolvedLink(
    String trackKey,
    String url, {
    int expireAtMs = 0,
  }) async {
    final Database db = await database;
    await db.insert(
      'resolved_links',
      <String, Object?>{
        'track_key': trackKey,
        'url': url,
        'expire_at': expireAtMs,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 璇诲彇鏌愭洸鐨勭洿閾剧紦瀛橈紙鏃犲垯杩斿洖 null锛夈€?
  Future<ResolvedLink?> resolvedLinkOf(String trackKey) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'resolved_links',
      where: 'track_key = ?',
      whereArgs: <Object>[trackKey],
      limit: 1,
    );
    return rows.isEmpty ? null : ResolvedLink.fromRow(rows.first);
  }

  /// 鍏ㄩ儴鐩撮摼缂撳瓨锛堜緵鎵归噺澶辨晥鍒ゆ柇 / 璋冭瘯锛夈€?
  Future<List<ResolvedLink>> allResolvedLinks() async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query('resolved_links');
    return rows.map(ResolvedLink.fromRow).toList();
  }
}

