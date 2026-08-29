import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../log_service.dart';

/// T11 投屏最小版：局域网 HTTP 流媒体服务（纯 dart:io，零新依赖）。
///
/// 启动后监听任意 IPv4 网卡，同网段设备（手机 / 平板 / 电视盒子）用
/// 浏览器、VLC、系统播放器打开 URL 即可播放当前曲目——即最小投屏通路。
///
/// 路由：
/// - `GET /`                 → 迷你 HTML 播放页（JS 自动解析 `?uri=` 并播放）
/// - `GET /track?uri=<u>`    → 音频流；支持 `Range: bytes=a-b`（206 切片）。
///    本地文件走 [File.openRead] 流式发送；http(s) URL 用 [http.Client]
///    代理转发并把上游 Range 语义原样透传。
/// - `GET /info?uri=<u>`     → JSON 元信息（标题 / 艺术家 / 封面 / 时长）
///
/// 注：AirPlay / Cast / DLNA 系统投屏不在此服务内（见 docs 说明），
/// 统一用「打开 URL」作为收敛通路；DLNA 电视盒可直接播 .m3u8 列表。
class CastStreamServer {
  CastStreamServer._();

  static final CastStreamServer instance = CastStreamServer._();

  /// 默认监听端口（冲突时自动 +1 重试）。
  static const int defaultPort = 8741;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _sub;
  int _port = defaultPort;
  bool _running = false;
  final http.Client _proxy = http.Client();

  bool get running => _running;

  /// 实际绑定端口（未启动时为 [defaultPort]）。
  int get port => _port;

