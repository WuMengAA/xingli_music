/// ════════════════════════════════════════════════════════════════════════
/// 本地静态文件服务（Steam 壁纸背景用）
/// ════════════════════════════════════════════════════════════════════════
///
/// Wallpaper Engine 的 `web` 壁纸用 `<script type="module">` 加载打包后的
/// JS，而 Chromium 在 `file://` 下会因 origin 为 `null` 拒绝加载 ES Module。
/// 因此这里在 `127.0.0.1` 随机端口起一个一次性静态服务，把壁纸目录暴露成
/// `http://127.0.0.1:<port>/`，再交给 [InAppWebView] 加载，规避 CORS。

library;

import 'dart:io';

/// 把 [rootDir] 通过一次性本地 HTTP 服务暴露给 WebView。
class LocalWallpaperServer {
  LocalWallpaperServer(this.rootDir);

  final String rootDir;
  HttpServer? _server;
  int? _port;

  /// 已启动后的监听端口（启动前为 null）。
  int? get port => _port;

  /// 在 127.0.0.1 随机端口启动，返回端口号。
  Future<int> start() async {
    _server = await HttpServer.bind('127.0.0.1', 0);
    _port = _server!.port;
    _server!.listen(_handle);
    return _port!;
  }

  void _handle(HttpRequest req) {
    final String path = Uri.decodeComponent(req.uri.path);
    final String rel = path == '/' ? '/index.html' : path;
    final File file = File('$rootDir$rel');
    final String normalized = file.absolute.path;
    final String rootNormalized = File(rootDir).absolute.path;
    // 防目录穿越：必须落在 root 之内且真实存在。
    if (!normalized.startsWith(rootNormalized) || !file.existsSync()) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }
    req.response.headers.contentType = ContentType.parse(_mime(file.path));
    req.response.add(file.readAsBytesSync());
    req.response.close();
  }

  void dispose() {
    _server?.close(force: true);
    _server = null;
    _port = null;
  }
}

/// 极简 MIME 推断（仅覆盖壁纸常见类型，避免引入额外依赖）。
String _mime(String p) {
  if (p.endsWith('.js') || p.endsWith('.mjs')) return 'application/javascript';
  if (p.endsWith('.css')) return 'text/css';
  if (p.endsWith('.html') || p.endsWith('.htm')) return 'text/html';
  if (p.endsWith('.gif')) return 'image/gif';
  if (p.endsWith('.json')) return 'application/json';
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
  if (p.endsWith('.svg')) return 'image/svg+xml';
  if (p.endsWith('.woff') || p.endsWith('.woff2')) return 'font/woff2';
  return 'application/octet-stream';
}
