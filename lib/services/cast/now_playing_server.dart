import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../log_service.dart';

/// ============================================================================
/// NowPlayingServer —— 星璃本地「现在播放」状态服务（ClassIsland 联动 · 方案见
/// docs/方案_ClassIsland联动.md）。
///
/// 纯 dart:io HttpServer，**零 Riverpod 依赖**：状态通过 [reader] 闭包注入，
/// 远程控制通过可选 [control] 闭包注入，便于脱离 App 单独单测。
///
/// 路由（协议 v1，冻结见方案文档 §3；v1.1 可选 token 鉴权见 §8）：
/// - `GET  /nowplaying` → 当前曲目 + 播放状态 + 电台状态 JSON
/// - `GET  /health`     → 探活 `{"ok":true,"app":"xingli_music","version":...}`
/// - `POST /control`    → `{"action":"play|pause|toggle|next|prev"}`（仅本机回环）
///
/// 鉴权（v1.1，可选）：构造传入 [token] 时开启——所有端点需带
/// `?token=` 查询参数或 `Authorization: Bearer <token>` 头，否则 401；
/// 有 token 时 `/control` 放行任意来源（token 即授权凭据）。
/// [token] 为 null/空（默认）→ v1 冻结行为：GET 局域网开放、/control 仅回环。
/// ============================================================================

/// 曲目快照（/nowplaying 的 `track` 对象）。
class NowPlayingTrack {
  const NowPlayingTrack({
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    this.isLiveStream = false,
    this.sourceId,
  });

  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final bool isLiveStream;
  final String? sourceId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'artist': artist,
        'album': album,
        'coverUrl': coverUrl,
        'isLiveStream': isLiveStream,
        'sourceId': sourceId,
      };
}

/// 电台快照（/nowplaying 的 `radio` 对象；不在电台房时为 null）。
class NowPlayingRadio {
  const NowPlayingRadio({
    this.role,
    this.isDj = false,
    this.djName,
    this.roomName,
    this.roomCode,
    this.mode,
    this.memberCount,
  });

  final String? role; // 'host' | 'client' | null
  final bool isDj;
  final String? djName;
  final String? roomName;
  final String? roomCode;
  final String? mode; // 'campus' | 'listen' | null
  final int? memberCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'inStation': true,
        'role': role,
        'isDj': isDj,
        'djName': djName,
        'roomName': roomName,
        'roomCode': roomCode,
        'mode': mode,
        'memberCount': memberCount,
      };
}

/// 完整 /nowplaying 响应快照。
class NowPlayingSnapshot {
  const NowPlayingSnapshot({
    this.track,
    this.isPlaying = false,
    this.positionMs,
    this.durationMs,
    this.radio,
  });

  final NowPlayingTrack? track;
  final bool isPlaying;
  final int? positionMs;
  final int? durationMs;
  final NowPlayingRadio? radio;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': 1,
        'app': 'xingli_music',
        'track': track?.toJson(),
        'isPlaying': isPlaying,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'radio': radio?.toJson(),
      };
}

/// 本机远程控制动作白名单（协议 v1）。
const List<String> kNowPlayingActions = <String>[
  'play',
  'pause',
  'toggle',
  'next',
  'prev',
];

class NowPlayingServer {
  NowPlayingServer({
    required NowPlayingSnapshot Function() reader,
    this.version = '',
    this.control,
    this.token,
  }) : _reader = reader;

  static const int defaultPort = 8742;

  final NowPlayingSnapshot Function() _reader;
  final String version;

  /// 可选鉴权 token（v1.1）。null/空 = 关闭鉴权（v1 冻结行为）。
  final String? token;

  /// 远程控制处理器（未注入时 /control 返回 501）。返回 true 表示已受理。
  final Future<bool> Function(String action)? control;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _sub;
  int _port = defaultPort;
  bool _running = false;

  bool get running => _running;

  /// 实际绑定端口（未启动时为 [defaultPort]）。
  int get port => _port;

  /// 启动服务。返回最终绑定端口（冲突自动 +1，最多重试 10 次）。
  Future<int> start() async {
    if (_running) return _port;
    for (int i = 0; i < 10; i++) {
      try {
        final HttpServer server =
            await HttpServer.bind(InternetAddress.anyIPv4, _port);
        server.idleTimeout = const Duration(hours: 2);
        _server = server;
        _sub = server.listen(_onRequest, onError: (_) {});
        _running = true;
        LogService.instance
            .i('np', 'NowPlaying 服务已启动（ClassIsland 联动），端口 $port');
        return _port;
      } on SocketException {
        _port++;
      }
    }
    throw StateError('NowPlaying 端口 $defaultPort-$port 均被占用');
  }

