import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/app_version.dart' show AppVersion;
import '../log_service.dart';

/// MusicBrainz 录音命中结果。
class ScrapeHit {
  const ScrapeHit({
    required this.title,
    required this.artist,
    this.album,
    this.releaseId,
    this.durationMs,
    this.recordingId,
  });

  final String title;
  final String artist;
  final String? album;
  final String? releaseId;
  final int? durationMs;
  final String? recordingId;

  /// coverartarchive 封面缩略图（release 维度可能有/没有图）。
  String? get coverUrl =>
      releaseId == null ? null : 'https://coverartarchive.org/release/$releaseId/front-250';
}

/// MusicBrainz 刮削器（T12）：按 标题 + 艺术家 查询官方录音元数据。
///
/// 注意 MusicBrainz 服务条款要求：请求必须带可识别 UA，且每秒 ≤1 个请求，
/// 故 [search] 内部自带 ~1.3s 节流（同一实例连续调用）。
class MusicBrainzScraper {
  MusicBrainzScraper({http.Client? client}) : _client = client ?? http.Client();

  static const String apiBase = 'https://musicbrainz.org/ws/2/recording';

  /// MusicBrainz 服务条款要求 UA 必须「可识别 + 带联系方式」，格式为
  /// `<应用名>/<版本> ( <联系方式> )`。**缺少联系方式的 UA 会被其 WAF 直接
  /// 403 拒绝**（这也是刮削器报 403 的主因），故这里带上项目主页做联系入口。
  static final String _ua =
      'XingliMusic/${AppVersion.display} ( https://github.com/WuMengAA/xingli_music )';

  /// 节流间隔。服务条款写的是「每秒 ≤1 个请求」，但 2026-09-13 实测：本机
  /// **间隔 3s 连发两次依然会吃到 503**（匿名搜索端点比条款更严），故取 2s
  /// 并配合 [_getWithRetry] 的退避重试，既守规矩又不至于太慢。
  static const Duration throttle = Duration(seconds: 2);

  /// 单次请求超时（MusicBrainz 偶发慢响应，避免 UI 一直转圈）。
  static const Duration timeout = Duration(seconds: 20);

  /// ⚠️ 节流状态**必须跨实例共享**：刮削页每次进来都 `new` 一个 scraper，
  /// 实例级节流等于没有节流，连续刮削会直接把 MusicBrainz 打到限流。
  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _gate = Future<void>.value();

  final http.Client _client;

  /// 全局串行化的 ≥1.3s 节流闸门（服务条款：每秒 ≤1 个请求）。
  static Future<void> _throttle() async {
    final Future<void> prev = _gate;
    final Completer<void> done = Completer<void>();
    _gate = done.future;
    await prev;
    final int waitMs = throttle.inMilliseconds -
        DateTime.now().difference(_lastCall).inMilliseconds;
    if (waitMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
    _lastCall = DateTime.now();
    done.complete();
  }

  /// 限流 / 风控都是**瞬时**的，退避重试一次比直接报错给用户体验好得多。
  static bool _retryable(int code) =>
      code == 429 || code == 503 || code == 403;

  /// 从 MusicBrainz 的错误 JSON 体里取出服务端原话（如
  /// `{"error":"The MusicBrainz web server is currently busy..."}`）。
  static String _serverHint(http.Response res) {
    try {
      final dynamic body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        final Object? err = body['error'] ?? body['message'];
        if (err is String && err.trim().isNotEmpty) return '：${err.trim()}';
      }
    } catch (_) {
      // 非 JSON（如 WAF 的 HTML 拦截页）→ 不给提示，只报状态码。
    }
    return '';
  }

  Future<http.Response> _get(Uri uri) => _client
      .get(uri, headers: <String, String>{'User-Agent': _ua, 'Accept': 'application/json'})
      .timeout(timeout);

