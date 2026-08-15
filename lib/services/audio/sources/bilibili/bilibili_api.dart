/// ════════════════════════════════════════════════════════════════════
/// 星璃 · 哔哩哔哩（B站）视频源 HTTP 客户端
/// ════════════════════════════════════════════════════════════════════
///
/// 只做「发请求 / 解 JSON / 管 cookie」三件事，不碰 Track、不碰 Riverpod、
/// 不碰落盘 —— 凭证加密由 `SecureBox` 负责，曲目映射由 `BilibiliSource` 负责。
///
/// 能力：
///   - 搜索视频（`x/web-interface/search/type`，公开接口，未登录也可用）；
///   - 解析视频音频流（`x/player/playurl` DASH audio m4s，登录后更高音质）；
///   - 二维码登录（`passport.bilibili.com` generate / poll，取 SESSDATA）。
///
/// 约定（与网易云源一致）：
///   - 必带桌面 Chrome UA 与 `Referer: https://www.bilibili.com/`；
///   - 全局串行节流（最小间隔 300ms）；
///   - 单请求 10s 超时；
///   - **禁止**打印 cookie / 请求头原文（日志脱敏）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// 接口根地址。
const String kBilibiliApiBase = 'https://api.bilibili.com';
const String kBilibiliPassportBase = 'https://passport.bilibili.com';

/// 桌面端 UA（搜索/播放接口反爬基础）。
const String kBilibiliUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// wbi 签名所需的 64 位混排表（B站官方固定，不可改）。
const List<int> _kWbiMixinTable = <int>[
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, //
  27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, //
  37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, //
  22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
];

/// B站接口返回的业务错误（HTTP 200 但 code != 0 也走这里）。
class BilibiliApiException implements Exception {
  const BilibiliApiException(this.code, this.message);

  /// B站业务错误码；-1 表示传输层/解析层失败。
  final int code;
  final String message;

  /// 登录失效/风控（-101 未登录、-352 风控校验）。
  bool get isAuthFailure => code == -101 || code == -352 || code == -400;

  @override
  String toString() => 'BilibiliApiException($code): $message';
}

/// 搜索结果里的轻量视频信息。
class BiliVideoLite {
  const BiliVideoLite({
    required this.bvid,
    required this.title,
    required this.author,
    required this.durationSeconds,
    this.coverUrl,
  });

  final String bvid;

  /// 标题（已剥离搜索高亮 `<em>` 标签）。
  final String title;

  final String author;

  /// 视频时长（秒）。
  final int durationSeconds;

  final String? coverUrl;
}

/// 二维码状态。
enum BiliQrStatus {
  /// 已授权（登录成功）。
  authorized,

  /// 等待扫码（未扫）。
  waitingScan,

  /// 已扫待确认。
  waitingConfirm,

  /// 已过期。
  expired,
}

/// B站 HTTP 客户端。
class BilibiliApi {
  BilibiliApi();

  /// 当前 cookie 串（`SESSDATA=..; bili_jct=..; DedeUserID=..`）。
  String _cookie = '';
  String get cookie => _cookie;

  bool get isLoggedIn => _cookie.contains('SESSDATA=');

  /// 上次请求时间（全局串行节流）。
  DateTime _lastReq = DateTime.fromMillisecondsSinceEpoch(0);

  final http.Client _client = http.Client();

  /// wbi 混排键缓存（nav 接口取得，10 分钟有效，避免每次播放都请求）。
  String? _wbiMixinKey;
  DateTime _wbiKeyExpire = DateTime.fromMillisecondsSinceEpoch(0);

  /// 串行节流：两次请求至少间隔 [kBilibiliMinInterval]。
  Future<void> _throttle() async {
    final DateTime now = DateTime.now();
    final int wait = 300 -
        now.difference(_lastReq).inMilliseconds;
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    _lastReq = DateTime.now();
  }

  Map<String, String> _headers({bool referer = true}) => <String, String>{
        'User-Agent': kBilibiliUserAgent,
        if (referer) 'Referer': 'https://www.bilibili.com/',
        if (_cookie.isNotEmpty) 'Cookie': _cookie,
      };

