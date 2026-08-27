/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 官方中转服务器（独立可执行程序）
/// ════════════════════════════════════════════════════════════════════════
///
/// 用途：把「电台 / 一起听 / 体素联机」的跨公网扇出集中到官方一台机子，
/// 客户端零配置直连（见 kDefaultRelayUrl）。
///
/// 部署：`dart compile exe bin/relay_server.dart -o relay_server.exe`，
/// 然后让该 exe 常驻监听 8092 端口（Cloudflare 隧道转发到此）。
///
/// 运行：`relay_server.exe`（默认端口 8092）
///       `relay_server.exe --port 9000`（指定端口）
///
/// 协议（与客户端 NetNode.relay() 对齐）：
///   - 首帧：{ctl:'join', room, name, host}  → 分配 peerId，回 {ctl:'ready', id}
///   - 同房间加入/离开：广播 {ctl:'peerJoin'/'peerLeave', id}
///   - 普通消息（NetMessage 信封，无 ctl）：msg.to 存在则定向投递，否则按房间扇出（不回发发送者）
///   - 错误：{ctl:'error', msg}（room required / room full / 房间不存在）
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ── 协议（内联自 xingli_music lib/services/net/net_message.dart）────────────
// 中继服务器仅需转发信封，无需感知每种消息类型，故只保留类型索引与编解码。

/// 消息类型索引（与客户端 NetMsgType 枚举一一对应，勿重排）。
enum _NetMsgType {
  hello,
  welcome,
  peerJoin,
  peerLeave,
  transform,
  edit,
  vitals,
  chat,
  listenState,
  requestListen,
  bye,
  ping,
  editSnapshot,
  requestEditSnapshot,
  orderSubmit,
  orderQueue,
  orderDecision,
}

/// 一条网络消息（JSON 信封：t=类型 f=发送方 to=接收方(可选) p=负载）。
class NetMessage {
  NetMessage({
    required this.type,
    required this.from,
    this.to,
    required this.payload,
  });

  final _NetMsgType type;
  final String from;
  final String? to;
  final Map<String, dynamic> payload;

