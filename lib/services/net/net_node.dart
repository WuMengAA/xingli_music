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
    this.relayMode = false,
    this.room,
  }) : _events = StreamController<NetEvent>.broadcast();

  final bool isHost;
  String localId;
  final HttpServer? server;
  final WebSocket? socket;
  final Map<String, WebSocket> peers; // 仅主机：peerId → socket
  final bool relayMode; // 中继模式：以客户端身份连中转，由服务器扇出
  final String? room; // 中继模式：所在房间号
  final StreamController<NetEvent> _events;
  Stream<NetEvent> get events => _events.stream;
  Completer<void>? _readyCompleter;

  /// 中转模式：等待服务器回 `ready`（分配 peerId）。超时由调用方处理。
  Future<void> get ready => (_readyCompleter ??= Completer<void>()).future;

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

  /// 中转模式：以客户端身份连接中转服务器，登记进入 [room]。
  ///
  /// 服务器随后通过控制帧(`ctl`)回报 peerJoin/peerLeave/ready；游戏帧（无 `ctl`）
  /// 原样转发为 [NetMessageEvent]，使既有会话逻辑无需改动即可跨公网运行。
  /// [isHostGame] 表示该端在游戏层的角色（房主/加入者），不影响传输（二者均连中转）。
  static Future<NetNode> relay(
    String relayUrl,
    String room,
    String name, {
    required bool isHostGame,
  }) async {
    final WebSocket ws = await WebSocket.connect(relayUrl);
    final NetNode node = NetNode._(
      isHost: false,
      localId: '',
      socket: ws,
      peers: <String, WebSocket>{},
      relayMode: true,
      room: room,
    );
    node._readyCompleter = Completer<void>();
    ws.listen(
      (dynamic data) {
        try {
          final String s = data as String;
          final Map<String, dynamic> c =
              jsonDecode(s) as Map<String, dynamic>;
          if (c['ctl'] != null) {
            switch (c['ctl']) {
              case 'ready':
                node.localId = (c['id'] as String?) ?? '';
                node._readyCompleter?.complete();
                return;
              case 'peerJoin':
                final String id = (c['id'] as String?) ?? '';
                if (id.isNotEmpty) node._events.add(NetPeerConnected(id));
                return;
              case 'peerLeave':
                final String id = (c['id'] as String?) ?? '';
                if (id.isNotEmpty) node._events.add(NetPeerDisconnected(id));
                return;
              default:
                return;
            }
          }
          final NetMessage msg = NetMessage.decode(s);
          node._events.add(NetMessageEvent(msg.from, msg));
        } catch (_) {
          // 非法包忽略
        }
      },
      onDone: () => node._events.add(const NetClosed()),
      onError: (_) => node._events.add(const NetClosed()),
    );
    // 首帧：向中转服务器登记房间（host=是否游戏房主，仅用于展示/统计）。
    ws.add(jsonEncode(<String, dynamic>{
      'ctl': 'join',
      'room': room,
      'name': name,
      'host': isHostGame,
    }));
    return node;
  }

  void _sendRaw(WebSocket ws, NetMessage msg) {
    try {
      ws.add(msg.encode());
    } catch (_) {}
  }

  /// 主机：广播给所有成员（除 [exceptId]）；客户端：发给主机。
  /// 中继模式：单连接写回中转服务器，由服务器按房间扇出给其他人（[exceptId] 被忽略，
  /// 因服务器本就不回送发送者；自环的 peerJoin 由上层按 localId 过滤）。
  void send(NetMessage msg, {String? exceptId}) {
    if (relayMode) {
      if (socket != null) _sendRaw(socket!, msg);
      return;
    }
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
  /// 中继模式：标记 `to`，由服务器定向投递到该 peerId。
  void sendTo(String peerId, NetMessage msg) {
    if (relayMode) {
      if (socket != null) _sendRaw(socket!, msg.withTo(peerId));
      return;
    }
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
