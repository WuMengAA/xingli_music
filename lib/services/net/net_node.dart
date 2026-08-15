/// ════════════════════════════════════════════════════════════════════════
/// 联机传输层（G9）：基于 dart:io 的 WebSocket，零外部依赖。
/// ════════════════════════════════════════════════════════════════════════
///
/// - 主机：HttpServer 监听 + WebSocketTransformer 升级，维护多客户端连接；
/// - 客户端：WebSocket.connect 连主机。
/// 消息统一 JSON 信封（见 [NetMessage]）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'net_message.dart';

/// 默认联机端口（与日志/发现服务区分）。
const int kNetDefaultPort = 8765;

/// 传输层事件（连接 / 断开 / 消息）。
class NetEvent {
  const NetEvent();
}

class NetPeerConnected extends NetEvent {
  const NetPeerConnected(this.peerId);
  final String peerId;
}

class NetPeerDisconnected extends NetEvent {
  const NetPeerDisconnected(this.peerId);
  final String peerId;
}

class NetMessageEvent extends NetEvent {
  const NetMessageEvent(this.from, this.message);
  final String from;
  final NetMessage message;
}

class NetClosed extends NetEvent {
  const NetClosed();
}

String _genId() {
  final math.Random r = math.Random();
  final int t = DateTime.now().microsecondsSinceEpoch;
  return '${(t & 0xffffff).toRadixString(16)}-${r.nextInt(1 << 20).toRadixString(16)}';
}

/// WebSocket 传输节点：主机或客户端。
class NetNode {
  NetNode._({
    required this.isHost,
    required this.localId,
    this.server,
    this.socket,
    required this.peers,
  }) : _events = StreamController<NetEvent>.broadcast();

  final bool isHost;
  final String localId;
  final HttpServer? server;
  final WebSocket? socket;
  final Map<String, WebSocket> peers; // 仅主机：peerId → socket
  final StreamController<NetEvent> _events;
  Stream<NetEvent> get events => _events.stream;

  static Future<NetNode> host({int port = kNetDefaultPort}) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
    );
    final NetNode node = NetNode._(
      isHost: true,
      localId: _genId(),
      server: server,
      peers: <String, WebSocket>{},
    );
    server.listen((HttpRequest req) async {
      if (req.uri.path == '/ws' || req.uri.path == '/') {
        try {
          final WebSocket ws = await WebSocketTransformer.upgrade(req);
          final String peerId = _genId();
          node.peers[peerId] = ws;
          node._events.add(NetPeerConnected(peerId));
          ws.listen(
            (dynamic data) {
              try {
                final NetMessage msg = NetMessage.decode(data as String);
                node._events.add(NetMessageEvent(msg.from, msg));
              } catch (_) {
                // 非法包忽略
              }
            },
            onDone: () {
              node.peers.remove(peerId);
              node._events.add(NetPeerDisconnected(peerId));
            },
            onError: (_) {
              node.peers.remove(peerId);
              node._events.add(NetPeerDisconnected(peerId));
            },
          );
        } catch (_) {
          try {
            await req.response.close();
          } catch (_) {}
        }
      } else {
        try {
          await req.response.close();
        } catch (_) {}
      }
    });
    return node;
  }

  static Future<NetNode> connect(String host, int port) async {
    final WebSocket ws = await WebSocket.connect('ws://$host:$port/ws');
    final NetNode node = NetNode._(
      isHost: false,
      localId: _genId(),
      socket: ws,
      peers: <String, WebSocket>{},
    );
    ws.listen(
      (dynamic data) {
        try {
          final NetMessage msg = NetMessage.decode(data as String);
          node._events.add(NetMessageEvent(msg.from, msg));
        } catch (_) {}
      },
      onDone: () => node._events.add(const NetClosed()),
      onError: (_) => node._events.add(const NetClosed()),
    );
    return node;
  }

  void _sendRaw(WebSocket ws, NetMessage msg) {
    try {
      ws.add(msg.encode());
    } catch (_) {}
  }

  /// 主机：广播给所有成员（除 [exceptId]）；客户端：发给主机。
  void send(NetMessage msg, {String? exceptId}) {
    if (isHost) {
      for (final MapEntry<String, WebSocket> e in peers.entries) {
        if (e.key == exceptId) continue;
        _sendRaw(e.value, msg);
      }
    } else {
      if (socket != null) _sendRaw(socket!, msg);
    }
  }

  /// 仅主机：发给指定成员。
  void sendTo(String peerId, NetMessage msg) {
    final WebSocket? ws = peers[peerId];
    if (ws != null) _sendRaw(ws, msg);
  }

  Future<void> close() async {
    for (final WebSocket ws in peers.values) {
      try {
        await ws.close();
      } catch (_) {}
    }
    try {
      await socket?.close();
    } catch (_) {}
    try {
      await server?.close(force: true);
    } catch (_) {}
  }
}