  Future<http.Response> _getWithRetry(Uri uri) async {
    const List<Duration> backoff = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 6),
    ];
    http.Response res = await _get(uri);
    for (int i = 0; i < backoff.length && _retryable(res.statusCode); i++) {
      LogService.instance.w(
        'scraper',
        'MusicBrainz ${res.statusCode}，${backoff[i].inSeconds}s 后重试（第 ${i + 1} 次）',
      );
      await Future<void>.delayed(backoff[i]);
      res = await _get(uri);
    }
    return res;
  }

  /// 查询录音；[title] 必填，[artist] 可选。失败抛异常（网络/限流）。
  Future<List<ScrapeHit>> search({
    required String title,
    String? artist,
    int limit = 8,
  }) async {
    final String q = (StringBuffer()
        ..write('recording:"${_esc(title)}"')
        ..write(artist != null && artist.trim().isNotEmpty
            ? ' AND artist:"${_esc(artist)}"'
            : ''))
    .toString();

    final Uri uri = Uri.parse(
      '$apiBase?fmt=json&limit=$limit&query=${Uri.encodeQueryComponent(q)}',
    );

    await _throttle();

    final http.Response res = await _getWithRetry(uri);
    if (res.statusCode == 429) {
      throw const MusicBrainzException('请求过于频繁（429），请稍等几秒再试');
    }
    if (res.statusCode == 400) {
      throw const MusicBrainzException('查询参数非法（400）');
    }
    if (res.statusCode == 403) {
      throw MusicBrainzException(
        'MusicBrainz 拒绝访问（403）。已携带合规 UA 重试仍被拒，'
        '通常是网络出口被其风控拦截，请稍后再试或更换网络${_serverHint(res)}',
      );
    }
    if (res.statusCode == 503) {
      throw MusicBrainzException(
        'MusicBrainz 服务繁忙（503），请稍等几秒再试${_serverHint(res)}',
      );
    }
    if (res.statusCode != 200) {
      throw MusicBrainzException(
        'MusicBrainz 返回 ${res.statusCode}${_serverHint(res)}',
      );
    }
    final dynamic body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return <ScrapeHit>[];
    final List<dynamic> recordings = body['recordings'] as List<dynamic>? ?? <dynamic>[];
    final List<ScrapeHit> out = <ScrapeHit>[];
    for (final dynamic r in recordings) {
      if (r is! Map<String, dynamic>) continue;
      final String titleV = r['title'] as String? ?? '';
      if (titleV.isEmpty) continue;
      // 取首个 artist-credit
      final List<dynamic> credit = r['artist-credit'] as List<dynamic>? ?? <dynamic>[];
      String artistV = '';
      final StringBuffer sb = StringBuffer();
      for (final dynamic c in credit) {
        if (c is Map<String, dynamic>) {
          final Map<String, dynamic>? art = c['artist'] as Map<String, dynamic>?;
          if (art != null) sb.write(art['name'] ?? '');
          final String? join = c['joinphrase'] as String?;
          if (join != null) sb.write(join);
        }
      }
      artistV = sb.toString().trim();
      // 首 release（专辑）
      final List<dynamic> releases =
          r['releases'] as List<dynamic>? ?? <dynamic>[];
      String? albumV;
      String? releaseId;
      if (releases.isNotEmpty &&
          releases.first is Map<String, dynamic>) {
        final Map<String, dynamic> rel =
            releases.first as Map<String, dynamic>;
        albumV = rel['title'] as String?;
        releaseId = rel['id'] as String?;
      }
      out.add(ScrapeHit(
        title: titleV,
        artist: artistV,
        album: albumV,
        releaseId: releaseId,
        durationMs: r['length'] as int?,
        recordingId: r['id'] as String?,
      ));
    }
    return out;
  }

  /// 标题/艺术家口语化转义：去掉可能破坏 query 语法字符。
  static String _esc(String s) =>
      s.replaceAll('"', '').replaceAll(':', '').trim();
}

class MusicBrainzException implements Exception {
  const MusicBrainzException(this.message);
  final String message;

  @override
  String toString() => message;
}