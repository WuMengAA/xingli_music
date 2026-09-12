/// ════════════════════════════════════════════════════════════════════════
/// VoiceHub 客户端（校园广播站点歌系统 · Nuxt 4 全栈）
///
/// 端点与认证方式（逐条对齐 `D:\Stellara\Music\_voicehub_ref\server`）：
///
/// | 能力         | 方法 | 路径                            | 认证        |
/// |--------------|------|---------------------------------|-------------|
/// | 点歌列表     | GET  | `/api/open/songs`               | X-API-Key   |
/// | 排期列表     | GET  | `/api/open/schedules`           | X-API-Key   |
/// | 提交点歌     | POST | `/api/open/songs/request`       | X-API-Key   |
/// | 我的投稿     | GET  | `/api/songs?scope=mine`         | Cookie      |
/// | 投票/取消    | POST | `/api/songs/vote`               | Cookie      |
/// | 撤回投稿     | POST | `/api/songs/withdraw`           | Cookie      |
/// | 投稿额度     | GET  | `/api/songs/submission-status`  | Cookie      |
/// | 登录         | POST | `/api/auth/login`               | 无          |
///
/// 认证分工（`server/middleware/api-auth.ts`）：`/api/open/*` 由中间件只校验
/// `X-API-Key`，**不要求 Cookie**；提交点歌虽在 `/api/open/` 下，但服务端用
/// API Key 归属的用户身份落库（`request.post.ts` 里的 `apiKey.createdByUserId`），
/// 因此同样不需要 Cookie。投票/我的投稿/额度走 `/api/songs/*`，依赖登录会话
/// Cookie（`auth-token`），未登录时服务端返回 401。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'voicehub_models.dart';

