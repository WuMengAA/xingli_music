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
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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

// ═══ cl08：REST 内容 API（App 与 ClassIsland 组件联动）═══════════════

/// 内容文件目录（相对启动目录，JSON 可热编辑即时生效）。
const String _kContentDir = 'content';

Future<Map<String, dynamic>?> _loadContent(String key) async {
  try {
    final File f = File('$_kContentDir/$key.json');
    if (!f.existsSync()) return null;
    final Object? v = jsonDecode(await f.readAsString());
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}

// ═══ cl11：能力清单（服务端全量声明，客户端按清单选配）══════════════════
//
// 设计约定：服务端是「能力中心」，客户端不内置任何音源逻辑，只按本清单
// 渲染入口。新增一个音源 = 在此登记 + 实现路由，**客户端零发版**。
//
// 凭据归属 `credentialOwner`：
// - `client`：凭据留客户端加密存储，随请求带上；服务端只做无状态协议适配，
//   用完即弃、不落盘、不记日志（服务端不持账号资产，是本项目的安全边界）。
// - `server`：服务端代持（仅自托管场景可选）。
// - `none`：公开能力，无需凭据。

/// 能力已实现可对外服务。
const String kCapStatusReady = 'ready';

/// 服务端已认知该能力但尚未实现，客户端应展示为「未启用」而非隐藏。
const String kCapStatusPlanned = 'planned';

/// 构造单条能力声明。[kind] 与客户端 `CapabilityKind` 取值对齐：
/// search / playlist / recommend / curated / radio / local。
Map<String, dynamic> _cap(
  String id,
  String source,
  String kind,
  String title, {
  required bool enabled,
  String? endpoint,
  bool requiresCredential = false,
  String credentialOwner = 'none',
}) =>
    <String, dynamic>{
      'id': id,
      'source': source,
      'kind': kind,
      'title': title,
      if (endpoint != null) 'endpoint': endpoint,
      'requiresCredential': requiresCredential,
      'credentialOwner': credentialOwner,
      'enabled': enabled,
      'status': enabled ? kCapStatusReady : kCapStatusPlanned,
    };

/// 组装能力清单。
///
/// 内容类能力的 `enabled` 按内容文件是否实际存在判定——运营在 `content/`
/// 里增删 JSON 即刻生效，不必改代码。
Future<Map<String, dynamic>> _capabilities() async {
  final bool hasScenes = File('$_kContentDir/scenes.json').existsSync();
  final bool hasPlaylists = File('$_kContentDir/playlists.json').existsSync();
  final bool hasNotices = File('$_kContentDir/notices.json').existsSync();

  final List<Map<String, dynamic>> caps = <Map<String, dynamic>>[
    _cap(
      'content.scenes',
      'content',
      'curated',
      '场景包',
      enabled: hasScenes,
      endpoint: '/api/content/scenes',
    ),
    _cap(
      'content.playlists',
      'content',
      'curated',
      '精选歌单',
      enabled: hasPlaylists,
      endpoint: '/api/content/playlists',
    ),
    _cap(
      'content.notices',
      'content',
      'curated',
      '公告',
      enabled: hasNotices,
      endpoint: '/api/content/notices',
    ),
    _cap(
      'content.random',
      'content',
      'curated',
      '随机推荐',
      enabled: hasScenes || hasPlaylists,
      endpoint: '/api/content/random',
    ),
    // ── 客户端执行：凭据留设备，服务端只登记、不代理 ─────────────────
    // 这类能力刻意**不带 endpoint**——实现不在服务端，而在客户端本地已有的
    // 音源链路（网易云的 weapi 加解密、B站的 WBI 签名，都在端上完成）。
    // 若改由服务端代理，用户的登录 cookie 就必须出网，与「服务端不持账号
    // 资产」相悖。服务端这里只做一件事：声明该能力可用，由客户端自行选配
    // 与执行。
    // 判定依据是「客户端是否真的具备实现」而非「服务端能否实现」——
    // 2026-08-29 核对：netease.search/recommend、bilibili.search 客户端
    // 8 月即已落地，此前误标为 planned，属于清单与事实不符。
    _cap(
      'netease.recommend',
      'netease',
      'recommend',
      '网易云 · 每日推荐',
      enabled: true,
      requiresCredential: true,
      credentialOwner: 'client',
    ),
    _cap(
      'netease.search',
      'netease',
      'search',
      '网易云 · 搜索',
      enabled: true,
      requiresCredential: true,
      credentialOwner: 'client',
    ),
    _cap(
      'bilibili.search',
      'bilibili',
      'search',
      'B站 · 搜索',
      // 实测（2026-08-29）：B站 WBI 搜索**不登录也能返回数据**（code=0、
      // 20 条结果、无需 cookie），故不标 requiresCredential。这与网易云不同
      // ——网易云的搜索/推荐未登录一律拿不到内容。
      enabled: true,
    ),
    // ── 规划中：需用户自登录，凭据留客户端 ──────────────────────────
    // 尚未在任何一侧落地：客户端 netease_source 的歌单链路明确标注「后续以
    // PagedMusicSource 补充」（getTracks 当前刻意返回空），服务端也未实现，
    // 故保持 planned——UI 应展示为「未启用」而非隐藏，让用户知道有这条路。
    _cap(
      'netease.playlist',
      'netease',
      'playlist',
      '网易云 · 我的歌单',
      enabled: false,
      requiresCredential: true,
      credentialOwner: 'client',
    ),
  ];

  return <String, dynamic>{
    'ok': true,
    'server': <String, dynamic>{
      'service': 'xingli-relay',
      'version': 'cl12',
      'mode': 'official',
      'tls': _tlsEnabled,
      'ts': DateTime.now().toIso8601String(),
    },
    'capabilities': caps,
  };
}

/// 随机返回一条内容（场景或歌单），供 ClassIsland 组件 / App 轮换展示。
Future<Map<String, dynamic>?> _randomContent() async {
  final Map<String, dynamic>? scenes = await _loadContent('scenes');
  final Map<String, dynamic>? playlists = await _loadContent('playlists');
  final List<dynamic> pool = <dynamic>[
    ...(scenes?['scenes'] as List<dynamic>? ?? const <dynamic>[]),
    ...(playlists?['playlists'] as List<dynamic>? ?? const <dynamic>[]),
  ];
  if (pool.isEmpty) return null;
  final Object? pick = pool[_random.nextInt(pool.length)];
  if (pick is! Map<String, dynamic>) return null;
  return <String, dynamic>{
    'type': pick.containsKey('visual') ? 'scene' : 'playlist',
    'title': pick['name'] ?? '',
    'subtitle': pick['soundscape'] ?? pick['desc'] ?? '',
    'accent': (pick['visual'] as Map<String, dynamic>?)?['accent'] ?? '#9B7BFF',
  };
}

final Random _random = Random();

Future<void> _handleApi(HttpRequest req) async {
  final String path = req.uri.path;
  final String method = req.method;
  Map<String, dynamic>? payload;
  int status = 200;
  switch (path) {
    case '/api/health':
      payload = <String, dynamic>{
        'ok': true,
        'service': 'xingli-relay',
        'version': 'cl12',
        'tls': _tlsEnabled,
        'ts': DateTime.now().toIso8601String(),
      };
    case '/api/capabilities':
      payload = await _capabilities();
    case '/api/content/scenes':
      payload = await _loadContent('scenes');
      if (payload == null) status = 404;
    case '/api/content/playlists':
      payload = await _loadContent('playlists');
      if (payload == null) status = 404;
    case '/api/content/notices':
      payload = await _loadContent('notices');
      if (payload == null) status = 404;
    case '/api/content/random':
      payload = await _randomContent();
      if (payload == null) status = 404;
    case '/api/auth/register':
      if (method != 'POST') {
        status = 405;
        payload = <String, dynamic>{'error': 'method not allowed'};
        break;
      }
      payload = await _authRegister(req);
      if (payload['ok'] != true) status = 400;
    case '/api/auth/login':
      if (method != 'POST') {
        status = 405;
        payload = <String, dynamic>{'error': 'method not allowed'};
        break;
      }
      payload = await _authLogin(req);
      if (payload['ok'] != true) status = 401;
    case '/api/auth/me':
      payload = await _authMe(req);
      if (payload['ok'] != true) status = 401;
    case '/api/auth/logout':
      payload = await _authLogout(req);
    default:
      status = 404;
      payload = <String, dynamic>{'error': 'not found'};
  }
  try {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(payload));
    await req.response.close();
  } catch (_) {}
}

