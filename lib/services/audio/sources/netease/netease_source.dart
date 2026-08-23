/// 星璃 · 网易云音源（I 域 · P1-4 / P1-5）
///
/// 实现工程既有的 `MusicSource` 抽象（lib/services/music_sources/music_source.dart），
/// 不另造接口 —— 这样将来接进 `activeSourcesProvider` 时零适配。
///
/// 与其它源的关键差异：网易云播放 URL **带签名且会过期**，因此
/// [getTracks] 阶段只填 `netease://song/<id>` 占位符（刻意不以 http 开头，
/// 避免 `Track.isRemote` 误判后被直接送进 setUrl），真正的地址由
/// [resolveStreamUrl] 懒解析（见 docs/方案_音源扩充.md §4.3(3)(4)）。
///
/// 沙箱安全：全文件只依赖 dart:async / dart:convert 与 http，
/// 不使用 dart:io Process、不使用 dart:mirrors。
library;

import '../../../../models/track.dart';
import '../../../music_sources/music_source.dart';
import 'netease_api.dart';

/// 播放地址不可用的原因（§4.3(4)：三类失败必须区分并给人话提示）。
enum NeteaseFailureReason {
  /// 未登录 / 登录态失效 / 触发风控 —— 需要重新登录。
  auth,

  /// 无版权、已下架、账号地区不可播。
  noCopyright,

  /// 仅试听片段，需要会员权益。
  vipRequired,

  /// 网络或接口异常。
  network,
}

/// 解析播放地址失败。消息为可直接展示给用户的中文。
class NeteaseResolveException implements Exception {
  const NeteaseResolveException(this.reason, this.message);

  final NeteaseFailureReason reason;
  final String message;

  @override
  String toString() => 'NeteaseResolveException(${reason.name}): $message';
}

/// 网易云音源。
class NeteaseSource implements MusicSource {
  NeteaseSource(this.api, {bool enabled = true}) : _enabled = enabled;

  /// 源 id，供 `StreamResolver` 反查（§4.3(3)）。
  static const String kSourceId = 'netease';

  /// 播放 URL 的保守有效期。网易云不返回过期时间，社区实测普通链约 24h、
  /// 会员链约 1h（§4.7.6 风险 3，待实测）；这里取远小于两者的保守值，
  /// 宁可多解析一次，也不要播到一半 403。
  static const Duration kUrlTtl = Duration(minutes: 20);

  final NeteaseApi api;
  final bool _enabled;

  @override
  String get sourceId => kSourceId;

  @override
  bool get enabled => _enabled && api.isLoggedIn;

  /// 曲库聚合入口。
  ///
  /// 当前阶段**刻意返回空列表**：网易云曲库走「歌单 → 分页」而非全量拉取
  /// （§3.4），且本次交付不接入主播放链路。歌单能力后续以
  /// `PagedMusicSource` 形式补充。
  @override
  Future<List<Track>> getTracks() async => const <Track>[];

  /// 搜索候选曲目。返回的 Track 的 uri 是占位符，播放前必须过 [resolveStreamUrl]。
  Future<List<Track>> search(String keyword, {int limit = 30, int offset = 0}) async {
    final List<SongLite> songs =
        await api.searchSongs(keyword, limit: limit, offset: offset);
    return songs.map(toTrack).toList(growable: false);
  }

  /// 把一首网易云歌曲映射成星璃的 [Track]。
  static Track toTrack(SongLite song) => Track(
        title: song.name,
        artist: song.artist,
        uri: placeholderUri(song.id),
        source: TrackSource.stream,
        sourceId: kSourceId,
        coverUrl: song.coverUrl,
        album: song.album,
        duration: song.duration,
        extras: <String, dynamic>{
          'songId': song.id,
          'fee': song.fee,
          if (song.reason != null) 'reason': song.reason!,
        },
      );

  /// 每日推荐（需登录）：约 30 首，每项带推荐理由。
  Future<List<Track>> recommend() async =>
      (await api.recommendSongs()).map(toTrack).toList(growable: false);

  /// 私人漫游（需登录）：一批曲目，可循环刷新。
  Future<List<Track>> roam() async =>
      (await api.roamSongs()).map(toTrack).toList(growable: false);

  /// 占位 uri：不得以 http 开头（§4.3(3)）。
  static String placeholderUri(int songId) => 'netease://song/$songId';

  /// 从 Track 反解出 songId；拿不到返回 null。
  static int? songIdOf(Track track) {
    final Object? raw = track.extras?['songId'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    final Match? m = RegExp(r'^netease://song/(\d+)$').firstMatch(track.uri);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 解析出可直接播放的 HTTPS 地址。
  ///
  /// 失败一律抛 [NeteaseResolveException]，由上层决定是提示还是跳下一首。
  Future<String> fetchPlayableUrl(int songId, {String level = 'standard'}) async {
    final List<SongUrl> urls;
    try {
      urls = await api.getSongUrls(<int>[songId], level: level);
    } on NeteaseApiException catch (e) {
      throw NeteaseResolveException(
        e.isAuthFailure ? NeteaseFailureReason.auth : NeteaseFailureReason.network,
        e.isAuthFailure ? '网易云登录已失效，请重新登录' : '网易云接口暂时不可用，请稍后重试',
      );
    }

    if (urls.isEmpty) {
      throw const NeteaseResolveException(
        NeteaseFailureReason.noCopyright,
        '该歌曲在你的账号下无法播放',
      );
    }

    final SongUrl first = urls.first;
    if (!first.playable) {
      throw NeteaseResolveException(
        first.fee > 0 ? NeteaseFailureReason.vipRequired : NeteaseFailureReason.noCopyright,
        first.fee > 0 ? '该歌曲需要网易云会员权益' : '该歌曲在你的账号下无法播放',
      );
    }
    if (first.isTrialOnly) {
      throw NeteaseResolveException(
        NeteaseFailureReason.vipRequired,
        '该歌曲仅可试听 ${first.trialSeconds} 秒，需要网易云会员',
      );
    }
    return first.url!;
  }

  @override
  Future<String> resolveStreamUrl(Track track) async {
    final int? songId = songIdOf(track);
    if (songId == null) {
      throw const NeteaseResolveException(
        NeteaseFailureReason.noCopyright,
        '曲目缺少网易云 id，无法解析播放地址',
      );
    }
    return fetchPlayableUrl(songId);
  }

  /// 解析后应写进 `Track.extras` 的字段（供 StreamResolver 判缓存）。
  static Map<String, dynamic> playbackExtras(Track track) => <String, dynamic>{
        ...?track.extras,
        'expireAt': DateTime.now().add(kUrlTtl).millisecondsSinceEpoch,
        'needHeaders': true,
      };

  /// 播放 CDN 必须携带的请求头（§3.3）。
  @override
  Map<String, String> get playbackHeaders => api.playbackHeaders;

  /// 网易云 CDN 流带签名且格式特殊，just_audio 无法解码，必须 media_kit。
  @override
  bool get requiresMediaKit => true;
}
