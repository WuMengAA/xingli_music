/// ════════════════════════════════════════════════════════════════════════
/// VoiceHub 客户端（校园广播站点歌系统 · Nuxt 4 全栈，合并对接）
///
/// 星璃不再单独实现电台/点歌/排期后端，改调 VoiceHub 开放 API：
///   - GET /api/open/songs.get       点歌列表/搜索（apiKey 认证）
///   - GET /api/open/schedules.get   排期列表（apiKey 认证）
///   - POST /api/songs/request.post  点歌提交（需登录用户 cookie）
///   - GET /api/open/{semesters,playtimes}.get 元数据（可选）
///
/// 认证：开放接口在请求头 `X-API-Key` 传 apiKey；点歌接口走用户登录态
/// （本客户端暂以「配置管理员令牌」方式提交，未配置时明确报错提示登录）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// 一条点歌（VoiceHub songs 表映射，仅取客户端需要的字段）。
class VoiceHubSong {
  const VoiceHubSong({
    required this.id,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.platform = '',
    this.musicId = '',
    this.playCount = 0,
    this.voteCount = 0,
    this.requester = '',
    this.status = '',
  });

  final int id;
  final String title;
  final String artist;
  final String? coverUrl;
  final String platform;
  final String musicId;
  final int playCount;
  final int voteCount;
  final String requester;
  final String status;

  factory VoiceHubSong.fromJson(Map<String, dynamic> j) => VoiceHubSong(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        coverUrl: j['coverUrl'] as String?,
        platform: j['musicPlatform'] as String? ?? '',
        musicId: j['musicId'] as String? ?? '',
        playCount: (j['playCount'] as num?)?.toInt() ?? 0,
        // 真实接口给的是热度/投票数（voteCount/votes 字段），两字段兼容。
        voteCount: (j['voteCount'] as num?)?.toInt() ??
            (j['votes'] as num?)?.toInt() ??
            (j['vote_count'] as num?)?.toInt() ??
            0,
        requester: j['requester'] as String? ??
            (j['requestedBy'] as String? ?? ''),
        status: j['status'] as String? ?? '',
      );
}

/// 一条排期（VoiceHub schedules 表映射）。
class VoiceHubSchedule {
  const VoiceHubSchedule({
    required this.id,
    required this.playDate,
    required this.playTimeId,
    this.songTitle = '',
    this.songArtist = '',
    this.coverUrl,
    this.requester = '',
    this.voteCount = 0,
    this.status = '',
  });

  final int id;
  final String playDate;
  final int playTimeId;
  final String songTitle;
  final String songArtist;
  final String? coverUrl;
  final String requester;
  final int voteCount;
  final String status;

  factory VoiceHubSchedule.fromJson(Map<String, dynamic> j) {
    final dynamic song = j['song'];
    if (song is Map<String, dynamic>) {
      return VoiceHubSchedule(
        id: (j['id'] as num?)?.toInt() ?? 0,
        playDate: j['playDate'] as String? ?? '',
        playTimeId: (j['playTimeId'] as num?)?.toInt() ?? 0,
        songTitle: song['title'] as String? ?? '',
        songArtist: song['artist'] as String? ?? '',
        coverUrl: song['coverUrl'] as String?,
        requester: song['requester'] as String? ?? '',
        voteCount: (song['voteCount'] as num?)?.toInt() ??
            (song['votes'] as num?)?.toInt() ??
            0,
        status: j['status'] as String? ?? '',
      );
    }
    return VoiceHubSchedule(
      id: (j['id'] as num?)?.toInt() ?? 0,
      playDate: j['playDate'] as String? ?? '',
      playTimeId: (j['playTimeId'] as num?)?.toInt() ?? 0,
      songTitle: j['songTitle'] as String? ?? '',
      songArtist: j['songArtist'] as String? ?? '',
      coverUrl: j['coverUrl'] as String?,
      requester: j['requester'] as String? ?? '',
      voteCount: (j['voteCount'] as num?)?.toInt() ??
          (j['votes'] as num?)?.toInt() ??
          0,
      status: j['status'] as String? ?? '',
    );
  }
}

/// VoiceHub 异常。
class VoiceHubException implements Exception {
  const VoiceHubException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// VoiceHub 客户端（无状态，URL + apiKey 由调用方/provider 提供）。
class VoiceHubClient {
  VoiceHubClient({
    required this.baseUrl,
    String? apiKey,
    String? cookie,
    http.Client? client,
  })  : _apiKey = apiKey ?? '',
        _cookie = cookie ?? '',
        _client = client ?? http.Client();

