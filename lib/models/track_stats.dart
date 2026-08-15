/// 播放统计 / 收藏 / 歌单 / 听歌历史 的数据模型（cl46 全局数据层）。
library;

/// 单曲播放统计。
class TrackStats {
  const TrackStats({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.sourceId,
    this.playCount = 0,
    this.totalMs = 0,
    this.lastPlayedAt,
  });

  /// 曲目唯一键：`title|artist|sourceId` 归一化（区分大小写、保留原文）。
  final String trackKey;
  final String title;
  final String artist;
  final String sourceId;

  /// 播放次数（开始播放且超过计次阈值即 +1）。
  final int playCount;

  /// 累计收听毫秒（含暂停前的有效播放）。
  final int totalMs;

  final DateTime? lastPlayedAt;

  TrackStats copyWith({
    int? playCount,
    int? totalMs,
    DateTime? lastPlayedAt,
  }) =>
      TrackStats(
        trackKey: trackKey,
        title: title,
        artist: artist,
        sourceId: sourceId,
        playCount: playCount ?? this.playCount,
        totalMs: totalMs ?? this.totalMs,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      );

  /// 累计收听时长（人类可读）。
  String get totalLabel {
    final int sec = (totalMs / 1000).round();
    if (sec < 60) return '$sec 秒';
    final int min = sec ~/ 60;
    if (min < 60) return '$min 分钟';
    return '${min ~/ 60} 小时 ${min % 60} 分';
  }

  factory TrackStats.fromRow(Map<String, dynamic> row) => TrackStats(
        trackKey: row['track_key'] as String,
        title: row['title'] as String,
        artist: row['artist'] as String? ?? '',
        sourceId: row['source_id'] as String? ?? '',
        playCount: row['play_count'] as int? ?? 0,
        totalMs: row['total_ms'] as int? ?? 0,
        lastPlayedAt: row['last_played_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                row['last_played_at'] as int,
              ),
      );
}

/// 单曲收听历史条目（自动收录机制的原始数据）。
class ListenEntry {
  const ListenEntry({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.sourceId,
    required this.playedAt,
    this.durationMs = 0,
  });

  final String trackKey;
  final String title;
  final String artist;
  final String sourceId;
  final DateTime playedAt;
  final int durationMs;

  factory ListenEntry.fromRow(Map<String, dynamic> row) => ListenEntry(
        trackKey: row['track_key'] as String,
        title: row['title'] as String,
        artist: row['artist'] as String? ?? '',
        sourceId: row['source_id'] as String? ?? '',
        playedAt: DateTime.fromMillisecondsSinceEpoch(row['played_at'] as int),
        durationMs: row['duration_ms'] as int? ?? 0,
      );
}

/// 全局收藏的歌曲。
class FavoriteEntry {
  const FavoriteEntry({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.sourceId,
    this.coverUrl,
    this.addedAt,
  });

  final String trackKey;
  final String title;
  final String artist;
  final String sourceId;
  final String? coverUrl;
  final DateTime? addedAt;

  factory FavoriteEntry.fromRow(Map<String, dynamic> row) => FavoriteEntry(
        trackKey: row['track_key'] as String,
        title: row['title'] as String,
        artist: row['artist'] as String? ?? '',
        sourceId: row['source_id'] as String? ?? '',
        coverUrl: row['cover_url'] as String?,
        addedAt: row['added_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
      );
}

/// 歌单排序方式。
enum PlaylistSortMode {
  manual,
  titleAsc,
  titleDesc,
  playCountDesc,
  addedDesc,
}

/// 歌单背景图来源类型。
enum PlaylistBgType {
  none,
  sceneSnapshot,
  sceneVideoFrame,
  gallery,
}

/// 全局歌单。
class Playlist {
  const Playlist({
    this.id,
    required this.name,
    this.bgType = PlaylistBgType.none,
    this.bgPath,
    this.sortMode = PlaylistSortMode.manual,
    this.createdAt,
    this.trackCount = 0,
  });

  final int? id;
  final String name;
  final PlaylistBgType bgType;
  final String? bgPath;
  final PlaylistSortMode sortMode;
  final DateTime? createdAt;
  final int trackCount;

  factory Playlist.fromRow(Map<String, dynamic> row) => Playlist(
        id: row['id'] as int,
        name: row['name'] as String,
        bgType: PlaylistBgType.values[
            (row['bg_type'] as int? ?? 0).clamp(0, PlaylistBgType.values.length - 1)],
        bgPath: row['bg_path'] as String?,
        sortMode: PlaylistSortMode.values[
            (row['sort_mode'] as int? ?? 0).clamp(0, PlaylistSortMode.values.length - 1)],
        createdAt: row['created_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        trackCount: row['track_count'] as int? ?? 0,
      );
}

/// 歌单内一首歌。
class PlaylistTrack {
  const PlaylistTrack({
    required this.playlistId,
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.sourceId,
    this.sortIndex = 0,
  });

  final int playlistId;
  final String trackKey;
  final String title;
  final String artist;
  final String sourceId;
  final int sortIndex;

  factory PlaylistTrack.fromRow(Map<String, dynamic> row) => PlaylistTrack(
        playlistId: row['playlist_id'] as int,
        trackKey: row['track_key'] as String,
        title: row['title'] as String,
        artist: row['artist'] as String? ?? '',
        sourceId: row['source_id'] as String? ?? '',
        sortIndex: row['sort_index'] as int? ?? 0,
      );
}

/// 曲目唯一键构建：title|artist|sourceId。
String trackKeyOf(String title, String artist, String sourceId) =>
    '$title|$artist|$sourceId';

/// 自动收录的归并候选：历史新条目 vs 已收录主条目。
class MergeCandidate {
  const MergeCandidate({required this.source, required this.canonical});

  final ListenEntry source;
  final TrackStats canonical;
}

/// 已解析的可播放链接缓存（重播加速 / 失效自动重匹配）。
///
/// 记录「上次成功解析出的直链 URL + 失效时间」，供再次播放时：
/// - 未过期 → 直接用缓存直链，跳过重新解析（更快、更省流量）；
/// - 已过期 / 无缓存 → 走源重新解析，再失败则按 名称/时长/歌手 聚合搜索自动匹配。
class ResolvedLink {
  const ResolvedLink({
    required this.trackKey,
    required this.url,
    required this.expireAtMs,
    required this.updatedAtMs,
  });

  final String trackKey;

  /// 可直接播放的直链（http(s) URL）。
  final String url;

  /// 失效时间戳（毫秒）。0 表示未知 / 永不过期。
  final int expireAtMs;

  /// 最近一次成功解析时间（毫秒）。
  final int updatedAtMs;

  /// 是否已过期（expireAtMs<=0 视为未过期）。
  bool get isExpired =>
      expireAtMs > 0 &&
      DateTime.now().millisecondsSinceEpoch >= expireAtMs;

  factory ResolvedLink.fromRow(Map<String, dynamic> row) => ResolvedLink(
        trackKey: row['track_key'] as String,
        url: row['url'] as String,
        expireAtMs: row['expire_at'] as int? ?? 0,
        updatedAtMs: row['updated_at'] as int? ?? 0,
      );
}