// ═══ cl10：用户系统（注册/登录/token）+ 可选 TLS ═════════════════════

/// 服务端签名密钥（启动生成并持久化到 relay_server.secret，绝不随代码分发）。
String? _serverSecret;

/// 是否以 TLS 模式监听（health 接口上报）。
bool _tlsEnabled = false;

/// 用户数据目录（每用户一个 JSON：salt/verifier 不存明文密码）。
const String _kUsersDir = 'users';
const int _kTokenTtlDays = 30;
const int _kPbkdf2Iterations = 30000;

/// 读/生成服务端密钥。失败返回 null（main 据此退出）。
Future<String?> _loadServerSecret() async {
  const String f = 'relay_server.secret';
  try {
    final File file = File(f);
    if (await file.exists()) {
      final String s = (await file.readAsString()).trim();
      if (s.isNotEmpty) return s;
    }
    final String gen = _randomBytes(32)
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await file.writeAsString(gen);
    return gen;
  } catch (_) {
    return null;
  }
}

/// 随机字节（密钥/盐用）。
Uint8List _randomBytes(int n) {
  final Uint8List b = Uint8List(n);
  for (int i = 0; i < n; i++) b[i] = _random.nextInt(256);
  return b;
}

/// 密码派生：PBKDF2-HMAC-SHA256，输出 base64（单 block，与 SecureBox 同思路）。
String _pbkdf2(String password, String salt,
    {int iterations = _kPbkdf2Iterations}) {
  final Hmac prf = Hmac(sha256, utf8.encode(password));
  List<int> u = prf.convert(<int>[...utf8.encode(salt), 0, 0, 0, 1]).bytes;
  final List<int> t = List<int>.from(u);
  for (int i = 1; i < iterations; i++) {
    u = prf.convert(u).bytes;
    for (int j = 0; j < t.length; j++) t[j] ^= u[j];
  }
  return base64Encode(Uint8List.fromList(t));
}

