/// 局域网日志服务器自动发现（零依赖 UDP 广播）。
///
/// 手机与电脑在**同一 Wi-Fi** 下时，App 向 `255.255.255.255:8766` 广播
/// `STELLARA_LOG_PROBE`；日志服务（tools/log_server/server.js，UDP 8766）
/// 收到后回 `STELLARA_LOG_FOUND <port>`。本类取响应源 IP，拼出
/// `http://<ip>:8765` 作为上报地址 —— 免去手动填电脑 IP。
///
/// 超时无响应（服务端未启动 / 不同网段 / 防火墙拦 UDP）返回 null。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 与服务端约定的 UDP 发现端口。
const int kDiscoveryPort = 8766;

/// HTTP 服务端口（发现响应只回端口，IP 取响应源地址）。
const int kLogHttpPort = 8765;

/// 探测消息（服务端原文匹配）。
const String kProbe = 'STELLARA_LOG_PROBE';

/// 响应前缀。
const String kFoundPrefix = 'STELLARA_LOG_FOUND';

/// 广播发现日志服务器；返回 `http://<ip>:8765`，未找到返回 null。
///
/// [timeout] 内没等到任何响应即放弃（默认 3s，用户可感知的等待上限）。
Future<String?> discoverLogServer({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final RawDatagramSocket socket;
  try {
    socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
  } catch (_) {
    return null; // 无网络权限等
  }

  final Completer<String?> completer = Completer<String?>();
  Timer? timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete(null);
  });

  socket.listen((RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final Datagram? dg = socket.receive();
      if (dg == null) return;
      final String text = String.fromCharCodes(dg.data).trim();
      if (text.startsWith(kFoundPrefix) && !completer.isCompleted) {
        timer.cancel();
        // IP 取响应源地址（UDP 应答来自日志服务器本机）。
        completer.complete('http://${dg.address.address}:$kLogHttpPort');
      }
    } else if (event == RawSocketEvent.closed) {
      if (!completer.isCompleted) {
        timer.cancel();
        completer.complete(null);
      }
    }
  });

  try {
    // 受限广播：同一子网内的主机都能收到。
    socket.send(utf8.encode(kProbe), InternetAddress('255.255.255.255'), kDiscoveryPort);
    return await completer.future;
  } finally {
    timer.cancel();
    socket.close();
  }
}
