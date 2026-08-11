/// 星璃 · 网易云 weapi HTTP 客户端（I 域 · P1-1）
///
/// 只做「发请求 / 解 JSON / 管 cookie」三件事，不碰 Track、不碰 Riverpod、
/// 不碰落盘 —— 凭证加密由 `SecureBox` 负责，曲目映射由 `NeteaseSource` 负责。
///
/// 遵循 docs/方案_音源扩充.md §4.3(2) 的客户端约定：
///   - 必带 `Referer: https://music.163.com/` 与桌面浏览器 UA；
///   - 全局串行节流（最小间隔 300ms），这是反爬第一道防线；
///   - 单请求 10s 超时；
///   - **禁止**打印 cookie / 请求头 / 响应体原文（§4.5 日志脱敏）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'netease_crypto.dart';

/// weapi 站点根地址。
const String kNeteaseBase = 'https://music.163.com';

/// 播放 CDN 与接口共用的桌面端 UA（§4.7.6 风险 2/6：UA 异常会触发风控）。
const String kNeteaseUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// 网易云接口返回的业务错误（HTTP 200 但 code != 200 也走这里）。
class NeteaseApiException implements Exception {
  const NeteaseApiException(this.code, this.message);

  /// 网易云业务错误码；-1 表示传输层/解析层失败。
  final int code;
  final String message;

  /// 常见的登录失效码：301 未登录、-460 风控（cheating）。
  bool get isAuthFailure => code == 301 || code == -460 || code == 8810;

  @override
  String toString() => 'NeteaseApiException($code): $message';
}

// ════════════════════════════════════════════════════════════════
// 数据模型（纯 Dart，无 Flutter 依赖，便于单测）
// ════════════════════════════════════════════════════════════════

/// 搜索/详情返回的轻量歌曲信息。
class SongLite {
  const SongLite({
    required this.id,
    required this.name,
    required this.artist,
    this.album,
    this.coverUrl,
    this.duration,
    this.fee = 0,
  });

  final int id;
  final String name;

  /// 多歌手已用 ` / ` 连接。
  final String artist;
  final String? album;
  final String? coverUrl;
  final Duration? duration;

  /// 收费标记：0 免费 / 1 会员 / 4 专辑付费 / 8 低音质免费。
  final int fee;