  /// 启动服务。返回最终绑定端口。
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
        LogService.instance.i('cast', '投屏服务已启动，端口 $port');
        return _port;
      } on SocketException {
        _port++;
      }
    }
    throw StateError('投屏端口 $defaultPort-$port 均被占用');
  }

  /// 停止服务。幂等。
  Future<void> stop() async {
    if (!_running) return;
    await _sub?.cancel();
    _sub = null;
    await _server?.close(force: true);
    _server = null;
    _running = false;
    LogService.instance.i('cast', '投屏服务已停止');
  }

  /// 本机可用于投屏的 IPv4 地址（排除回环）。
  Future<List<String>> localIPv4() async {
    final List<String> out = <String>[];
    try {
      final List<NetworkInterface> ifs = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final NetworkInterface e in ifs) {
        for (final InternetAddress a in e.addresses) {
          if (!a.isLoopback && a.address.isNotEmpty) out.add(a.address);
        }
      }
    } catch (e) {
      LogService.instance.w('cast', '枚举本机 IP 失败: $e');
    }
    return out.toSet().toList();
  }

  Future<void> _onRequest(HttpRequest req) async {
    try {
      final HttpResponse res = req.response;
      switch (req.uri.path) {
        case '/':
          await _respondHtml(req, res);
        case '/track':
          await _respondStream(req, res);
        case '/info':
          await _respondInfo(req, res);
        default:
          res.statusCode = HttpStatus.notFound;
          res.write('not found');
          await res.close();
      }
    } catch (e) {
      LogService.instance.w('cast', '请求处理异常: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.write('server error');
        await req.response.close();
      } catch (_) {}
    }
  }

  // ── 迷你网页播放端 ────────────────────────────────────────────

  Future<void> _respondHtml(HttpRequest req, HttpResponse res) async {
    res.headers.contentType = ContentType.html;
    res.write(
      '<!DOCTYPE html><html lang="zh"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>星璃投屏</title><style>'
      'body{background:#0f1220;color:#e8eaf6;font-family:system-ui,sans-serif;'
      'display:flex;flex-direction:column;align-items:center;padding:32px 16px}'
      'h1{font-size:20px;margin:0 0 8px}h2{font-size:14px;color:#9aa0b4;margin:0 0 24px;'
      'text-align:center;word-break:break-all}audio{width:100%;max-width:480px}'
      '</style></head><body><h1>星璃 · 无限音乐画布</h1><h2 id="t">正在就绪…</h2>'
      '<audio id="a" controls autoplay></audio>'
      '<script>const u=decodeURIComponent(new URLSearchParams(location.search).get("uri")||"");'
      'if(u){document.title="星璃投屏";const h=u.split("/").pop()||"流媒体";'
      'document.getElementById("t").textContent=h;const a=document.getElementById("a");'
      'a.src="/track?uri="+encodeURIComponent(u);a.play().catch(()=>{});}'
      'else{document.getElementById("t").textContent="未指定曲目";}'
      '</script></body></html>',
    );
    await res.close();
  }

  // ── 音频流（Range 切片）──────────────────────────────────────

  Future<void> _respondStream(HttpRequest req, HttpResponse res) async {
    final String? uri = req.uri.queryParameters['uri'];
    if (uri == null || uri.isEmpty) {
      res.statusCode = HttpStatus.badRequest;
      res.write('missing uri');
      await res.close();
      return;
    }
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      await _proxyRemote(req, res, uri);
    } else {
      await _serveFile(req, res, uri);
    }
  }

  Future<void> _serveFile(HttpRequest req, HttpResponse res, String path) async {
    final File f = File(path);
    if (!await f.exists()) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final int size = await f.length();
    int start = 0;
    int end = size - 1;
    final String? range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null &&
        range.startsWith('bytes=') &&
        range.trim().length > 6) {
      final String spec = range.substring(6).split(',').first.trim();
      final List<String> parts = spec.split('-');
      if (spec.startsWith('-')) {
        // 后缀长度：bytes=-N 表示最后 N 字节
        final int suffix = int.tryParse(parts[1]) ?? 0;
        start = (size - suffix).clamp(0, size);
        end = size - 1;
      } else if (parts.length == 2) {
        start = int.tryParse(parts[0]) ?? 0;
        final int? rawEnd = parts[1].isEmpty ? null : int.tryParse(parts[1]);
        end = rawEnd ?? size - 1;
      }
      if (start < 0) start = 0;
      if (end >= size) end = size - 1;
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    } else {
      res.statusCode = HttpStatus.ok;
    }
    res.headers.set(HttpHeaders.contentLengthHeader, '${end - start + 1}');
    res.headers.set(HttpHeaders.contentTypeHeader, _contentTypeFor(path));
    await res.addStream(f.openRead(start, end + 1));
    await res.close();
  }

  Future<void> _proxyRemote(
    HttpRequest req,
    HttpResponse res,
    String uri,
  ) async {
    final http.Request out = http.Request('GET', Uri.parse(uri));
    final String? range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) out.headers[HttpHeaders.rangeHeader] = range;
    final String? ua = req.headers.value(HttpHeaders.userAgentHeader);
    out.headers[HttpHeaders.userAgentHeader] = ua ?? 'xingli-cast/1.0';
    try {
      final http.StreamedResponse up = await _proxy.send(out).timeout(
        const Duration(seconds: 20),
      );
      res.statusCode = up.statusCode;
      up.headers.forEach((String k, String v) {
        final String kk = k.toLowerCase();
        if (kk == 'transfer-encoding' ||
            kk == 'content-length' ||
            kk == 'connection') {
          return;
        }
        try {
          res.headers.set(k, v);
        } catch (_) {}
      });
      await res.addStream(up.stream);
      await res.close();
    } catch (e) {
      LogService.instance.w('cast', '远程代理失败: $uri -> $e');
      try {
        res.statusCode = HttpStatus.badGateway;
        res.write('upstream failed');
        await res.close();
      } catch (_) {}
    }
  }

  // ── 元信息（供 UI / 脚本展示标题与封面）──────────────────────

  Future<void> _respondInfo(HttpRequest req, HttpResponse res) async {
    final String uri = req.uri.queryParameters['uri'] ?? '';
    final String title = req.uri.queryParameters['title'] ?? uri;
    final String artist = req.uri.queryParameters['artist'] ?? '';
    final String cover = req.uri.queryParameters['cover'] ?? '';
    res.headers.contentType = ContentType.json;
    res.write(
      '{"uri":"${_jsonEscape(uri)}","title":"${_jsonEscape(title)}",'
      '"artist":"${_jsonEscape(artist)}","cover":"${_jsonEscape(cover)}"}',
    );
    await res.close();
  }

  static String _jsonEscape(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');

  static String _contentTypeFor(String path) {
    final String p = path.toLowerCase();
    if (p.endsWith('.mp3')) return 'audio/mpeg';
    if (p.endsWith('.flac')) return 'audio/flac';
    if (p.endsWith('.m4a') || p.endsWith('.aac')) return 'audio/mp4';
    if (p.endsWith('.wav')) return 'audio/wav';
    if (p.endsWith('.ogg')) return 'audio/ogg';
    if (p.endsWith('.opus')) return 'audio/ogg';
    if (p.endsWith('.wma')) return 'audio/x-ms-wma';
    return 'application/octet-stream';
  }
}