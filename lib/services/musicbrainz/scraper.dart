import 'dart:convert';

import 'package:http/http.dart' as http;

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
  static const String _ua = 'xingli-music/0.26.8 (local music player)';
  static const Duration throttle = Duration(milliseconds: 1300);

  final http.Client _client;
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

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

    // 节流：距上次调用不足 1.3s 则等待补齐。
    final DateTime now = DateTime.now();
    final int waitMs = throttle.inMilliseconds -
        now.difference(_lastCall).inMilliseconds;
    if (waitMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
    _lastCall = DateTime.now();

    final http.Response res = await _client.get(
      uri,
      headers: <String, String>{'User-Agent': _ua, 'Accept': 'application/json'},
    );
    if (res.statusCode == 429) {
      throw const MusicBrainzException('请求过于频繁（429），请稍等几秒再试');
    }
    if (res.statusCode == 400) {
      throw const MusicBrainzException('查询参数非法（400）');
    }
    if (res.statusCode != 200) {
      throw MusicBrainzException('MusicBrainz 返回 ${res.statusCode}');
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