  /// 兼容 cloudsearch(`ar`/`al`) 与 v3 detail(`ar`/`al`) 两种字段名，
  /// 同时兜底老版 `artists`/`album`。
  static SongLite fromJson(Map<String, dynamic> json) {
    final List<dynamic> artists =
        (json['ar'] as List<dynamic>?) ?? (json['artists'] as List<dynamic>?) ?? const <dynamic>[];
    final Map<String, dynamic>? album =
        (json['al'] as Map<String, dynamic>?) ?? (json['album'] as Map<String, dynamic>?);
    final int? ms = (json['dt'] as int?) ?? (json['duration'] as int?);

    final String names = artists
        .map((dynamic a) => (a as Map<String, dynamic>)['name'] as String?)
        .whereType<String>()
        .join(' / ');

    return SongLite(
      id: (json['id'] as num).toInt(),
      name: (json['name'] as String?) ?? '未知曲目',
      artist: names.trim().isEmpty ? '未知艺术家' : names,
      album: album?['name'] as String?,
      coverUrl: (album?['picUrl'] as String?) ?? (json['picUrl'] as String?),
      duration: ms != null && ms > 0 ? Duration(milliseconds: ms) : null,
      fee: (json['fee'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 播放地址接口返回的单条结果。
class SongUrl {
  const SongUrl({
    required this.id,
    required this.url,
    this.bitrate = 0,
    this.size = 0,
    this.type,
    this.level,
    this.fee = 0,
    this.trialSeconds,
  });

  final int id;

  /// 无版权 / 无权益时网易云返回 null。
  final String? url;
  final int bitrate;
  final int size;

  /// 容器格式（mp3 / flac …）。
  final String? type;

  /// 音质档位（standard / higher / exhigh / lossless …）。
  final String? level;
  final int fee;

  /// 非空表示只给了试听片段（需要会员）。
  final int? trialSeconds;

  bool get playable => url != null && url!.isNotEmpty;
  bool get isTrialOnly => trialSeconds != null && trialSeconds! > 0;

  static SongUrl fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? trial = json['freeTrialInfo'] as Map<String, dynamic>?;
    final int? start = (trial?['start'] as num?)?.toInt();
    final int? end = (trial?['end'] as num?)?.toInt();

    return SongUrl(
      id: (json['id'] as num).toInt(),
      url: json['url'] as String?,
      bitrate: (json['br'] as num?)?.toInt() ?? 0,
      size: (json['size'] as num?)?.toInt() ?? 0,
      type: json['type'] as String?,
      level: json['level'] as String?,
      fee: (json['fee'] as num?)?.toInt() ?? 0,
      trialSeconds: (start != null && end != null && end > start) ? end - start : null,
    );
  }
}

/// 账号信息（用于校验 cookie 是否仍然有效）。
class NeteaseAccount {
  const NeteaseAccount({required this.uid, required this.nickname, this.avatarUrl});

  final int uid;
  final String nickname;
  final String? avatarUrl;
}

/// 二维码轮询状态码：800 过期 / 801 待扫描 / 802 待确认 / 803 成功。
class NeteaseQrStatus {
  const NeteaseQrStatus({required this.code, required this.message, this.cookie});

  final int code;
  final String message;

  /// 仅 803 时非空，已是可直接使用的 cookie 串。
  final String? cookie;

  bool get expired => code == 800;
  bool get waitingScan => code == 801;
  bool get waitingConfirm => code == 802;
  bool get authorized => code == 803;
}

// ════════════════════════════════════════════════════════════════
// 客户端
// ════════════════════════════════════════════════════════════════

/// 网易云 weapi 客户端。一个实例持有一份 cookie 会话。
class NeteaseApi {
  NeteaseApi({http.Client? client, String? cookie, Duration? minInterval})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _minInterval = minInterval ?? const Duration(milliseconds: 300) {
    if (cookie != null && cookie.isNotEmpty) applyCookie(cookie);
  }

  final http.Client _client;
  final bool _ownsClient;
  final Duration _minInterval;

  static const Duration _timeout = Duration(seconds: 10);

  final Map<String, String> _cookies = <String, String>{};

  Future<void> _gate = Future<void>.value();
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ── cookie ────────────────────────────────────────

  /// 当前 cookie 串（`k=v; k=v`），未登录时为空串。
  String get cookie =>
      _cookies.entries.map((MapEntry<String, String> e) => '${e.key}=${e.value}').join('; ');

  /// 是否已具备登录态主凭证。
  bool get isLoggedIn => (_cookies['MUSIC_U'] ?? '').isNotEmpty;

  /// 部分接口需要的 csrf token。
  String get csrf => _cookies['__csrf'] ?? '';

  /// 合并一段 cookie 串（WebView 抓取 / 用户手工粘贴 / Set-Cookie 均走这里）。
  void applyCookie(String raw) {
    for (final String piece in raw.split(RegExp(r'[;\n]'))) {
      final int eq = piece.indexOf('=');
      if (eq <= 0) continue;
      final String k = piece.substring(0, eq).trim();
      final String v = piece.substring(eq + 1).trim();
      if (k.isEmpty || _isCookieAttribute(k)) continue;
      _cookies[k] = v;
    }
  }

  /// 清空会话（登出）。
  void clearCookie() => _cookies.clear();

  /// 播放 CDN 需要的请求头（§3.3：交给 just_audio 的 AudioSource.uri）。
  Map<String, String> get playbackHeaders => <String, String>{
        'User-Agent': kNeteaseUserAgent,
        'Referer': '$kNeteaseBase/',
      };

  /// 释放内部 http client（外部注入的 client 由调用方自行关闭）。
  void close() {
    if (_ownsClient) _client.close();
  }

  // ── 业务接口 ──────────────────────────────────────

  /// 搜索歌曲。
  ///
  /// 走 `/weapi/cloudsearch/get/web`：相比老的 `/weapi/search/get`，它在
  /// 结果里直接带 `al.picUrl` 封面与 `dt` 时长，省掉一次详情请求。
  Future<List<SongLite>> searchSongs(
    String keyword, {
    int limit = 30,
    int offset = 0,
  }) async {
    if (keyword.trim().isEmpty) return const <SongLite>[];
    final Map<String, dynamic> res = await _post(
      '/weapi/cloudsearch/get/web',
      <String, dynamic>{
        's': keyword.trim(),
        'type': 1,
        'limit': limit,
        'offset': offset,
        'total': true,
      },
    );
    final List<dynamic> songs =
        ((res['result'] as Map<String, dynamic>?)?['songs'] as List<dynamic>?) ??
            const <dynamic>[];
    return songs
        .map((dynamic s) => SongLite.fromJson(s as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// 批量取播放地址。
  ///
  /// [level] 取值：standard / higher / exhigh / lossless / hires，
  /// 高档位需要账号本身具备相应会员权益，否则服务端自动降级。
  Future<List<SongUrl>> getSongUrls(
    List<int> ids, {
    String level = 'standard',
  }) async {
    if (ids.isEmpty) return const <SongUrl>[];
    final Map<String, dynamic> res = await _post(
      '/weapi/song/enhance/player/url/v1',
      <String, dynamic>{
        'ids': jsonEncode(ids),
        'level': level,
        'encodeType': 'flac',
      },
    );
    final List<dynamic> data = (res['data'] as List<dynamic>?) ?? const <dynamic>[];
    return data
        .map((dynamic e) => SongUrl.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// 批量取歌曲详情（补全标题 / 封面 / 时长）。
  Future<List<SongLite>> getSongDetails(List<int> ids) async {
    if (ids.isEmpty) return const <SongLite>[];
    final Map<String, dynamic> res = await _post(
      '/weapi/v3/song/detail',
      <String, dynamic>{
        'c': jsonEncode(
          ids.map((int id) => <String, int>{'id': id}).toList(growable: false),
        ),
      },
    );
    final List<dynamic> songs = (res['songs'] as List<dynamic>?) ?? const <dynamic>[];
    return songs
        .map((dynamic s) => SongLite.fromJson(s as Map<String, dynamic>))
        .toList(growable: false);
  }

  // ── 登录 ──────────────────────────────────────────

  /// 申请二维码 key。
  Future<String> createQrKey() async {
    final Map<String, dynamic> res = await _post(
      '/weapi/login/qrcode/unikey',
      <String, dynamic>{'type': 1},
    );
    final String? key = res['unikey'] as String?;
    if (key == null || key.isEmpty) {
      throw const NeteaseApiException(-1, '未能获取二维码 key');
    }
    return key;
  }

  /// 由 key 拼出二维码内容（交给 UI 渲染成图）。
  String qrLoginUrl(String key) => '$kNeteaseBase/login?codekey=$key';

  /// 轮询扫码状态；返回 803 时 cookie 已自动写入本实例。
  Future<NeteaseQrStatus> checkQrLogin(String key) async {
    final Map<String, dynamic> res = await _post(
      '/weapi/login/qrcode/client/login',
      <String, dynamic>{'key': key, 'type': 1},
      allowBusinessError: true,
    );
    final int code = (res['code'] as num?)?.toInt() ?? -1;
    return NeteaseQrStatus(
      code: code,
      message: (res['message'] as String?) ?? (res['msg'] as String?) ?? '',
      cookie: code == 803 ? cookie : null,
    );
  }

  /// 用现成 cookie 登录（WebView 抓取 / 用户手工粘贴 MUSIC_U）。
  ///
  /// 会立刻打一次账号接口校验；无效时抛 [NeteaseApiException] 且不保留 cookie。
  Future<NeteaseAccount> loginWithCookie(String raw) async {
    final Map<String, String> backup = Map<String, String>.of(_cookies);
    applyCookie(raw);
    try {
      return await account();
    } catch (_) {
      _cookies
        ..clear()
        ..addAll(backup);
      rethrow;
    }
  }

  /// 校验登录态并取账号信息。
  Future<NeteaseAccount> account() async {
    final Map<String, dynamic> res =
        await _post('/weapi/w/nuser/account/get', <String, dynamic>{});
    final Map<String, dynamic>? profile = res['profile'] as Map<String, dynamic>?;
    if (profile == null) {
      throw const NeteaseApiException(301, '登录态无效或已过期');
    }
    return NeteaseAccount(
      uid: (profile['userId'] as num?)?.toInt() ?? 0,
      nickname: (profile['nickname'] as String?) ?? '网易云用户',
      avatarUrl: profile['avatarUrl'] as String?,
    );
  }

  // ── 传输层 ────────────────────────────────────────

  /// 发一次 weapi POST。
  ///
  /// [allowBusinessError] 为 true 时不校验 `code`，由调用方自行判读
  /// （二维码轮询的 801/802 本就不是 200）。
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data, {
    bool allowBusinessError = false,
  }) {
    return _throttled(() async {
      final Map<String, dynamic> body = <String, dynamic>{
        ...data,
        if (csrf.isNotEmpty) 'csrf_token': csrf,
      };
      final Uri uri = Uri.parse('$kNeteaseBase$path').replace(
        queryParameters: csrf.isEmpty ? null : <String, String>{'csrf_token': csrf},
      );

      final http.Response res;
      try {
        res = await _client
            .post(
              uri,
              headers: <String, String>{
                'User-Agent': kNeteaseUserAgent,
                'Referer': '$kNeteaseBase/',
                'Origin': kNeteaseBase,
                'Content-Type': 'application/x-www-form-urlencoded',
                if (cookie.isNotEmpty) 'Cookie': cookie,
              },
              body: weapiJson(body),
            )
            .timeout(_timeout);
      } on TimeoutException {
        throw NeteaseApiException(-1, '请求超时：$path');
      } catch (e) {
        throw NeteaseApiException(-1, '网络请求失败：$path');
      }

      _captureSetCookie(res);

      if (res.statusCode != 200) {
        throw NeteaseApiException(-1, '接口 $path 返回 HTTP ${res.statusCode}');
      }

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        throw NeteaseApiException(-1, '接口 $path 返回了非 JSON 内容');
      }

      final int code = (json['code'] as num?)?.toInt() ?? 200;
      if (!allowBusinessError && code != 200) {
        throw NeteaseApiException(
          code,
          (json['message'] as String?) ?? (json['msg'] as String?) ?? '接口 $path 调用失败',
        );
      }
      return json;
    });
  }

  /// 全局串行 + 最小间隔，避免高频请求触发风控。
  Future<T> _throttled<T>(Future<T> Function() task) {
    final Completer<T> done = Completer<T>();
    _gate = _gate.then((_) async {
      final int wait =
          _minInterval.inMilliseconds - DateTime.now().difference(_lastAt).inMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      try {
        done.complete(await task());
      } catch (e, s) {
        done.completeError(e, s);
      } finally {
        _lastAt = DateTime.now();
      }
    });
    return done.future;
  }

  void _captureSetCookie(http.Response res) {
    final String? raw = res.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    // http 包会把多条 Set-Cookie 用逗号拼成一行，需在「逗号 + 新的 k=」处切开，
    // 否则会误伤 `Expires=Wed, 01 Jan ...` 里的逗号。
    for (final String one in raw.split(RegExp(r',(?=\s*[^;=\s]+=)'))) {
      final int semi = one.indexOf(';');
      applyCookie(semi >= 0 ? one.substring(0, semi) : one);
    }
  }

  static bool _isCookieAttribute(String key) => const <String>{
        'path',
        'domain',
        'expires',
        'max-age',
        'secure',
        'httponly',
        'samesite',
        'version',
      }.contains(key.toLowerCase());
}
