import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io;

/// ════════════════════════════════════════════════════════════════════════
/// HTTP 客户端工厂（cl10：加密连接）
/// ════════════════════════════════════════════════════════════════════════
///
/// 默认返回标准 [http.Client]（走系统根 CA 校验）。
/// [lenient] 为 true 时返回接受任意证书（含自签名）的客户端，供自托管
/// 局域网中继/内容服务使用——仅加密、不认证，由用户在设置中显式开启。

/// 构造 HTTP 客户端。
http.Client makeHttpClient({bool lenient = false}) {
  if (!lenient) return http.Client();
  final HttpClient raw = HttpClient()
    ..badCertificateCallback = (_, __, ___) => true;
  return io.IOClient(raw);
}
