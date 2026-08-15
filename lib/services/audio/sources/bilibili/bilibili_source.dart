/// 星璃 · 哔哩哔哩（B站）视频源
///
/// 实现工程既有的 `MusicSource` 抽象，与网易云源同构：
///   - [getTracks] 返回空（曲库不聚合，搜索驱动）；
///   - [search] 按关键词搜视频 → 映射成 Track（占位 uri `bilibili://video/<bvid>`，
///     刻意不以 http 开头，避免 `Track.isRemote` 误判直连）；
///   - [resolveStreamUrl] 懒解析 B站音频流（带 cookie，登录后更高音质）；
///   - [autoMatch] 按「曲名 + 时长」自动匹配：搜相似结果里挑时长最接近的
///     （B站自动播放的默认策略，时长差 > 阈值则放弃）。
///
/// 沙箱安全：全文件只依赖 dart:async / dart:convert 与 http。
library;

import '../../../../models/track.dart';
import '../../../music_sources/music_source.dart';
import 'bilibili_api.dart';

/// 解析播放地址失败。消息为可直接展示给用户的中文。
class BilibiliResolveException implements Exception {
  const BilibiliResolveException(this.message);

  final String message;

  @override
  String toString() => 'BilibiliResolveException: $message';
}

/// 自动匹配的候选。
class BiliMatchCandidate {
  const BiliMatchCandidate({required this.track, required this.delta});

  final Track track;

  /// 与目标时长的绝对差（秒）。
  final int delta;
}

/// 哔哩哔哩视频源。
class BilibiliSource implements MusicSource {
  BilibiliSource(this.api, {bool enabled = true}) : _enabled = enabled;

  static const String kSourceId = 'bilibili';

  final BilibiliApi api;
  final bool _enabled;

  @override
  String get sourceId => kSourceId;

  @override
  bool get enabled => _enabled && api.isLoggedIn;

  /// 曲库聚合入口：B站不参与曲库，返回空。
  @override
  Future<List<Track>> getTracks() async => const <Track>[];

  /// 搜索候选视频。返回 Track 的 uri 是占位符，播放前必须过 [resolveStreamUrl]。
  Future<List<Track>> search(String keyword, {int limit = 20}) async {
    final List<BiliVideoLite> vids =
        await api.searchVideos(keyword, pageSize: limit);
    return vids.map(toTrack).toList(growable: false);
  }

  /// 把 B站视频映射成星璃的 [Track]。
  static Track toTrack(BiliVideoLite v) => Track(
        title: v.title,
        artist: v.author,
        uri: placeholderUri(v.bvid),
        source: TrackSource.stream,
        sourceId: kSourceId,
        coverUrl: v.coverUrl,
        duration: Duration(seconds: v.durationSeconds),
        extras: <String, dynamic>{'bvid': v.bvid},
      );

  /// 占位 uri：不得以 http 开头。
  static String placeholderUri(String bvid) => 'bilibili://video/$bvid';

  /// 从 Track 反解 bvid；拿不到返回 null。
  static String? bvidOf(Track t) {
    final Object? b = t.extras?['bvid'];
    if (b is String && b.isNotEmpty) return b;
    final String u = t.uri;
    if (u.startsWith('bilibili://video/')) {
      final String id = u.substring('bilibili://video/'.length);
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  /// 解析 B站视频的音频流为可直接播放的 http 地址。
  @override
  Future<String> resolveStreamUrl(Track track) async {
    final String? bvid = bvidOf(track);
    if (bvid == null) {
      throw const BilibiliResolveException('缺少 bvid，无法解析 B站播放地址');
    }
    try {
      return await api.resolveAudioUrl(bvid);
    } on BilibiliApiException catch (e) {
      throw BilibiliResolveException(
        e.isAuthFailure ? 'B站登录态已失效，请重新登录' : 'B站播放地址获取失败（${e.code}）',
      );
    }
  }

  /// 解析 B站视频的**画面流**（场景背景用；背景视频默认静音，只听主音乐）。
  ///
  /// [qualityIndex] 透传 [BilibiliApi.resolveVideoUrl]（0=最高/自动）。
  Future<String> resolveVideoUrl(String bvid, {int qualityIndex = 0}) async {
    try {
      return await api.resolveVideoUrl(bvid, qualityIndex: qualityIndex);
    } on BilibiliApiException catch (e) {
      throw BilibiliResolveException(
        e.isAuthFailure ? 'B站登录态已失效，请重新登录' : 'B站视频画面获取失败（${e.code}）',
      );
    }
  }

  /// 自动匹配：按「曲名 + 目标时长」从相似结果里挑时长最接近的候选。
  ///
  /// [targetDuration] 为空时只按搜索相关度（首条）。返回 null = 无合适结果。
  /// 时长差阈值默认 25s 或目标时长的 15%（取较大者）——太离谱的直接放弃，
  /// 避免把「同名但完全不同内容」的视频当成当前曲目自动播。
  Future<BiliMatchCandidate?> autoMatch(
    String title, {
    String? artist,
    Duration? targetDuration,
    int limit = 20,
  }) async {
    if (title.trim().isEmpty) return null;
    final String kw = [title.trim(), if (artist != null && artist.isNotEmpty) artist.trim()]
        .join(' ');
    final List<BiliVideoLite> vids = await api.searchVideos(kw, pageSize: limit);
    if (vids.isEmpty) return null;
    if (targetDuration == null) {
      return BiliMatchCandidate(track: toTrack(vids.first), delta: 0);
    }
    final int targetSecs = targetDuration.inSeconds;
    final int threshold = (targetSecs * 0.15).round().clamp(20, 60);
    BiliMatchCandidate? best;
    for (final BiliVideoLite v in vids) {
      final int delta = (v.durationSeconds - targetSecs).abs();
      if (delta > threshold) continue; // 时长差太大：同名不同内容，跳过
      if (best == null || delta < best.delta) {
        best = BiliMatchCandidate(track: toTrack(v), delta: delta);
      }
    }
    return best;
  }

  @override
  Map<String, String> get playbackHeaders => const <String, String>{
        'User-Agent': kBilibiliUserAgent,
        'Referer': 'https://www.bilibili.com/',
      };

  /// B站音频流 just_audio 无法解码，必须 media_kit（libmpv）。
  @override
  bool get requiresMediaKit => true;
}