  /// 停止服务。幂等。
  Future<void> stop() async {
    if (!_running) return;
    await _sub?.cancel();
    _sub = null;
    await _server?.close(force: true);
    _server = null;
    _running = false;
    LogService.instance.i('np', 'NowPlaying 服务已停止');
  }

  Future<void> _onRequest(HttpRequest req) async {
    final HttpResponse res = req.response;
    try {
      // v1.1 可选鉴权：启用 token 后，三个 API 端点均需通过校验。
      final bool isApi = req.uri.path == '/health' ||
          req.uri.path == '/nowplaying' ||
          req.uri.path == '/control';
      if (isApi && !_authorized(req)) {
        await _respondText(res, HttpStatus.unauthorized, 'unauthorized');
        return;
      }
      switch (req.method) {
        case 'GET':
          switch (req.uri.path) {
            case '/health':
              await _respondHealth(res);
            case '/nowplaying':
              await _respondNowPlaying(res);
            default:
              await _respondText(res, HttpStatus.notFound, 'not found');
          }
        case 'POST':
          if (req.uri.path == '/control') {
            await _respondControl(req, res);
          } else {
            await _respondText(res, HttpStatus.notFound, 'not found');
          }
        default:
          await _respondText(res, HttpStatus.notFound, 'not found');
      }
    } catch (e) {
      LogService.instance.w('np', '请求处理异常: $e');
      try {
        await _respondText(
            res, HttpStatus.internalServerError, 'server error');
      } catch (_) {}
    }
  }

  Future<void> _respondHealth(HttpResponse res) async {
    await _respondJson(res, <String, dynamic>{
      'ok': true,
      'app': 'xingli_music',
      'version': version,
    });
  }

  Future<void> _respondNowPlaying(HttpResponse res) async {
    NowPlayingSnapshot snapshot;
    try {
      snapshot = _reader();
    } catch (e) {
      LogService.instance.w('np', '快照读取异常: $e');
      await _respondText(res, HttpStatus.internalServerError, 'reader error');
      return;
    }
    await _respondJson(res, snapshot.toJson());
  }

  /// v1.1 鉴权：token 未启用（null/空）时恒放行；启用时接受
  /// `?token=` 查询参数或 `Authorization: Bearer <token>` 头。
  bool _authorized(HttpRequest req) {
    final String? t = token;
    if (t == null || t.isEmpty) return true;
    final String? fromQuery = req.uri.queryParameters['token'];
    if (fromQuery != null && _constantTimeEquals(fromQuery, t)) return true;
    final String? auth = req.headers.value(HttpHeaders.authorizationHeader);
    if (auth != null &&
        auth.startsWith('Bearer ', 0) &&
        _constantTimeEquals(auth.substring(7).trim(), t)) {
      return true;
    }
    return false;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _respondControl(HttpRequest req, HttpResponse res) async {
    // 回环限制仅在未启用 token 时生效（v1 冻结行为：防局域网误触）。
    // 启用 token 后由鉴权承担授权边界，允许异机（有 token 即可信）。
    final String? t = token;
    if (t == null || t.isEmpty) {
      // 只允许本机回环来源（127.0.0.1 / ::1）——局域网只读展示，写操作防误触。
      final InternetAddress? from = req.connectionInfo?.remoteAddress;
      final bool loopback = from != null &&
          (from.isLoopback ||
              from.address == '0.0.0.0' ||
              from.address == '::');
      if (!loopback) {
        await _respondText(res, HttpStatus.forbidden, 'loopback only');
        return;
      }
    }
    if (control == null) {
      await _respondText(res, HttpStatus.notImplemented, 'no controller');
      return;
    }
    String action = '';
    try {
      final String body = await utf8.decoder.bind(req).join();
      action = (jsonDecode(body) as Map<String, dynamic>)['action'] as String? ??
          '';
    } catch (_) {
      action = '';
    }
    if (!kNowPlayingActions.contains(action)) {
      await _respondText(res, HttpStatus.badRequest, 'unknown action');
      return;
    }
    final bool ok = await control!(action);
    if (!ok) {
      await _respondText(res, HttpStatus.conflict, 'action rejected');
      return;
    }
    res.statusCode = HttpStatus.noContent;
    await res.close();
  }

  Future<void> _respondJson(HttpResponse res, Map<String, dynamic> body) async {
    res.headers.contentType = ContentType('application', 'json',
        charset: 'utf-8');
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<void> _respondText(
      HttpResponse res, int statusCode, String text) async {
    res.statusCode = statusCode;
    res.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
    res.write(text);
    await res.close();
  }
}