  final String baseUrl;
  final String _apiKey;
  final String _cookie;
  final http.Client _client;

  /// 浏览器 cookie 串（`name=value; name2=value2`）→ Map。
  static Map<String, String> parseCookie(String raw) {
    final Map<String, String> out = <String, String>{};
    for (final String pair in raw.split(';')) {
      final int eq = pair.indexOf('=');
      if (eq <= 0) continue;
      out[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
    }
    return out;
  }

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => <String, String>{
        if (_apiKey.isNotEmpty) 'X-API-Key': _apiKey,
        if (_cookie.isNotEmpty) 'Cookie': _cookie,
        'Content-Type': 'application/json; charset=utf-8',
      };

  /// 拉取点歌列表（open 接口，apiKey 认证）。
  Future<List<VoiceHubSong>> fetchSongs({
    String search = '',
    String semester = '',
    int page = 1,
    int limit = 50,
  }) async {
    final Uri uri = Uri.parse('$_root/api/open/songs.get').replace(
          queryParameters: <String, String>{
            if (search.isNotEmpty) 'search': search,
            if (semester.isNotEmpty) 'semester': semester,
            'page': '$page',
            'limit': '$limit',
          },
        );
    final dynamic data = await _getJson(uri);
    final List<dynamic>? items = data['data'] as List<dynamic>? ??
        (data['items'] as List<dynamic>?);
    return <VoiceHubSong>[
      for (final dynamic e in items ?? const <dynamic>[])
        VoiceHubSong.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// 拉取排期列表（open 接口，apiKey 认证）。
  Future<List<VoiceHubSchedule>> fetchSchedules({
    String semester = '',
    String date = '',
    int page = 1,
    int limit = 50,
  }) async {
    final Uri uri = Uri.parse('$_root/api/open/schedules.get').replace(
          queryParameters: <String, String>{
            if (semester.isNotEmpty) 'semester': semester,
            if (date.isNotEmpty) 'date': date,
            'page': '$page',
            'limit': '$limit',
          },
        );
    final dynamic data = await _getJson(uri);
    final List<dynamic>? items = data['data'] as List<dynamic>? ??
        (data['items'] as List<dynamic>?);
    return <VoiceHubSchedule>[
      for (final dynamic e in items ?? const <dynamic>[])
        VoiceHubSchedule.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// 点歌提交（需 VoiceHub 用户登录态；未提供会话 cookie 时服务端 401）。
  /// 参数尽量对齐 VoiceHub `songRequestBodySchema`。
  Future<bool> submitSong({
    required String title,
    required String artist,
    String? coverUrl,
    String? musicPlatform,
    String? musicId,
    Map<String, String>? cookies,
  }) async {
    // 优先客户端配置的 cookie（_headers 已含）；若显式传入 cookies 则覆盖
    //（浏览器粘贴的完整串 vs 手拆 Map 两种入口都支持）。
    final Map<String, String> headers = <String, String>{
      ..._headers,
      if (cookies != null && cookies.isNotEmpty)
        'Cookie': cookies.entries
            .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
            .join('; '),
    };
    final http.Response resp = await _client
        .post(
          Uri.parse('$_root/api/songs/request.post'),
          headers: headers,
          body: jsonEncode(<String, dynamic>{
            'title': title,
            'artist': artist,
            if (coverUrl != null && coverUrl.isNotEmpty) 'cover': coverUrl,
            if (musicPlatform != null && musicPlatform.isNotEmpty)
              'musicPlatform': musicPlatform,
            if (musicId != null && musicId.isNotEmpty) 'musicId': musicId,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200 || resp.statusCode == 201) return true;
    if (resp.statusCode == 401) {
      throw const VoiceHubException('点歌需要 VoiceHub 登录（当前未登录）');
    }
    throw VoiceHubException('点歌失败（HTTP ${resp.statusCode}）');
  }

  /// GET JSON 公共路径：401 → 明确报错；其余非 200 → 通用异常。
  Future<dynamic> _getJson(Uri uri) async {
    final http.Response resp = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401) {
      throw const VoiceHubException('VoiceHub API 认证失败（API Key 无效或未配置）');
    }
    if (resp.statusCode != 200) {
      throw VoiceHubException('VoiceHub 请求失败（HTTP ${resp.statusCode}）');
    }
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }
}