/// VoiceHub 客户端（无状态，URL + apiKey + cookie 由调用方/provider 注入）。
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

  /// 会话判定的**唯一来源**：Cookie 里必须含 `auth-token`。
  ///
  /// 会话凭据只有这一个——登录响应只写 `Set-Cookie: auth-token=<jwt>`
  /// （`server/api/auth/login.post.ts:273`），响应体里没有 token。手粘的其他
  /// cookie（如 `binding-token`）不算已登录，否则「我的投稿」/ 投票这些私有
  /// 端点必然 401，用户会看到「显示已登录、点了才失败」。
  ///
  /// [VoiceHubConfig.loggedIn] 与本类的 [hasSession] 都走这里，杜绝两套判定。
  static bool hasSessionCookie(String raw) =>
      parseCookie(raw).containsKey('auth-token');

  /// 是否持有登录会话（判定见 [hasSessionCookie]）。
  bool get hasSession => hasSessionCookie(_cookie);

  Map<String, String> _headers({bool withCookie = true}) =>
      <String, String>{
        if (_apiKey.isNotEmpty) 'X-API-Key': _apiKey,
        if (withCookie && _cookie.isNotEmpty) 'Cookie': _cookie,
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      };

  // ── 点歌列表 ────────────────────────────────────────────────────────────

  /// GET `/api/open/songs`（apiKey 认证）。
  ///
  /// 返回 `{songs, pagination}`；解析走 [VoiceHubJson.pickList]，
  /// `data.data` 是 Map（`{songs, pagination}`）或数组都能吃下。
  Future<VoiceHubSongPage> fetchSongs({
    String search = '',
    String semester = '',
    int page = 1,
    int limit = 20,
    String sortBy = 'createdAt',
    String sortOrder = 'desc',
  }) async {
    final Uri uri = Uri.parse('$_root/api/open/songs').replace(
          queryParameters: <String, String>{
            if (search.isNotEmpty) 'search': search,
            if (semester.isNotEmpty) 'semester': semester,
            'page': '$page',
            'limit': '$limit',
            if (sortBy.isNotEmpty) 'sortBy': sortBy,
            if (sortOrder.isNotEmpty) 'sortOrder': sortOrder,
          },
        );
    final dynamic decoded = await _getJson(uri);
    return VoiceHubSongPage(
      songs: _songList(decoded, 'songs'),
      pagination: VoiceHubJson.pagination(decoded, page, limit),
    );
  }

  // ── 排期列表 ────────────────────────────────────────────────────────────

  /// GET `/api/open/schedules`（apiKey 认证）。
  Future<VoiceHubSchedulePage> fetchSchedules({
    String semester = '',
    String date = '',
    int page = 1,
    int limit = 20,
  }) async {
    final Uri uri = Uri.parse('$_root/api/open/schedules').replace(
          queryParameters: <String, String>{
            if (semester.isNotEmpty) 'semester': semester,
            if (date.isNotEmpty) 'date': date,
            'page': '$page',
            'limit': '$limit',
          },
        );
    final dynamic decoded = await _getJson(uri);
    return VoiceHubSchedulePage(
      schedules: _scheduleList(decoded, 'schedules'),
      pagination: VoiceHubJson.pagination(decoded, page, limit),
    );
  }

  // ── 我的投稿 ────────────────────────────────────────────────────────────

  /// GET `/api/songs?scope=mine`（Cookie 认证）。
  ///
  /// 该端点无分页信封，只给 `data.songs` + `data.total`。
  Future<List<VoiceHubSong>> fetchMySongs({String semester = ''}) async {
    final Uri uri = Uri.parse('$_root/api/songs').replace(
          queryParameters: <String, String>{
            'scope': 'mine',
            if (semester.isNotEmpty) 'semester': semester,
          },
        );
    final dynamic decoded = await _getJson(uri, withCookie: true);
    return _songList(decoded, 'songs');
  }

  // ── 提交点歌 ────────────────────────────────────────────────────────────

  /// POST `/api/open/songs/request`（**只需 apiKey，不需要 Cookie**）。
  ///
  /// body 字段名取 `request.post.ts` 的 `ALLOWED_FIELDS` 白名单 ∩
  /// `songRequestService.ts` 的 zod `songRequestBodySchema`：
  /// title / artist / cover / musicPlatform / musicId / bilibiliCid /
  /// bilibiliPage / playUrl / submissionNote / submissionNotePublic /
  /// preferredPlayTimeId / cardCode / collaborators。
  ///
  /// 注意：白名单**不含** `durationSeconds`，下发会被过滤（详见下方 body）。
  ///
  /// B 站分 P：不要试图把 `BVxx:cid:page` 整串塞进 [musicId]——服务端在
  /// `songRequestService.ts:452-465` 会以 `musicId.split(':')[0]` 重建 id，
  /// 只有同时传了 [bilibiliCid] 才会把 `:cid(:page)` 拼回去。分 P 信息必须
  /// 走 [bilibiliCid] / [bilibiliPage] 两个独立字段。
  ///
  /// [collaborators] 是**数值用户 id**（不是姓名）：服务端
  /// `songRequestService.ts:498-501` 做 `Number(id)` 后按 `users.id` 校验，
  /// 传姓名会得到 NaN 并被静默丢弃。
  ///
  /// 返回新歌曲 id（后端直接返回新建的 song 行；拿不到时回退 0）。
  Future<int> submitSong({
    required String title,
    required String artist,
    String? cover,
    String? musicPlatform,
    String? musicId,
    String? bilibiliCid,
    String? bilibiliPage,
    String? playUrl,
    String? submissionNote,
    bool submissionNotePublic = false,
    int? preferredPlayTimeId,
    String? cardCode,
    List<int>? collaborators,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'title': title,
      'artist': artist,
      if (cover != null && cover.isNotEmpty) 'cover': cover,
      if (musicPlatform != null && musicPlatform.isNotEmpty)
        'musicPlatform': musicPlatform,
      if (musicId != null && musicId.isNotEmpty) 'musicId': musicId,
      if (bilibiliCid != null && bilibiliCid.isNotEmpty)
        'bilibiliCid': bilibiliCid,
      if (bilibiliPage != null && bilibiliPage.isNotEmpty)
        'bilibiliPage': bilibiliPage,
      if (playUrl != null && playUrl.isNotEmpty) 'playUrl': playUrl,
      // 不下发 durationSeconds：open 端点 `request.post.ts` 的 ALLOWED_FIELDS
      // 不含该字段，进入 service 前就被剥掉，发了也收不到（读取侧仍保留，
      // songs 端点返回时长用于展示）。
      if (submissionNote != null && submissionNote.isNotEmpty)
        'submissionNote': submissionNote,
      'submissionNotePublic': submissionNotePublic,
      if (preferredPlayTimeId != null)
        'preferredPlayTimeId': preferredPlayTimeId,
      if (cardCode != null && cardCode.isNotEmpty) 'cardCode': cardCode,
      // 数值用户 id 列表（不是姓名；传姓名会被 Number() 转 NaN 后静默丢弃）。
      if (collaborators != null && collaborators.isNotEmpty)
        'collaborators': collaborators,
    };
    final dynamic decoded = await _postJson(
      Uri.parse('$_root/api/open/songs/request'),
      body,
      withCookie: false,
    );
    // 后端 `requestSongForUser` 直接返回新建的 song 行（也可能包在 data 里）。
    final Map<String, dynamic> top = VoiceHubJson.map(decoded);
    return VoiceHubJson.intOrNull(VoiceHubJson.map(top['data'])['id']) ??
        VoiceHubJson.intOrNull(top['id']) ??
        0;
  }

  // ── 投票 / 取消投票 ─────────────────────────────────────────────────────

  /// POST `/api/songs/vote`（Cookie 认证）。
  ///
  /// body 为 `{songId, unvote}`——私有端点只认 `songId`，
  /// 与 open 端点的 `id` 命名不同，别混用。
  /// 返回服务端回算的投票数（拿不到时回退 null，由调用方做乐观 ±1）。
  Future<int?> vote(int songId, {bool unvote = false}) async {
    final dynamic decoded = await _postJson(
      Uri.parse('$_root/api/songs/vote'),
      <String, dynamic>{'songId': songId, 'unvote': unvote},
      withCookie: true,
    );
    final Map<String, dynamic> top = VoiceHubJson.map(decoded);
    return VoiceHubJson.intOrNull(VoiceHubJson.map(top['song'])['voteCount']) ??
        VoiceHubJson.intOrNull(VoiceHubJson.map(top['data'])['voteCount']);
  }

  // ── 撤回投稿 ────────────────────────────────────────────────────────────

  /// POST `/api/songs/withdraw`（Cookie 认证）。
  ///
  /// 主投稿人 = 删除歌曲；联合投稿人 = 退出联合投稿（后端自行判断）。
  Future<void> withdraw(int songId) async {
    await _postJson(
      Uri.parse('$_root/api/songs/withdraw'),
      <String, dynamic>{'songId': songId},
      withCookie: true,
    );
  }

  // ── 投稿额度 ────────────────────────────────────────────────────────────

  /// GET `/api/songs/submission-status`（Cookie 认证）。
  Future<VoiceHubSubmissionStatus> fetchSubmissionStatus() async {
    final dynamic decoded = await _getJson(
      Uri.parse('$_root/api/songs/submission-status'),
      withCookie: true,
    );
    // 该端点直接把状态字段平铺在顶层，也可能套一层 `data`。
    final Map<String, dynamic> top = VoiceHubJson.map(decoded);
    final Object? payload = top.containsKey('data') ? top['data'] : decoded;
    return VoiceHubSubmissionStatus.fromJson(payload);
  }

  // ── 登录 ────────────────────────────────────────────────────────────────

  /// POST `/api/auth/login`：拿用户名密码换会话 Cookie。
  ///
  /// 后端只把 JWT 写在 `Set-Cookie: auth-token=...`（httpOnly）里，响应体
  /// 只有 `{success, user}`，所以必须读响应头。返回可直接存进配置的
  /// cookie 串（形如 `auth-token=<jwt>`）；拿不到时返回空串。
  ///
  /// 站点开启图形验证码时传 [captchaId] / [captchaInput]。
  Future<String> login(
    String username,
    String password, {
    String? captchaId,
    String? captchaInput,
  }) async {
    final http.Response resp = await _client
        .post(
          Uri.parse('$_root/api/auth/login'),
          headers: _headers(withCookie: false),
          body: jsonEncode(<String, dynamic>{
            'username': username,
            'password': password,
            if (captchaId != null && captchaId.isNotEmpty)
              'captchaId': captchaId,
            if (captchaInput != null && captchaInput.isNotEmpty)
              'captchaInput': captchaInput,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const VoiceHubException('用户名或密码错误');
    }
    if (resp.statusCode == 423) {
      throw const VoiceHubException('账号或 IP 已被临时锁定，请稍后再试');
    }
    if (resp.statusCode != 200) {
      throw VoiceHubException(_errorMessage(resp) ?? '登录失败（HTTP ${resp.statusCode}）');
    }
    final String? raw = resp.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return '';
    // 只取 auth-token：`Set-Cookie` 里可能还夹着被删除的其他 cookie。
    for (final String part in raw.split(RegExp(r',(?=\s*[A-Za-z0-9_\-\.]+=)'))) {
      final String head = part.split(';').first.trim();
      final int eq = head.indexOf('=');
      if (eq <= 0) continue;
      if (head.substring(0, eq).trim() == 'auth-token') return head;
    }
    return '';
  }

  // ── 底层 ────────────────────────────────────────────────────────────────

  List<VoiceHubSong> _songList(dynamic decoded, String key) => <VoiceHubSong>[
        for (final dynamic e in VoiceHubJson.pickList(decoded, key))
          VoiceHubSong.fromJson(e),
      ];

  List<VoiceHubSchedule> _scheduleList(dynamic decoded, String key) =>
      <VoiceHubSchedule>[
        for (final dynamic e in VoiceHubJson.pickList(decoded, key))
          VoiceHubSchedule.fromJson(e),
      ];

  /// GET JSON：401/403 → 明确报错；其余非 200 → 通用异常。
  Future<dynamic> _getJson(Uri uri, {bool withCookie = false}) async {
    final http.Response resp = await _client
        .get(uri, headers: _headers(withCookie: withCookie))
        .timeout(const Duration(seconds: 12));
    _ensureOk(resp, uri);
    if (resp.bodyBytes.isEmpty) return <String, dynamic>{};
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  /// POST JSON：返回解码后的响应体（可能为空 Map）。
  Future<dynamic> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    bool withCookie = false,
  }) async {
    final http.Response resp = await _client
        .post(
          uri,
          headers: _headers(withCookie: withCookie),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    _ensureOk(resp, uri);
    if (resp.bodyBytes.isEmpty) return <String, dynamic>{};
    final dynamic decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    return decoded;
  }

  /// 401 的两类成因（按请求路径区分，见 [unauthorizedMessage]）。
  static const String kUnauthorizedApiKey =
      'API Key 无效或未配置，请到设置里检查站点配置';
  static const String kUnauthorizedSession = '会话已失效，请重新登录';

  /// 是否为开放端点（`/api/open/*`）。
  ///
  /// 开放端点只认 `X-API-Key`（`server/middleware/api-auth.ts:62-69`），
  /// 401 说明 Key 有问题；其余端点靠登录会话（Cookie 里的 `auth-token`），
  /// 401 说明会话过期。
  static bool isOpenApi(Uri uri) => uri.path.startsWith('/api/open/');

  /// 401 文案：按路径分类，避免把「Key 配错」和「登录过期」混成一句话。
  static String unauthorizedMessage(Uri uri) =>
      isOpenApi(uri) ? kUnauthorizedApiKey : kUnauthorizedSession;

  /// 非 2xx → 抛 [VoiceHubException]。
  ///
  /// 401 走 [unauthorizedMessage] 按路径分类；403/其它优先透传服务端
  /// `message`（如「你已经为这首歌投过票了」）。
  void _ensureOk(http.Response resp, Uri uri) {
    if (resp.statusCode == 401) {
      throw VoiceHubException(unauthorizedMessage(uri));
    }
    if (resp.statusCode == 403) {
      throw VoiceHubException(
          _errorMessage(resp) ?? 'VoiceHub 拒绝访问（权限不足，HTTP 403）');
    }
    if (resp.statusCode == 404) {
      throw const VoiceHubException('VoiceHub 接口不存在（HTTP 404）');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw VoiceHubException(
          _errorMessage(resp) ?? 'VoiceHub 请求失败（HTTP ${resp.statusCode}）');
    }
  }

  /// 从错误响应体里挑一句人话（`{message}` / `{statusMessage}` / `{error}`）。
  String? _errorMessage(http.Response resp) {
    if (resp.body.isEmpty) return null;
    try {
      final dynamic decoded = jsonDecode(resp.body);
      final Map<String, dynamic> j = VoiceHubJson.map(decoded);
      for (final String k in <String>['message', 'statusMessage', 'error']) {
        final String? s = VoiceHubJson.strOrNull(j[k]);
        if (s != null) return s;
      }
    } catch (_) {
      // 非 JSON 错误体：忽略，回退到状态码文案。
    }
    return null;
  }
}