/// base64url（去填充）。
String _b64url(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');

String _b64urlDecode(String s) => utf8.decode(base64Url.decode(
      s + List<String>.filled((4 - s.length % 4) % 4, '=').join(),
    ));

/// 签发 HMAC token（类 JWT 三段式，HS256）。
String _signToken(String uid) {
  final String h =
      _b64url(jsonEncode(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'}));
  final String p = _b64url(jsonEncode(<String, dynamic>{
    'uid': uid,
    'exp': DateTime.now()
        .add(const Duration(days: _kTokenTtlDays))
        .millisecondsSinceEpoch,
  }));
  final String sig = base64Url
      .encode(Hmac(sha256, utf8.encode(_serverSecret!))
          .convert(utf8.encode('$h.$p'))
          .bytes)
      .replaceAll('=', '');
  return '$h.$p.$sig';
}

/// 校验 token，返回 payload（含 uid/exp）或 null（伪造/过期）。
Map<String, dynamic>? _verifyToken(String token) {
  final List<String> parts = token.split('.');
  if (parts.length != 3) return null;
  final String expect = base64Url
      .encode(Hmac(sha256, utf8.encode(_serverSecret!))
          .convert(utf8.encode('${parts[0]}.${parts[1]}'))
          .bytes)
      .replaceAll('=', '');
  if (expect != parts[2]) return null;
  try {
    final Map<String, dynamic> payload =
        jsonDecode(_b64urlDecode(parts[1])) as Map<String, dynamic>;
    if ((payload['exp'] as int? ?? 0) < DateTime.now().millisecondsSinceEpoch) {
      return null;
    }
    return payload;
  } catch (_) {
    return null;
  }
}

/// 读 POST 的 JSON body（失败返回 null）。
Future<Map<String, dynamic>?> _readJsonBody(HttpRequest req) async {
  try {
    final String body = await utf8.decoder.bind(req).join();
    if (body.isEmpty) return null;
    final Object? v = jsonDecode(body);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}

/// 从 Authorization 头取 Bearer token。
String? _bearer(HttpRequest req) {
  final String? auth = req.headers.value('authorization');
  if (auth == null) return null;
  final RegExpMatch? m =
      RegExp(r'^Bearer\s+(.+)$', caseSensitive: false).firstMatch(auth);
  return m?.group(1);
}

/// 用户公开档案（剔除 salt/verifier）。
Map<String, dynamic> _publicUser(Map<String, dynamic> rec) =>
    <String, dynamic>{
      'username': rec['username'],
      'prefs': rec['prefs'] ?? <String, dynamic>{},
      'favorites': rec['favorites'] ?? <dynamic>[],
      'createdAt': rec['createdAt'],
    };

Future<Map<String, dynamic>> _authRegister(HttpRequest req) async {
  final Map<String, dynamic>? body = await _readJsonBody(req);
  if (body == null) return <String, dynamic>{'error': 'invalid body'};
  final String username = (body['username'] as String? ?? '').trim();
  final String password = (body['password'] as String? ?? '');
  if (username.length < 3 || username.length > 24) {
    return <String, dynamic>{'error': '用户名需 3-24 字符'};
  }
  if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(username)) {
    return <String, dynamic>{'error': '用户名仅限字母数字 _ -'};
  }
  if (password.length < 6) return <String, dynamic>{'error': '密码至少 6 位'};
  final File f = File('$_kUsersDir/$username.json');
  if (await f.exists()) return <String, dynamic>{'error': '用户名已存在'};
  final String salt = base64Encode(_randomBytes(16));
  final Map<String, dynamic> rec = <String, dynamic>{
    'username': username,
    'salt': salt,
    'verifier': _pbkdf2(password, salt),
    'prefs': <String, dynamic>{},
    'favorites': <dynamic>[],
    'createdAt': DateTime.now().toIso8601String(),
  };
  try {
    await Directory(_kUsersDir).create(recursive: true);
    await f.writeAsString(jsonEncode(rec));
  } catch (_) {
    return <String, dynamic>{'error': 'server error'};
  }
  return <String, dynamic>{
    'ok': true,
    'token': _signToken(username),
    'user': _publicUser(rec),
  };
}

Future<Map<String, dynamic>> _authLogin(HttpRequest req) async {
  final Map<String, dynamic>? body = await _readJsonBody(req);
  if (body == null) return <String, dynamic>{'error': 'invalid body'};
  final String username = (body['username'] as String? ?? '').trim();
  final String password = (body['password'] as String? ?? '');
  final File f = File('$_kUsersDir/$username.json');
  if (!await f.exists()) return <String, dynamic>{'error': '用户名或密码错误'};
  Map<String, dynamic> rec;
  try {
    rec = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return <String, dynamic>{'error': 'server error'};
  }
  final String expect = _pbkdf2(password, rec['salt'] as String? ?? '');
  if (expect != rec['verifier']) {
    return <String, dynamic>{'error': '用户名或密码错误'};
  }
  return <String, dynamic>{
    'ok': true,
    'token': _signToken(username),
    'user': _publicUser(rec),
  };
}

Future<Map<String, dynamic>> _authMe(HttpRequest req) async {
  final String? token = _bearer(req);
  if (token == null) return <String, dynamic>{'error': 'unauthorized'};
  final Map<String, dynamic>? payload = _verifyToken(token);
  if (payload == null) return <String, dynamic>{'error': 'unauthorized'};
  final File f = File('$_kUsersDir/${payload['uid']}.json');
  if (!await f.exists()) return <String, dynamic>{'error': 'unauthorized'};
  try {
    final Map<String, dynamic> rec =
        jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return <String, dynamic>{'ok': true, 'user': _publicUser(rec)};
  } catch (_) {
    return <String, dynamic>{'error': 'server error'};
  }
}

Future<Map<String, dynamic>> _authLogout(HttpRequest req) async {
  // 无状态 token：客户端丢弃即登出；此处预留吊销位点。
  return <String, dynamic>{'ok': true};
}

Future<void> _listen(int port, {String? certPath, String? keyPath}) async {
  final HttpServer server;
  if (certPath != null && keyPath != null) {
    final SecurityContext ctx = SecurityContext()
      ..useCertificateChain(certPath)
      ..usePrivateKey(keyPath);
    server = await HttpServer.bindSecure(InternetAddress.anyIPv4, port, ctx);
    _tlsEnabled = true;
    stdout.writeln('[relay] 监听 https://0.0.0.0:$port/ws  + /api/*  (TLS)');
  } else {
    server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    stdout.writeln('[relay] 监听 ws://0.0.0.0:$port/ws  + /api/*  （明文，Ctrl+C 退出）');
  }

  server.listen((HttpRequest req) async {
    // cl08：REST 内容 API —— 星璃音乐 App 与 ClassIsland 组件共用。
    // cl10：放行所有方法的 /api/*（含 POST 认证端点）。
    if (req.uri.path.startsWith('/api/')) {
      await _handleApi(req);
      return;
    }
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
  String? cert, key;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--port' && i + 1 < args.length) {
      final int? p = int.tryParse(args[i + 1]);
      if (p != null && p > 0) port = p;
    } else if (args[i] == '--cert' && i + 1 < args.length) {
      cert = args[++i];
    } else if (args[i] == '--key' && i + 1 < args.length) {
      key = args[++i];
    }
  }
  final String? secret = await _loadServerSecret();
  if (secret == null) {
    stderr.writeln('[relay] 无法初始化服务端密钥，退出');
    return;
  }
  _serverSecret = secret;
  await _listen(port, certPath: cert, keyPath: key);
}
