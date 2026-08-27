/// 星璃 · 「听过的歌」自动收录源（cl64-5 / #635）。
///
/// 把播放历史里出现过的网络曲目重建为可播放 [Track]，注入曲库聚合，
/// 实现「听过的歌自动加入曲库」。这些 Track 的 uri 是各源的占位符
/// （如 `netease://song/<id>`），播放时由 [NeteaseSource] 懒解析直链。
///
/// 因此本源复用 `netease` 的 sourceId 与解析能力：注册时持有一份
/// [NeteaseSource] 引用，[resolveStreamUrl] / [playbackHeaders] / [requiresMediaKit]
/// 全部转发给它，避免 StreamResolver 因找不到对应源而回落原生崩溃。
library;

import '../../../models/track.dart';
import '../../../models/track_stats.dart';
import '../../../services/music_sources/music_source.dart';
import '../../stats/track_stats_db.dart';
import './netease/netease_source.dart';

/// 听过的歌源：从 [TrackStatsDb.heardTracks] 重建曲目并入曲库。
class HeardSource implements MusicSource {
  HeardSource(this._netease, this._db);

  /// 复用网易云源做解析转发（占位 uri → 直链）。
  final NeteaseSource _netease;
  final TrackStatsDb _db;

  /// 复用网易云的 sourceId，使 StreamResolver 能按 sourceId 找到解析源。
  @override
  String get sourceId => NeteaseSource.kSourceId;

  /// 总是参与曲库聚合（听过的歌就是曲库的一部分）。
  @override
  bool get enabled => true;

  @override
  Future<List<Track>> getTracks() async {
    final List<ListenEntry> entries = await _db.heardTracks();
    final List<Track> tracks = <Track>[];
    for (final ListenEntry e in entries) {
      final Track? t = e.toTrack();
      if (t != null) tracks.add(t);
    }
    return tracks;
  }

  @override
  Future<String> resolveStreamUrl(Track track) => _netease.resolveStreamUrl(track);

  @override
  Map<String, String> get playbackHeaders => _netease.playbackHeaders;

  @override
  bool get requiresMediaKit => _netease.requiresMediaKit;
}
