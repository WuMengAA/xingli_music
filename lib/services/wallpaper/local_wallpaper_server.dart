/// ════════════════════════════════════════════════════════════════════════
/// 本地静态文件服务（Steam 壁纸背景用）
/// ════════════════════════════════════════════════════════════════════════
///
/// Wallpaper Engine 的 `web` 壁纸用 `<script type="module">` 加载打包后的
/// JS，而 Chromium 在 `file://` 下会因 origin 为 `null` 拒绝加载 ES Module。
/// 因此这里在 `127.0.0.1` 随机端口起一个一次性静态服务，把壁纸目录暴露成
/// `http://127.0.0.1:<port>/`，再交给 [InAppWebView] 加载，规避 CORS。
///
/// 两种根来源：
/// - 文件系统目录（桌面：直接读本机 Steam 创意工坊路径）；
/// - 打包资源（手机等无 Steam 路径的平台：从 [rootBundle] 按路径提供）。

library;

import 'dart:io';

import 'package:flutter/services.dart';

/// 把壁纸目录（文件系统或打包资源）通过一次性本地 HTTP 服务暴露给 WebView。
class LocalWallpaperServer {
  /// 文件系统目录模式。
  LocalWallpaperServer.folder(this.rootDir) : assetBase = null;

  /// 打包资源模式：资源前缀，例如 `assets/wallpapers/sonic_topography`。
  LocalWallpaperServer.asset(this.assetBase) : rootDir = null;

  /// 文件系统根目录（[assetBase] 为 null 时生效）。
  final String? rootDir;

  /// 打包资源前缀（非 null 时从 [rootBundle] 提供，无需落盘）。
  final String? assetBase;

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

  Future<void> _handle(HttpRequest req) async {
    final String path = Uri.decodeComponent(req.uri.path);
    final String rel = path == '/' ? '/index.html' : path;
    if (assetBase != null) {
      await _serveAsset(req, rel);
      return;
    }
    _serveFile(req, rel);
  }

  void _serveFile(HttpRequest req, String rel) {
    final File file = File('$rootDir$rel');
    final String normalized = file.absolute.path;
    final String rootNormalized = File(rootDir!).absolute.path;
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

  Future<void> _serveAsset(HttpRequest req, String rel) async {
    // 资源 key 不以 '/' 开头
    final String key = '$assetBase${rel.startsWith('/') ? rel.substring(1) : rel}';
    try {
      final ByteData data = await rootBundle.load(key);
      req.response.headers.contentType = ContentType.parse(_mime(key));
      req.response.add(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      req.response.close();
    } catch (_) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..close();
    }
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