  /// 发 JSON 请求并统一解析 B站业务码。
  Future<dynamic> _getJson(
    String url, {
    bool referer = true,
    bool withCookie = true,
  }) async {
    await _throttle();
    final http.Response resp;
    try {
      resp = await _client
          .get(Uri.parse(url),
              headers: withCookie ? _headers(referer: referer) : _headers(referer: referer))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const BilibiliApiException(-1, '请求超时');
    } on http.ClientException catch (e) {
      throw BilibiliApiException(-1, '网络异常: ${e.message}');
    }
    if (resp.statusCode != 200) {
      throw BilibiliApiException(resp.statusCode, 'HTTP ${resp.statusCode}');
    }
    final dynamic body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw const BilibiliApiException(-1, '响应格式异常');
    }
    final int code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw BilibiliApiException(
          code, (body['message'] as String?) ?? '接口错误');
    }
    return body;
  }

  /// 清除内存 cookie（登出）。
  void clearCookie() => _cookie = '';

  /// 用现成 cookie 串登录（粘贴 / 其它通道抓取）。
  ///
  /// 校验：拿 cookie 请求一次「我的信息」——失败视为无效。
  Future<void> loginWithCookie(String rawCookie) async {
    _cookie = rawCookie.trim();
    try {
      await account();
    } catch (_) {
      _cookie = '';
      rethrow;
    }
  }

  /// 当前账号信息（未登录 / 失败返回 null）。
  ///
  /// R26skel-b6：附带大会员状态（nav 的 `vipStatus`/`vipType`），供音质
  /// 选择自动识别（大会员解锁更高清晰度）。
  Future<({String? uname, bool vip})?> account() async {
    final dynamic body = await _getJson(
      '$kBilibiliApiBase/x/web-interface/nav',
      withCookie: true,
    );
    final dynamic data = body['data'];
    if (data is Map && data['isLogin'] == true) {
      final dynamic uname = data['uname'];
      final int vipStatus = (data['vipStatus'] as num?)?.toInt() ?? 0;
      final int vipType = (data['vipType'] as num?)?.toInt() ?? 0;
      return (
        uname: uname is String ? uname : null,
        vip: vipStatus > 0 && vipType > 0,
      );
    }
    throw const BilibiliApiException(-101, '未登录');
  }

  // ── 二维码登录 ────────────────────────────────────────────────────

  /// 申请二维码，返回 qrcode_key（渲染 URL 用 [qrLoginUrl]）。
  Future<String> createQrKey() async {
    await _throttle();
    final http.Response resp = await _client
        .get(
          Uri.parse('$kBilibiliPassportBase/x/passport-login/web/qrcode/generate'),
          headers: _headers(referer: false),
        )
        .timeout(const Duration(seconds: 10));
    final dynamic body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (body is! Map<String, dynamic> || body['code'] != 0) {
      throw const BilibiliApiException(-1, '二维码获取失败');
    }
    final dynamic data = body['data'];
    if (data is! Map || data['qrcode_key'] is! String) {
      throw const BilibiliApiException(-1, '二维码数据缺失');
    }
    return data['qrcode_key'] as String;
  }

  /// 二维码内容（用户扫码跳转的 URL）。
  String qrLoginUrl(String key) =>
      'https://passport.bilibili.com/h5/app/passport/login?navhide=1&qrcode_key=$key';

  /// 轮询一次扫码状态。
  ///
  /// 成功时从 Set-Cookie 抓取 SESSDATA/bili_jct 等并写入 [_cookie]。
  Future<BiliQrStatus> checkQrLogin(String key) async {
    await _throttle();
    final http.Response resp = await _client
        .post(
          Uri.parse(
              '$kBilibiliPassportBase/x/passport-login/web/qrcode/poll?qrcode_key=$key'),
          headers: _headers(referer: false),
        )
        .timeout(const Duration(seconds: 10));
    // 先抓 Set-Cookie（登录成功的关键凭证在响应头而非 JSON）。
    final List<String> setCookies = resp.headers['set-cookie'] == null
        ? const <String>[]
        : resp.headers['set-cookie']!.split(',').map((String s) => s.trim()).toList();
    final dynamic body = jsonDecode(utf8.decode(resp.bodyBytes));
    final int bizCode = body is Map && body['code'] == 0
        ? (((body['data'] as Map?)?['code'] as num?)?.toInt() ?? -1)
        : -1;
    switch (bizCode) {
      case 0: // 登录成功
        if (setCookies.isNotEmpty) {
          _cookie = setCookies
              .where((String c) => c.contains('='))
              .map((String c) => c.split(';').first.trim())
              .join('; ');
        }
        return BiliQrStatus.authorized;
      case 86038:
        return BiliQrStatus.expired;
      case 86090:
        return BiliQrStatus.waitingScan;
      case 86101:
      case 86058:
        return BiliQrStatus.waitingConfirm;
      default:
        return BiliQrStatus.waitingScan;
    }
  }

  // ── 搜索 ──────────────────────────────────────────────────────────

  /// 按关键词搜索视频。返回轻量视频列表（未登录也可用）。
  Future<List<BiliVideoLite>> searchVideos(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final dynamic body = await _getJson(
      '$kBilibiliApiBase/x/web-interface/search/type'
      '?search_type=video&keyword=${Uri.encodeQueryComponent(keyword)}'
      '&page=$page&page_size=$pageSize',
      withCookie: true,
    );
    final dynamic data = body['data'];
    final dynamic result = data is Map ? data['result'] : null;
    if (result is! List) return const <BiliVideoLite>[];
    final List<BiliVideoLite> out = <BiliVideoLite>[];
    for (final dynamic it in result) {
      if (it is! Map) continue;
      final String bvid = (it['bvid'] as String?) ?? '';
      if (bvid.isEmpty) continue;
      final int secs = _parseDuration(it['duration']);
      if (secs <= 0) continue;
      out.add(BiliVideoLite(
        bvid: bvid,
        title: _stripEm((it['title'] as String?) ?? ''),
        author: (it['author'] as String?) ?? '',
        durationSeconds: secs,
        coverUrl: it['pic'] is String ? it['pic'] as String : null,
      ));
    }
    return out;
  }

  /// 解析 B站时长：`"MM:SS"` / `"H:MM:SS"` / 秒数 统一转秒。
  static int _parseDuration(dynamic v) {
    if (v is num) return v.toInt();
    if (v is! String) return 0;
    final String s = v.trim();
    if (s.isEmpty) return 0;
    if (s.contains(':')) {
      final List<String> parts = s.split(':');
      int secs = 0;
      for (final String p in parts) {
        secs = secs * 60 + (int.tryParse(p.trim()) ?? 0);
      }
      return secs;
    }
    return int.tryParse(s) ?? 0;
  }

  /// 剥离搜索高亮 `<em class="keyword">` 标签。
  static String _stripEm(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '');

  // ── 播放地址 ──────────────────────────────────────────────────────

  /// 取视频 cid（view 接口，无需登录、无需签名即可访问）。
  Future<int> _fetchCid(String bvid) async {
    final dynamic body = await _getJson(
      '$kBilibiliApiBase/x/web-interface/view?bvid=$bvid',
      withCookie: false,
    );
    final dynamic data = body['data'];
    final int cid = (data is Map ? (data['cid'] as num?)?.toInt() : null) ?? 0;
    if (cid == 0) throw const BilibiliApiException(-1, '无法获取视频 cid');
    return cid;
  }

  /// 取 wbi 混排键（nav 接口，缓存 10 分钟）。
  Future<String> _getMixinKey() async {
    final DateTime now = DateTime.now();
    if (_wbiMixinKey != null && _wbiKeyExpire.isAfter(now)) {
      return _wbiMixinKey!;
    }
    final dynamic body = await _getJson(
      '$kBilibiliApiBase/x/web-interface/nav',
      withCookie: false,
    );
    final dynamic data = body['data'];
    final dynamic wbi = data is Map ? data['wbi_img'] : null;
    if (wbi is! Map) throw const BilibiliApiException(-1, 'wbi 密钥获取失败');
    final String imgUrl = (wbi['img_url'] as String?) ?? '';
    final String subUrl = (wbi['sub_url'] as String?) ?? '';
    final String imgKey = imgUrl.split('/').last.split('.').first;
    final String subKey = subUrl.split('/').last.split('.').first;
    final String raw = imgKey + subKey;
    final StringBuffer sb = StringBuffer();
    for (final int i in _kWbiMixinTable) {
      if (i < raw.length) sb.write(raw[i]);
    }
    final String key = sb.toString();
    _wbiMixinKey = key.length > 32 ? key.substring(0, 32) : key;
    _wbiKeyExpire = now.add(const Duration(minutes: 10));
    return _wbiMixinKey!;
  }

  /// 构造带 wbi 签名的 playurl 请求地址（同时补齐 cid）。
  ///
  /// B站 `x/player/playurl` 现在**必须**同时带 wbi 签名（w_rid/wts）与视频
  /// cid，否则返回 -400。音频流与画面流共用同一个 playurl，仅返回字段不同。
  Future<String> _signedPlayUrl(String bvid) async {
    final int cid = await _fetchCid(bvid);
    final String mixinKey = await _getMixinKey();
    final Map<String, String> params = <String, String>{
      'bvid': bvid,
      'cid': cid.toString(),
      'fnval': '16',
      'fourk': '1',
    };
    final int wts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    params['wts'] = wts.toString();
    final List<String> keys = params.keys.toList()..sort();
    final String raw = keys.map((String k) => '$k=${params[k]}').join('&');
    final String wrid = md5.convert(utf8.encode(raw + mixinKey)).toString();
    params['w_rid'] = wrid;
    return Uri.parse('$kBilibiliApiBase/x/player/playurl')
        .replace(queryParameters: params)
        .toString();
  }

  /// 解析 BVID 的音频流（DASH audio m4s）。
  ///
  /// 返回首个可用 audio 的 baseUrl（未登录也能拿到低码率音频；登录后更高
  /// 音质）。若 DASH 缺失，回退 durl（mp4 直链，含音轨）。失败抛中文异常。
  Future<String> resolveAudioUrl(String bvid) async {
    final dynamic body = await _getJson(
      await _signedPlayUrl(bvid),
      withCookie: true,
    );
    final dynamic data = body['data'];
    if (data is! Map) {
      throw const BilibiliApiException(-1, '播放地址获取失败');
    }
    final dynamic dash = data['dash'];
    if (dash is Map) {
      final dynamic audio = dash['audio'];
      if (audio is List && audio.isNotEmpty) {
        // 按码率降序选最高音质；取 baseUrl（baseUrl 通常最稳）。
        final List<dynamic> sorted = List<dynamic>.of(audio)
          ..sort((dynamic a, dynamic b) =>
              ((b as Map)['bandwidth'] as num? ?? 0)
                  .compareTo(((a as Map)['bandwidth'] as num? ?? 0)));
        final dynamic best = sorted.first;
        final String? base = (best as Map)['baseUrl'] as String?;
        if (base != null && base.isNotEmpty) return base;
        final dynamic backups = best['backupUrl'];
        if (backups is List && backups.isNotEmpty) {
          final String? b = backups.first as String?;
          if (b != null && b.isNotEmpty) return b;
        }
      }
    }
    // 回退：非 DASH 的 mp4 直链（含音轨）。
    final dynamic durl = data['durl'];
    if (durl is List && durl.isNotEmpty) {
      final String? url = (durl.first as Map)['url'] as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    throw const BilibiliApiException(-1, '该视频无可播放音频流');
  }

  /// 解析 BVID 的视频画面流（DASH video m4s）。
  ///
  /// 供「B站视频作场景背景」使用（背景视频默认静音，只听主播放器的音乐）。
  /// 取码率最高的 video 流；DASH 缺失则抛异常（视频画面需要 DASH）。
  ///
  /// [qualityIndex]：0 = 最高可用（自动）；越大取越低档（1 = 次高、
  /// 2 = 三档…）。自动夹到可用档数内。
  Future<String> resolveVideoUrl(String bvid, {int qualityIndex = 0}) async {
    final dynamic body = await _getJson(
      await _signedPlayUrl(bvid),
      withCookie: true,
    );
    final dynamic data = body['data'];
    if (data is! Map) {
      throw const BilibiliApiException(-1, '视频画面获取失败');
    }
    final dynamic dash = data['dash'];
    if (dash is! Map) {
      throw const BilibiliApiException(-1, '该视频无 DASH 画面流');
    }
    final dynamic video = dash['video'];
    if (video is! List || video.isEmpty) {
      throw const BilibiliApiException(-1, '该视频无画面流');
    }
    final List<dynamic> sorted = List<dynamic>.of(video)
      ..sort((dynamic a, dynamic b) =>
          ((b as Map)['bandwidth'] as num? ?? 0)
              .compareTo(((a as Map)['bandwidth'] as num? ?? 0)));
    final int idx = qualityIndex.clamp(0, sorted.length - 1);
    final dynamic pick = sorted[idx];
    final String? base = (pick as Map)['baseUrl'] as String?;
    if (base != null && base.isNotEmpty) return base;
    final dynamic backups = pick['backupUrl'];
    if (backups is List && backups.isNotEmpty) {
      final String? b = backups.first as String?;
      if (b != null && b.isNotEmpty) return b;
    }
    throw const BilibiliApiException(-1, '该视频无可播放画面流');
  }

  /// 释放（provider dispose 时调用）。
  void close() => _client.close();
}
