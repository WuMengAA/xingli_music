/// ════════════════════════════════════════════════════════════════════════
/// 局域网联机发现（G9）：零依赖 UDP 广播，复用 log_discovery 思路。
/// ════════════════════════════════════════════════════════════════════════
///
/// 主机：在固定发现端口监听 `XINGLI_WS_DISCOVER`，收到后回
///       `XINGLI_WS_HOST <ws端口> <昵称>`，让同网段客户端免填 IP。
/// 客户端：向 `255.255.255.255:<发现端口>` 广播探测，收集主机应答。
///
/// 与日志发现（UDP 8766）区分，本服务用 8767，避免互相干扰。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UDP 发现端口（区别于日志服务的 8766）。
const int kNetDiscoveryPort = 8767;

/// 探测消息（客户端广播）。
const String kWsProbe = 'XINGLI_WS_DISCOVER';

/// 主机应答前缀：`XINGLI_WS_HOST <ws端口> <昵称>`。
const String kWsHostPrefix = 'XINGLI_WS_HOST';

/// 一台被发现的主机。
class LanHost {
  const LanHost({
    required this.ip,
    required this.port,
    required this.name,
  });

  final String ip;
  final int port;
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanHost &&
          other.ip == ip &&
          other.port == port &&
          other.name == name;

  @override
  int get hashCode => Object.hash(ip, port, name);

  @override
  String toString() => 'LanHost($ip:$port "$name")';
}

/// 局域网联机发现。
class LanDiscovery {
  LanDiscovery._();

  /// 扫描同网段内的联机主机；[timeout] 内无新响应即结束（自动关闭 socket）。
  ///
  /// 返回广播流，可多次监听；去重（同一 ip:port 只发一次）。
  static Future<Stream<LanHost>> scan({
    int discoveryPort = kNetDiscoveryPort,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    late final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
    } catch (_) {
      return const Stream<LanHost>.empty();
    }

    final StreamController<LanHost> ctrl =
        StreamController<LanHost>.broadcast(onCancel: () => socket.close());
    final Set<String> seen = <String>{};

    final Timer timer = Timer(timeout, () => ctrl.close());

    socket.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;
      final Datagram? dg = socket.receive();
      if (dg == null) return;
      final String text = String.fromCharCodes(dg.data).trim();
      if (!text.startsWith(kWsHostPrefix)) return;
      final List<String> parts = text.split(RegExp(r'\s+'));
      if (parts.length < 3) return;
      final int? wsPort = int.tryParse(parts[1]);
      if (wsPort == null) return;
      final String name = parts.skip(2).join(' ').trim();
      final String key = '${dg.address.address}:$wsPort';
      if (seen.add(key)) {
        ctrl.add(LanHost(
          ip: dg.address.address,
          port: wsPort,
          name: name.isEmpty ? '房主' : name,
        ));
      }
    });

    try {
      socket.send(
        utf8.encode(kWsProbe),
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
    } catch (_) {
      // 广播失败（无网络权限）即时结束。
      ctrl.close();
    }

    // 超时后确保关闭。
    unawaited(timerFuture(timeout).then((_) => socket.close()).catchError((_) {}));

    return ctrl.stream;
  }

  /// 主机侧：在发现端口监听探测并应答，使客户端免填 IP。
  ///
  /// 返回保持打开的 socket（[NetSessionNotifier.leave] 时 [close]），
  /// 失败（端口被占等）返回 null —— 局域网发现为**尽力而为**，不应阻断主持。
  static Future<RawDatagramSocket?> startBeacon({
    required int port,
    required String name,
  }) async {
    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kNetDiscoveryPort,
      );
      socket.broadcastEnabled = true;
    } catch (_) {
      return null; // 发现端口被占：不致命，主机仍可通过 IP 直连
    }

    socket.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;
      final Datagram? dg = socket.receive();
      if (dg == null) return;
      final String text = String.fromCharCodes(dg.data).trim();
      if (text != kWsProbe) return;
      try {
        socket.send(
          utf8.encode('$kWsHostPrefix $port $name'),
          dg.address,
          dg.port,
        );
      } catch (_) {}
    });

    return socket;
  }
}

/// 把 Timer 包装成 Future，便于在超时后清理资源（避免直接依赖 timer 是否激活）。
Future<void> timerFuture(Duration duration) => Future<void>.delayed(duration);