  factory NetMessage.fromJson(Map<String, dynamic> j) => NetMessage(
        type: _NetMsgType.values[(j['t'] as int?) ?? 0],
        from: j['f'] as String? ?? '',
        to: j['to'] as String?,
        payload:
            (j['p'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': type.index,
        'f': from,
        if (to != null) 'to': to,
        'p': payload,
      };

  String encode() => jsonEncode(toJson());

  static NetMessage decode(String s) =>
      NetMessage.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// 单房间人数上限（避免房间被刷爆）。
const int kMaxRoomMembers = 32;

/// 一个已建立连接的客户端。
class _Client {
  _Client({
    required this.ws,
    required this.id,
    required this.room,
    required this.name,
  });

  final WebSocket ws;
  final String id;
  final String room;
  final String name;
}

final Map<String, WebSocket> _clientsById = <String, WebSocket>{}; // peerId → ws
final Map<String, _Client> _clientsByWs = <String, _Client>{}; // ws hash → client
final Map<String, int> _roomCount = <String, int>{}; // room → 人数

String _genId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
    '${DateTime.now().millisecondsSinceEpoch % 0xffff}';

void _sendRaw(WebSocket ws, Object payload) {
  try {
    ws.add(payload is String ? payload : jsonEncode(payload));
  } catch (_) {}
}

void _broadcastToRoom(
  String room,
  Object payload, {
  String? exceptId,
}) {
  for (final _Client c in _clientsByWs.values) {
    if (c.room != room) continue;
    if (exceptId != null && c.id == exceptId) continue;
    _sendRaw(c.ws, payload);
  }
}

void _handleClient(_Client client, String data) {
  final Object? decoded = tryJsonDecode(data);
  if (decoded is! Map<String, dynamic>) return; // 非法包忽略

  // ── 控制帧（join / 各种 ctl）───────────────────────────────────────
  if (decoded['ctl'] != null) {
    switch (decoded['ctl']) {
      case 'join':
        _onJoin(client, decoded);
        return;
      default:
        return; // 客户端不应发其它 ctl
    }
  }

  // ── 普通消息：NetMessage 信封 ───────────────────────────────────────
  final NetMessage msg;
  try {
    msg = NetMessage.decode(data);
  } catch (_) {
    return;
  }
  if (msg.from.isEmpty) return;

  // 定向投递（msg.to 存在且在线）
  final String? to = msg.to;
  if (to != null && to.isNotEmpty) {
    final WebSocket? target = _clientsById[to];
    if (target != null) _sendRaw(target, msg.encode());
    return;
  }

  // 扇出给同房间其它成员（不回发发送者）
  final String room = client.room;
  if (!_roomCount.containsKey(room)) return;
  _broadcastToRoom(room, msg.encode(), exceptId: msg.from);
}

void _onJoin(_Client client, Map<String, dynamic> join) {
  final String room = (join['room'] as String?)?.trim() ?? '';
  final String name = (join['name'] as String?)?.trim() ?? '';

  if (room.isEmpty) {
    _error(client, 'room required');
    return;
  }

  final int count = _roomCount[room] ?? 0;
  if (count >= kMaxRoomMembers) {
    _error(client, 'room full');
    return;
  }

  // 分配 id，绑定房间
  final String id = _genId();
  _clientsById[id] = client.ws;
  _roomCount[room] = count + 1;
  // 用最新对象重写（保留 room/name）
  final _Client bound = _Client(
    ws: client.ws,
    id: id,
    room: room,
    name: name,
  );
  _clientsByWs[client.ws.hashCode.toString()] = bound;

  // 回 ready
  _sendRaw(client.ws, <String, dynamic>{'ctl': 'ready', 'id': id});

  // 广播 peerJoin 给同房间其它成员（不含新成员自身）
  _broadcastToRoom(room, <String, dynamic>{'ctl': 'peerJoin', 'id': id});
}

void _error(_Client client, String msg) {
  _sendRaw(client.ws, <String, dynamic>{'ctl': 'error', 'msg': msg});
}

void _removeClient(_Client client) {
  _clientsById.remove(client.id);
  _clientsByWs.remove(client.ws.hashCode.toString());
  final int? count = _roomCount[client.room];
  if (count != null) {
    if (count <= 1) {
      _roomCount.remove(client.room);
    } else {
      _roomCount[client.room] = count - 1;
    }
  }
  // 广播 peerLeave 给同房间其它成员
  _broadcastToRoom(
    client.room,
    <String, dynamic>{'ctl': 'peerLeave', 'id': client.id},
  );
}

Object? tryJsonDecode(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

Future<void> _listen(int port) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.anyIPv4,
    port,
  );
  stdout.writeln('[relay] 监听 ws://0.0.0.0:$port/ws  （Ctrl+C 退出）');

  server.listen((HttpRequest req) async {
    if (req.uri.path != '/ws' && req.uri.path != '/') {
      try {
        await req.response.close();
      } catch (_) {}
      return;
    }
    try {
      final WebSocket ws = await WebSocketTransformer.upgrade(req);
      final String wsKey = ws.hashCode.toString();
      final _Client client = _Client(ws: ws, id: '', room: '', name: '');
      _clientsByWs[wsKey] = client;

      ws.listen(
        (dynamic data) {
          if (data is! String) return;
          _handleClient(_clientsByWs[wsKey] ?? client, data);
        },
        onDone: () {
          final _Client? c = _clientsByWs[wsKey];
          if (c != null) _removeClient(c);
        },
        onError: (_) {
          final _Client? c = _clientsByWs[wsKey];
          if (c != null) _removeClient(c);
        },
      );
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  });
}

Future<void> main(List<String> args) async {
  int port = 8092;
  for (int i = 0; i < args.length - 1; i++) {
    if (args[i] == '--port') {
      final int? p = int.tryParse(args[i + 1]);
      if (p != null && p > 0) port = p;
    }
  }
  await _listen(port);
}
