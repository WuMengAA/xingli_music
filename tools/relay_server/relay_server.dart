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
///   - 首帧：{ctl:'join', room, name, host, public, mode, capacity, password}
///     → 分配 peerId，回 {ctl:'ready', id}
///     · host=true 时为创建：携带 public(公开/私密)、mode(campus/listen)、
///       capacity(人数上限)、password(私密房间密码) 元数据，登记房间。
///     · host=false 时为加入：私密房间须带正确 password，公开房间可不带。
///   - 同房间加入/离开：广播 {ctl:'peerJoin'/'peerLeave', id}
///   - 普通消息（NetMessage 信封，无 ctl）：msg.to 存在则定向投递，否则按房间扇出（不回发发送者）
///   - 错误：{ctl:'error', msg}（room required / room full / 房间不存在 / 密码错误）
///   - REST：GET /api/rooms 返回公开房间列表（供大厅展示，含模式/容量/人数/房主）
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

/// 默认房间人数上限（未显式指定时兜底；创建时按模式计算）。
const int kMaxRoomMembers = 100;

/// 房间模式：校园广播（默认 100 人）/ 一起听（2-10 人）。
class _RoomMode {
  static const String campus = 'campus'; // 校园广播：上限 100
  static const String listen = 'listen'; // 一起听：上限 2-10
}

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

/// 房间元数据（cl15：公开/私密 + 模式 + 容量 + 密码）。
/// cl16：电台自动化——房主保活（autoDJ/ttl）与归主（hostId）字段。
class _RoomMeta {
  _RoomMeta({
    required this.code,
    required this.name,
    required this.mode,
    required this.capacity,
    required this.isPublic,
    this.password,
    this.hostId,
    this.autoDJ = false,
    this.ttlSeconds = 0,
  });

  final String code; // 房间号（公开房间列表展示）
  final String name; // 房主昵称
  final String mode; // campus / listen
  final int capacity; // 人数上限
  final bool isPublic; // true=公开（大厅可搜）/ false=私密（需房间号+密码）
  final String? password; // 私密房间密码（null=无需密码）
  final String? hostId; // 房主稳定标识（客户端生成并持久化，归主凭据）
  final bool autoDJ; // 无人值守：房主离线房间不销毁（relay 托管）
  final int ttlSeconds; // 房主离线保活秒数（autoDJ 时生效；0=立即随房主销毁）

  // ── 运行态（非创建字段，随房间生命周期更新）─────────────────────
  String? hostPeerId; // 当前在线房主的 peerId（断线判定）
  bool hostOffline = false; // 房主离线托管中（虚拟 DJ 接管）
  Timer? ttlTimer; // 房主离线 TTL 倒计时（到点销毁房间）

  Map<String, dynamic> toJson(int members) => <String, dynamic>{
        'code': code,
        'name': name,
        'mode': mode,
        'capacity': capacity,
        'public': isPublic,
        'members': members,
        if (autoDJ) 'autoDJ': autoDJ,
        if (hostOffline) 'hostOffline': hostOffline,
      };
}

final Map<String, WebSocket> _clientsById = <String, WebSocket>{}; // peerId → ws
final Map<String, _Client> _clientsByWs = <String, _Client>{}; // ws hash → client
final Map<String, int> _roomCount = <String, int>{}; // room → 人数
final Map<String, _RoomMeta> _rooms = <String, _RoomMeta>{}; // room → 元数据

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
  final bool isHost = join['host'] == true;
  final String? hostId = join['hostId'] as String?;

  if (room.isEmpty) {
    _error(client, 'room required');
    return;
  }

  // ── 房主归主判定（cl16）：托管态房间 + 同 hostId → 恢复房主身份 ────
  // 先判定（用 pre 的原始状态），成功 join 后再做归主收尾，避免提前复位
  // hostOffline 导致「room exists」误判。
  final _RoomMeta? pre = _rooms[room];
  final bool hostReturn = isHost &&
      pre != null &&
      pre.hostOffline &&
      hostId != null &&
      hostId == pre.hostId;

  // ── 创建房间（host=true）：登记元数据 ──────────────────────────────
  if (isHost) {
    // 已有活跃房间（同号）：拒绝，提示换房号。
    // 注：托管态房间（hostOffline=true）+ 同 hostId 的房主归主放行。
    if (_rooms.containsKey(room) && (_roomCount[room] ?? 0) > 0 && !hostReturn) {
      _error(client, 'room exists');
      return;
    }
    final String mode = (join['mode'] as String?) ?? _RoomMode.campus;
    final bool isPublic = join['public'] == true;
    // 容量：一起听 2-10，校园广播默认 100，其余兜底 100。
    final int capacity = switch (mode) {
      _RoomMode.listen => ((join['capacity'] as num?) ?? 10)
          .toInt()
          .clamp(2, 10),
      _ => ((join['capacity'] as num?) ?? 100).toInt().clamp(1, 100),
    };
    final String? password = join['password'] as String?;
    final bool autoDJ = join['autoDJ'] == true;
    final int ttlSeconds =
        ((join['ttl'] as num?) ?? 0).toInt().clamp(0, 3600);
    final _RoomMeta meta = _rooms[room] ?? _RoomMeta(
          code: room,
          name: name.isEmpty ? '房主' : name,
          mode: mode,
          capacity: capacity,
          isPublic: isPublic,
          password: (password == null || password.isEmpty) ? null : password,
          hostId: hostId,
          autoDJ: autoDJ,
          ttlSeconds: ttlSeconds,
        );
    if (!_rooms.containsKey(room)) _rooms[room] = meta;
    _roomCount[room] = (_roomCount[room] ?? 0); // 归主时保持现有成员数
  } else {
    // ── 加入房间（host=false）：校验存在 + 私密密码 + 容量 ─────────────
    final _RoomMeta? meta = _rooms[room];
    if (meta == null) {
      _error(client, 'room not found');
      return;
    }
    // 私密房间：须带正确密码（无密码私密房可直接进）。
    if (!meta.isPublic && meta.password != null) {
      final String pw = (join['password'] as String?) ?? '';
      if (pw != meta.password) {
        _error(client, 'wrong password');
        return;
      }
    }
    final int count = _roomCount[room] ?? 0;
    if (count >= meta.capacity) {
      _error(client, 'room full');
      return;
    }
  }

  // 分配 id，绑定房间
  final String id = _genId();
  _clientsById[id] = client.ws;
  _roomCount[room] = (_roomCount[room] ?? 0) + 1;
  // 用最新对象重写（保留 room/name）
  final _Client bound = _Client(
    ws: client.ws,
    id: id,
    room: room,
    name: name,
  );
  _clientsByWs[client.ws.hashCode.toString()] = bound;
  // 房主：记录当前在线房主 peerId（断线判定用）
  if (isHost) {
    _rooms[room]?.hostPeerId = id;
  }

  // 房主归主收尾：取消 TTL、复位 hostOffline、通知房内成员
  if (hostReturn) {
    pre.ttlTimer?.cancel();
    pre.ttlTimer = null;
    pre.hostOffline = false;
    _broadcastToRoom(
      room,
      <String, dynamic>{'ctl': 'peerHostBack', 'id': hostId},
    );
  }

  // 回 ready（创建者带房间元数据，供客户端展示人数上限/模式）
  final _RoomMeta? meta = _rooms[room];
  _sendRaw(client.ws, <String, dynamic>{
    'ctl': 'ready',
    'id': id,
    if (meta != null) 'meta': meta.toJson(_roomCount[room] ?? 1),
  });

  // 广播 peerJoin 给同房间其它成员（不含新成员自身）
  _broadcastToRoom(room, <String, dynamic>{'ctl': 'peerJoin', 'id': id});
}

void _error(_Client client, String msg) {
  _sendRaw(client.ws, <String, dynamic>{'ctl': 'error', 'msg': msg});
}

void _removeClient(_Client client) {
  _clientsById.remove(client.id);
  _clientsByWs.remove(client.ws.hashCode.toString());
  final String room = client.room;
  final int? count = _roomCount[room];
  final _RoomMeta? meta = _rooms[room];
  if (count != null) {
    final bool isHostLeaving = meta?.hostPeerId == client.id;
    if (isHostLeaving && meta != null && meta.autoDJ && meta.ttlSeconds > 0) {
      // ── 房主离线：转入托管态（cl16，电台自动化）─────────────
      // 房间不销毁，交给虚拟 DJ（M2）继续广播；房主凭 hostId 归主恢复。
      meta.hostOffline = true;
      meta.hostPeerId = null;
      _roomCount[room] = count - 1;
      meta.ttlTimer?.cancel();
      meta.ttlTimer = Timer(Duration(seconds: meta.ttlSeconds), () {
        // TTL 到期：房主未归 → 销毁房间（含元数据）
        _roomCount.remove(room);
        _rooms.remove(room);
      });
      // 通知房内成员：托管态（虚拟 DJ 接管，房主可回归）
      _broadcastToRoom(
        room,
        <String, dynamic>{'ctl': 'roomMetaUpdate', 'hostOffline': true},
      );
    } else if (count <= 1 && !(meta?.hostOffline ?? false)) {
      // 房间清空（非托管态）：立即下线（含元数据）——cl15 原行为
      _roomCount.remove(room);
      _rooms.remove(room);
    } else {
      // 一般成员离开 / 托管态成员离开：仅减人数，房间保留至 TTL
      _roomCount[room] = count - 1;
    }
  }
  // 广播 peerLeave 给同房间其它成员
  _broadcastToRoom(
    room,
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
      'version': 'cl16',
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

// ═══ cl17：CORS —— 运营后台前端已分离部署（独立静态站点）══════════════════
//
// 后台前端不再由 relay 进程伺服，改为独立静态站点部署（见 admin_web/），
// 浏览器跨域调用 /api/* 因此需要 CORS。
//
// 安全边界：CORS 只放宽「读取响应」，不放宽「谁有权限」。鉴权仍靠
// `Authorization: Bearer <secret>`——没有密钥的站点即便能发出请求，
// 拿到的也只会是 401，读不到任何 admin 数据。
//
// 默认放行任意来源；如需收紧，启动时用环境变量指定来源白名单（逗号分隔）：
//   RELAY_CORS_ORIGIN=https://admin.example.com,https://staging.example.com
// 白名单生效时，命中则反射该 Origin，未命中直接在入口拒 403。

/// 允许的来源白名单；空集表示放行任意来源（默认，兼容既有部署）。
final Set<String> _corsAllowOrigins = <String>{
  ...(Platform.environment['RELAY_CORS_ORIGIN'] ?? '')
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty),
};

/// 该跨域来源是否放行（无 Origin 头 = 同源/curl/服务端直连，一律放行）。
bool _corsAllowed(HttpRequest req) {
  final String? origin = req.headers.value('origin');
  if (origin == null || origin.isEmpty) return true;
  return _corsAllowOrigins.isEmpty || _corsAllowOrigins.contains(origin);
}

/// 下发 CORS 响应头（幂等，重复调用结果一致）。
///
/// 非跨域请求不写任何头，行为与分离部署前完全一致。
void _applyCors(HttpRequest req) {
  final String? origin = req.headers.value('origin');
  if (origin == null || origin.isEmpty) return;
  if (_corsAllowOrigins.isNotEmpty && !_corsAllowOrigins.contains(origin)) return;
  req.response.headers
    ..set('Access-Control-Allow-Origin', origin)
    ..set('Vary', 'Origin')
    ..set('Access-Control-Allow-Headers', 'Authorization, Content-Type')
    ..set('Access-Control-Allow-Methods',
        'GET, POST, PUT, PATCH, DELETE, OPTIONS')
    ..set('Access-Control-Max-Age', '86400');
}

Future<void> _handleApi(HttpRequest req) async {
  final String path = req.uri.path;
  final String method = req.method;
  // cl17：跨域来源白名单校验——未命中直接拒（响应不带 CORS 头，浏览器自行拦截）。
  if (!_corsAllowed(req)) {
    await _jsonError(req, 'origin not allowed', status: 403);
    return;
  }
  _applyCors(req);
  if (method == 'OPTIONS') {
    try {
      req.response.statusCode = 204;
      await req.response.close();
    } catch (_) {}
    return;
  }
  // cl14：基础防护——登录/注册限流防爆破、admin 限流防滥用（按 IP 滑动窗口）。
  final String ip = _clientIp(req);
  if ((path == '/api/auth/login' || path == '/api/auth/register') &&
      !_rateLimit('$ip|auth', _kAuthRateMax, _kAuthRateWindowSec)) {
    await _jsonError(req, '请求过于频繁，请稍后再试', status: 429);
    return;
  }
  if ((path == '/api/admin' || path.startsWith('/api/admin/')) &&
      !_rateLimit('$ip|admin', _kAdminRateMax, _kAdminRateWindowSec)) {
    await _jsonError(req, '请求过于频繁，请稍后再试', status: 429);
    return;
  }
  if (path == '/api/admin' || path.startsWith('/api/admin/')) {
    await _handleAdmin(req);
    return;
  }
  Map<String, dynamic>? payload;
  int status = 200;
  switch (path) {
    case '/api/health':
      payload = <String, dynamic>{
        'ok': true,
        'service': 'xingli-relay',
        'version': 'cl16',
        'tls': _tlsEnabled,
        'ts': DateTime.now().toIso8601String(),
      };
      break;
    case '/api/capabilities':
      payload = await _capabilities();
      break;
    case '/api/content/scenes':
      payload = await _loadContent('scenes');
      if (payload == null) status = 404;
      break;
    case '/api/content/playlists':
      payload = await _loadContent('playlists');
      if (payload == null) status = 404;
      break;
    case '/api/content/notices':
      payload = await _loadContent('notices');
      if (payload == null) status = 404;
      break;
    case '/api/content/random':
      payload = await _randomContent();
      if (payload == null) status = 404;
      break;
    case '/api/rooms':
      // cl15：公开房间列表（供电台大厅「加入」页展示，含模式/容量/人数/房主）。
      if (method != 'GET') {
        status = 405;
        payload = <String, dynamic>{'ok': false, 'error': 'method not allowed'};
        break;
      }
      payload = <String, dynamic>{
        'ok': true,
        'rooms': <dynamic>[
          for (final MapEntry<String, _RoomMeta> e in _rooms.entries)
            if (e.value.isPublic && (_roomCount[e.key] ?? 0) > 0)
              e.value.toJson(_roomCount[e.key] ?? 0),
        ],
      };
      break;
    case '/api/auth/register':
      if (method != 'POST') {
        status = 405;
        payload = <String, dynamic>{'ok': false, 'error': 'method not allowed'};
        break;
      }
      payload = await _authRegister(req);
      if (payload['ok'] != true) status = 400;
      break;
    case '/api/auth/login':
      if (method != 'POST') {
        status = 405;
        payload = <String, dynamic>{'ok': false, 'error': 'method not allowed'};
        break;
      }
      payload = await _authLogin(req);
      if (payload['ok'] != true) status = 401;
      break;
    case '/api/auth/me':
      payload = await _authMe(req);
      if (payload['ok'] != true) status = 401;
      break;
    case '/api/auth/logout':
      payload = await _authLogout(req);
      break;
    case '/api/auth/prefs':
      if (method != 'PUT') {
        status = 405;
        payload = <String, dynamic>{'ok': false, 'error': 'method not allowed'};
        break;
      }
      payload = await _authUpdatePrefs(req);
      if (payload['ok'] != true) status = 400;
      break;
    case '/api/auth/favorites':
      if (method != 'PUT') {
        status = 405;
        payload = <String, dynamic>{'ok': false, 'error': 'method not allowed'};
        break;
      }
      payload = await _authUpdateFavorites(req);
      if (payload['ok'] != true) status = 400;
      break;
    case '/api/auth/profile':
      if (method != 'PUT' && method != 'PATCH') {
        status = 405;
        payload = <String, dynamic>{'ok': false, 'error': 'method not allowed'};
        break;
      }
      payload = await _authUpdateProfile(req);
      if (payload['ok'] != true) status = 400;
      break;
    case '/api/auth/change-password':
      // R32：修改密码（校验旧密码 → 重加盐 → 更新 verifier）。
      if (method != 'PUT') {
        status = 405;
        payload = <String, dynamic>{'ok': false, 'error': 'method not allowed'};
        break;
      }
      payload = await _authChangePassword(req);
      if (payload['ok'] != true) status = 400;
      break;
    case '/api/logs':
      if (method != 'POST') {
        status = 405;
        payload = <String, dynamic>{'ok': false, 'error': 'method not allowed'};
        break;
      }
      payload = await _handleAppLogs(req);
      if (payload['ok'] != true) status = 400;
      break;
    default:
      status = 404;
      payload = <String, dynamic>{'ok': false, 'error': 'not found'};
  }
  _applyCors(req); // cl17：跨域响应头（幂等）
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
      if (rec['displayName'] is String && (rec['displayName'] as String).isNotEmpty)
        'displayName': rec['displayName'],
      if (rec['avatar'] is String && (rec['avatar'] as String).isNotEmpty)
        'avatar': rec['avatar'],
      'prefs': rec['prefs'] ?? <String, dynamic>{},
      'favorites': rec['favorites'] ?? <dynamic>[],
      'createdAt': rec['createdAt'],
    };

Future<Map<String, dynamic>> _authRegister(HttpRequest req) async {
  final Map<String, dynamic>? body = await _readJsonBody(req);
  if (body == null) return <String, dynamic>{'ok': false, 'error': 'invalid body'};
  final String username = (body['username'] as String? ?? '').trim();
  final String password = (body['password'] as String? ?? '');
  if (username.length < 3 || username.length > 24) {
    return <String, dynamic>{'ok': false, 'error': '用户名需 3-24 字符'};
  }
  if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(username)) {
    return <String, dynamic>{'ok': false, 'error': '用户名仅限字母数字 _ -'};
  }
  if (password.length < 6) return <String, dynamic>{'ok': false, 'error': '密码至少 6 位'};
  final File f = File('$_kUsersDir/$username.json');
  if (await f.exists()) return <String, dynamic>{'ok': false, 'error': '用户名已存在'};
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
    return <String, dynamic>{'ok': false, 'error': 'server error'};
  }
  return <String, dynamic>{
    'ok': true,
    'token': _signToken(username),
    'user': _publicUser(rec),
  };
}

Future<Map<String, dynamic>> _authLogin(HttpRequest req) async {
  final Map<String, dynamic>? body = await _readJsonBody(req);
  if (body == null) return <String, dynamic>{'ok': false, 'error': 'invalid body'};
  final String username = (body['username'] as String? ?? '').trim();
  final String password = (body['password'] as String? ?? '');
  final File f = File('$_kUsersDir/$username.json');
  if (!await f.exists()) return <String, dynamic>{'ok': false, 'error': '用户名或密码错误'};
  Map<String, dynamic> rec;
  try {
    rec = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return <String, dynamic>{'ok': false, 'error': 'server error'};
  }
  final String expect = _pbkdf2(password, rec['salt'] as String? ?? '');
  if (expect != rec['verifier']) {
    return <String, dynamic>{'ok': false, 'error': '用户名或密码错误'};
  }
  return <String, dynamic>{
    'ok': true,
    'token': _signToken(username),
    'user': _publicUser(rec),
  };
}

Future<Map<String, dynamic>> _authMe(HttpRequest req) async {
  final String? token = _bearer(req);
  if (token == null) return <String, dynamic>{'ok': false, 'error': 'unauthorized'};
  final Map<String, dynamic>? payload = _verifyToken(token);
  if (payload == null) return <String, dynamic>{'ok': false, 'error': 'unauthorized'};
  final File f = File('$_kUsersDir/${payload['uid']}.json');
  if (!await f.exists()) return <String, dynamic>{'ok': false, 'error': 'unauthorized'};
  try {
    final Map<String, dynamic> rec =
        jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return <String, dynamic>{'ok': true, 'user': _publicUser(rec)};
  } catch (_) {
    return <String, dynamic>{'ok': false, 'error': 'server error'};
  }
}

Future<Map<String, dynamic>> _authLogout(HttpRequest req) async {
  // 无状态 token：客户端丢弃即登出；此处预留吊销位点。
  return <String, dynamic>{'ok': true};
}

// ═══ cl14：用户档案读写（偏好 / 收藏跨设备同步）════════════════════

/// 校验请求的 Bearer token 并返回对应用户记录；未登录/失效返回 null。
Future<Map<String, dynamic>?> _authedUserRecord(HttpRequest req) async {
  final String? token = _bearer(req);
  if (token == null) return null;
  final Map<String, dynamic>? payload = _verifyToken(token);
  if (payload == null) return null;
  final File f = File('$_kUsersDir/${payload['uid']}.json');
  if (!await f.exists()) return null;
  try {
    return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// 原子写回用户记录（复用 .tmp + rename，避免半写损坏）。
Future<bool> _writeUserRecord(Map<String, dynamic> rec) async {
  final String username = rec['username'] as String? ?? '';
  if (username.isEmpty) return false;
  try {
    final File f = File('$_kUsersDir/$username.json');
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(rec));
    await tmp.rename(f.path);
    return true;
  } catch (_) {
    return false;
  }
}

/// 更新偏好：`PUT /api/auth/prefs`，body 为 `{prefs: {...}}` 或直接 `{...}`。
Future<Map<String, dynamic>> _authUpdatePrefs(HttpRequest req) async {
  final Map<String, dynamic>? rec = await _authedUserRecord(req);
  if (rec == null) return <String, dynamic>{'ok': false, 'error': 'unauthorized'};
  final Map<String, dynamic>? body = await _readJsonBody(req);
  if (body == null) return <String, dynamic>{'ok': false, 'error': 'invalid body'};
  final Object? prefs = body['prefs'] ?? body;
  if (prefs is! Map<String, dynamic>) {
    return <String, dynamic>{'ok': false, 'error': 'prefs must be object'};
  }
  rec['prefs'] = prefs;
  if (!await _writeUserRecord(rec)) {
    return <String, dynamic>{'ok': false, 'error': 'server error'};
  }
  return <String, dynamic>{'ok': true, 'user': _publicUser(rec)};
}

/// 更新收藏：`PUT /api/auth/favorites`，body 为 `{favorites: [...]}` 或直接 `[...]`。
Future<Map<String, dynamic>> _authUpdateFavorites(HttpRequest req) async {
  final Map<String, dynamic>? rec = await _authedUserRecord(req);
  if (rec == null) return <String, dynamic>{'ok': false, 'error': 'unauthorized'};
  final Map<String, dynamic>? body = await _readJsonBody(req);
  if (body == null) return <String, dynamic>{'ok': false, 'error': 'invalid body'};
  final Object? favs = body['favorites'] ?? body;
  if (favs is! List) return <String, dynamic>{'ok': false, 'error': 'favorites must be array'};
  rec['favorites'] = favs;
  if (!await _writeUserRecord(rec)) {
    return <String, dynamic>{'ok': false, 'error': 'server error'};
  }
  return <String, dynamic>{'ok': true, 'user': _publicUser(rec)};
}

/// 部分更新档案：`PUT/PATCH /api/auth/profile`，body 可含
/// `displayName` / `avatar` / `prefs` / `favorites`。
Future<Map<String, dynamic>> _authUpdateProfile(HttpRequest req) async {
  final Map<String, dynamic>? rec = await _authedUserRecord(req);
  if (rec == null) return <String, dynamic>{'ok': false, 'error': 'unauthorized'};
  final Map<String, dynamic>? body = await _readJsonBody(req);
  if (body == null) return <String, dynamic>{'ok': false, 'error': 'invalid body'};
  // R32：昵称（displayName，≤32 字符）与头像（avatar，URL/emoji/data，≤512 字符）。
  if (body.containsKey('displayName')) {
    final String v = (body['displayName'] as String? ?? '').trim();
    if (v.length > 32) {
      return <String, dynamic>{'ok': false, 'error': '昵称最多 32 字符'};
    }
    rec['displayName'] = v;
  }
  if (body.containsKey('avatar')) {
    final String v = (body['avatar'] as String? ?? '').trim();
    if (v.length > 512) {
      return <String, dynamic>{'ok': false, 'error': '头像数据过长'};
    }
    rec['avatar'] = v;
  }
  if (body.containsKey('prefs')) {
    final Object? prefs = body['prefs'];
    if (prefs is! Map<String, dynamic>) {
      return <String, dynamic>{'ok': false, 'error': 'prefs must be object'};
    }
    rec['prefs'] = prefs;
  }
  if (body.containsKey('favorites')) {
    final Object? favs = body['favorites'];
    if (favs is! List) {
      return <String, dynamic>{'ok': false, 'error': 'favorites must be array'};
    }
    rec['favorites'] = favs;
  }
  if (!await _writeUserRecord(rec)) {
    return <String, dynamic>{'ok': false, 'error': 'server error'};
  }
  return <String, dynamic>{'ok': true, 'user': _publicUser(rec)};
}

/// 修改密码：`PUT /api/auth/change-password`，body `{oldPassword, newPassword}`。
/// 校验旧密码后更新 verifier（重新加盐），token 不变（仍有效）。
Future<Map<String, dynamic>> _authChangePassword(HttpRequest req) async {
  final Map<String, dynamic>? rec = await _authedUserRecord(req);
  if (rec == null) return <String, dynamic>{'ok': false, 'error': 'unauthorized'};
  final Map<String, dynamic>? body = await _readJsonBody(req);
  if (body == null) return <String, dynamic>{'ok': false, 'error': 'invalid body'};
  final String oldPassword = body['oldPassword'] as String? ?? '';
  final String newPassword = body['newPassword'] as String? ?? '';
  if (newPassword.length < 6) {
    return <String, dynamic>{'ok': false, 'error': '新密码至少 6 位'};
  }
  final String oldSalt = rec['salt'] as String? ?? '';
  final String expect = _pbkdf2(oldPassword, oldSalt);
  if (expect != (rec['verifier'] as String? ?? '')) {
    return <String, dynamic>{'ok': false, 'error': '旧密码错误'};
  }
  final String newSalt = base64Encode(_randomBytes(16));
  rec['salt'] = newSalt;
  rec['verifier'] = _pbkdf2(newPassword, newSalt);
  if (!await _writeUserRecord(rec)) {
    return <String, dynamic>{'ok': false, 'error': 'server error'};
  }
  return <String, dynamic>{'ok': true};
}

// ═══ cl14：App 日志接收（/api/logs，JSONL 落盘）════════════════════

/// App 日志目录（按日 JSONL：logs/<YYYY-MM-DD>.log）。
const String _kAppLogsDir = 'logs';

/// 单请求体上限（防刷爆）。
const int _kAppLogMaxBody = 256 * 1024;

/// 单次最大条数。
const int _kAppLogMaxEntries = 500;

/// 单日文件上限（超出丢弃新日志）。
const int _kAppLogMaxFileBytes = 64 * 1024 * 1024;

/// 接收 App 批量日志：`POST /api/logs`，body 为 JSON 数组
/// `[{ts, level, tag, msg}, ...]`（与 log_server 的 /api/logs 协议一致）。
Future<Map<String, dynamic>> _handleAppLogs(HttpRequest req) async {
  final Object? v = await _readJsonAny(req);
  if (v is! List) return <String, dynamic>{'ok': false, 'error': 'expected array'};
  if (v.isEmpty) return <String, dynamic>{'ok': false, 'error': 'empty batch'};
  final List<dynamic> slice =
      v.take(_kAppLogMaxEntries).toList(growable: false);
  // 规整字段，忽略坏行。
  final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
  for (final dynamic e in slice) {
    if (e is! Map<String, dynamic>) continue;
    rows.add(<String, dynamic>{
      'ts': e['ts'] is String ? e['ts'] as String : '',
      'level': e['level'] is String ? e['level'] as String : 'INFO',
      'tag': e['tag'] is String ? e['tag'] as String : '',
      'msg': e['msg'] is String ? e['msg'] as String : jsonEncode(e),
    });
  }
  if (rows.isEmpty) return <String, dynamic>{'ok': false, 'error': 'no valid entries'};
  final int written = await _appendAppLogs(rows);
  return <String, dynamic>{'ok': true, 'received': rows.length, 'written': written};
}

/// 读取任意 JSON（数组/对象都接受），失败返回 null。
Future<Object?> _readJsonAny(HttpRequest req) async {
  try {
    final String body = await utf8.decoder.bind(req).join();
    if (body.isEmpty || body.length > _kAppLogMaxBody) return null;
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

/// 追加日志到当日 JSONL（超单日上限丢弃并返回 0）。
Future<int> _appendAppLogs(List<Map<String, dynamic>> rows) async {
  try {
    final Directory dir = Directory(_kAppLogsDir);
    await dir.create(recursive: true);
    final String stamp = DateTime.now().toIso8601String().split('T').first;
    final File f = File('$_kAppLogsDir/$stamp.log');
    if (await f.exists()) {
      final int size = await f.length();
      if (size > _kAppLogMaxFileBytes) return 0;
    }
    final String lines =
        rows.map((Map<String, dynamic> r) => jsonEncode(r)).join('\n') + '\n';
    await f.writeAsString(lines, mode: FileMode.append);
    return rows.length;
  } catch (_) {
    return 0;
  }
}

/// 读最近 [n] 条 App 日志（倒序，跨当日文件）。
Future<List<dynamic>> _readRecentAppLogs(int n) async {
  final List<dynamic> out = <dynamic>[];
  try {
    final Directory dir = Directory(_kAppLogsDir);
    if (!await dir.exists()) return out;
    final List<FileSystemEntity> files = await dir.list().toList();
    files.sort((a, b) => b.path.compareTo(a.path)); // 新文件在前
    for (final FileSystemEntity e in files) {
      if (e is! File || !e.path.endsWith('.log')) continue;
      final List<String> lines = await e.readAsLines();
      for (int i = lines.length - 1; i >= 0 && out.length < n; i--) {
        final Object? v = jsonDecode(lines[i]);
        if (v is Map<String, dynamic>) out.add(v);
      }
      if (out.length >= n) break;
    }
  } catch (_) {}
  return out;
}

/// 统计注册用户数（users/ 下 *.json 数量）。
Future<int> _countUsers() async {
  try {
    final Directory dir = Directory(_kUsersDir);
    if (!await dir.exists()) return 0;
    final List<FileSystemEntity> files = await dir.list().toList();
    return files.where((e) => e is File && e.path.endsWith('.json')).length;
  } catch (_) {
    return 0;
  }
}

/// 统计 App 日志文件数（logs/ 下 *.log 数量）。
Future<int> _countAppLogFiles() async {
  try {
    final Directory dir = Directory(_kAppLogsDir);
    if (!await dir.exists()) return 0;
    final List<FileSystemEntity> files = await dir.list().toList();
    return files.where((e) => e is File && e.path.endsWith('.log')).length;
  } catch (_) {
    return 0;
  }
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
    // cl13：后台前端已拆分为独立静态站点（admin_web/），relay 只提供 /api/* REST，
    // 不再吐页面；非 API 路径（除 /ws）一律关闭连接。
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

// ═══ 后台管理（admin）：复用启动 secret 鉴权，直接增删改 content/*.json ═══

/// admin 端点鉴权：Bearer 头 == 启动密钥即放行（密钥轮转后后台凭据同步变更）。
bool _isAdmin(HttpRequest req) => _bearer(req) == _serverSecret;

/// 允许的运营内容类型白名单。
const List<String> _kAdminTypes = <String>['notices', 'playlists', 'scenes'];

/// 写 content：先落 .tmp 再 rename，避免半写损坏（原子替换）。
Future<void> _saveContent(String type, List<dynamic> items) async {
  final File f = File('$_kContentDir/$type.json');
  final File tmp = File('$_kContentDir/$type.json.tmp');
  await tmp.writeAsString(
    JsonEncoder.withIndent('  ').convert(<String, dynamic>{type: items}),
  );
  await tmp.rename(f.path);
}

/// JSON 响应快捷封装。
Future<void> _json(HttpRequest req, Map<String, dynamic> data,
    {int status = 200}) async {
  try {
    _applyCors(req); // cl17：跨域响应头（幂等，非跨域请求不写）
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data));
    await req.response.close();
  } catch (_) {}
}

/// 统一错误响应（cl14：与成功结构对齐，均带 `ok` 字段）。
Future<void> _jsonError(HttpRequest req, String message,
    {int status = 400}) async {
  await _json(req, <String, dynamic>{'ok': false, 'error': message},
      status: status);
}

// ═══ cl14：基础防护——按 IP 的滑动窗口限流 ═════════════════════════

/// 登录/注册限流：每 IP 每窗口最多 [kAuthRateMax] 次（防爆破）。
const int _kAuthRateMax = 20;
const int _kAuthRateWindowSec = 60;

/// admin 限流：每 IP 每窗口最多 [kAdminRateMax] 次（防滥用）。
const int _kAdminRateMax = 120;
const int _kAdminRateWindowSec = 60;

final Map<String, List<int>> _rateBuckets = <String, List<int>>{};

/// 滑动窗口限流：窗口 [windowSec] 内超过 [max] 次返回 false（应拒绝）。
///
/// 桶按 key（通常 `ip|用途`）累计时间戳，并定期裁剪过期项防内存膨胀。
bool _rateLimit(String key, int max, int windowSec) {
  final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final List<int> bucket = _rateBuckets.putIfAbsent(key, () => <int>[]);
  bucket.removeWhere((int t) => now - t > windowSec);
  if (bucket.length >= max) return false;
  bucket.add(now);
  if (bucket.length > 256) {
    bucket.removeRange(0, bucket.length - 128);
  }
  return true;
}

/// admin REST：/api/admin/content/<type>[/<id>]，方法 GET/POST/PUT/DELETE。
Future<void> _handleAdmin(HttpRequest req) async {
  final String path = req.uri.path;
  final String method = req.method;
  final bool authed = _isAdmin(req);

  // 探活/元信息（无需鉴权，供前端判断是否已登录）。
  if (path == '/api/admin') {
    await _json(req, <String, dynamic>{
      'ok': true,
      // cl13：后台前端已拆为独立静态站点 admin_web/，relay 不再提供 /admin 页面。
      'ui': 'admin_web/ (独立前端，任意静态托管)',
      'authed': authed,
      'types': _kAdminTypes,
    });
    return;
  }
  if (!authed) {
    await _json(req, <String, dynamic>{'ok': false, 'error': 'unauthorized'}, status: 401);
    return;
  }
  if (path == '/api/admin/log') {
    final List<dynamic> logs = <dynamic>[];
    try {
      final File f = File(_kAuditLog);
      if (await f.exists()) {
        final List<String> lines = await f.readAsLines();
        for (int i = lines.length - 1; i >= 0 && logs.length < 100; i--) {
          final Object? v = jsonDecode(lines[i]);
          if (v is Map<String, dynamic>) logs.add(v);
        }
      }
    } catch (_) {}
    await _json(req, <String, dynamic>{'logs': logs});
    return;
  }
  if (path == '/api/admin/logs/app') {
    // cl14：查看 App 上报的日志（最近 200 条，跨当日文件）。
    await _json(req, <String, dynamic>{'logs': await _readRecentAppLogs(200)});
    return;
  }
  if (path == '/api/admin/stats') {
    // cl14：服务统计（用户数 / 内容数 / 日志行数），供后台概览。
    final Map<String, dynamic> content = <String, dynamic>{};
    for (final String t in _kAdminTypes) {
      final Map<String, dynamic>? data = await _loadContent(t);
      content[t] = (data?[t] as List?)?.length ?? 0;
    }
    await _json(req, <String, dynamic>{
      'ok': true,
      'users': await _countUsers(),
      'content': content,
      'appLogFiles': await _countAppLogFiles(),
      'ts': DateTime.now().toIso8601String(),
    });
    return;
  }
  if (path == '/api/admin/users') {
    // cl14：用户列表（公开档案 + 文件信息，不含凭据）。
    final List<dynamic> users = <dynamic>[];
    try {
      final Directory dir = Directory(_kUsersDir);
      if (await dir.exists()) {
        final List<FileSystemEntity> files = await dir.list().toList();
        files.sort((a, b) => a.path.compareTo(b.path));
        for (final FileSystemEntity e in files) {
          if (e is! File || !e.path.endsWith('.json')) continue;
          try {
            final Map<String, dynamic> rec =
                jsonDecode(await e.readAsString()) as Map<String, dynamic>;
            final Map<String, dynamic> u = _publicUser(rec);
            u['fileSize'] = await e.length();
            u['prefsCount'] = (rec['prefs'] as Map?)?.length ?? 0;
            u['favoritesCount'] = (rec['favorites'] as List?)?.length ?? 0;
            users.add(u);
          } catch (_) {}
        }
      }
    } catch (_) {}
    await _json(req, <String, dynamic>{'users': users, 'count': users.length});
    return;
  }

  // 用户管理：DELETE 删除用户 / POST reset 重置密码。
  final RegExpMatch? userOp =
      RegExp(r'^/api/admin/users/([A-Za-z0-9_\-]+)$').firstMatch(path);
  if (userOp != null) {
    final String username = userOp.group(1)!;
    final File f = File('$_kUsersDir/$username.json');
    if (!await f.exists()) {
      await _jsonError(req, '用户不存在', status: 404);
      return;
    }
    if (method == 'DELETE') {
      try {
        await f.delete();
      } catch (_) {
        await _jsonError(req, '删除失败', status: 500);
        return;
      }
      await _logAdmin('deleteUser', 'users', username, _clientIp(req));
      await _json(req, <String, dynamic>{'ok': true, 'removed': username});
      return;
    }
    if (method == 'POST') {
      // 重置密码：body {password} → 重新生成 salt + verifier。
      final Map<String, dynamic>? body = await _readJsonBody(req);
      final String password = (body?['password'] as String? ?? '').trim();
      if (password.length < 6) {
        await _jsonError(req, '新密码至少 6 位', status: 400);
        return;
      }
      try {
        final Map<String, dynamic> rec =
            jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        rec['salt'] = base64Encode(_randomBytes(16));
        rec['verifier'] = _pbkdf2(password, rec['salt'] as String);
        await _writeUserRecord(rec);
      } catch (_) {
        await _jsonError(req, '重置失败', status: 500);
        return;
      }
      await _logAdmin('resetPassword', 'users', username, _clientIp(req));
      await _json(req, <String, dynamic>{'ok': true, 'reset': username});
      return;
    }
    await _jsonError(req, 'method not allowed', status: 405);
    return;
  }

  final RegExpMatch? m =
      RegExp(r'^/api/admin/content/([a-z]+)(?:/([^/]+))?$').firstMatch(path);
  if (m == null) {
    await _json(req, <String, dynamic>{'ok': false, 'error': 'bad path'}, status: 404);
    return;
  }
  final String type = m.group(1)!;
  final String? id = m.group(2);
  if (!_kAdminTypes.contains(type)) {
    await _json(req, <String, dynamic>{'ok': false, 'error': 'unknown type'}, status: 400);
    return;
  }

  if (method == 'GET' && id == null) {
    final Map<String, dynamic>? data = await _loadContent(type);
    await _json(req, data ?? <String, dynamic>{type: <dynamic>[]});
    return;
  }
  if (method == 'POST' && id == null) {
    final Map<String, dynamic>? body = await _readJsonBody(req);
    if (body == null) {
      await _json(req, <String, dynamic>{'ok': false, 'error': 'invalid body'}, status: 400);
      return;
    }
    final Map<String, dynamic> cur =
        await _loadContent(type) ?? <String, dynamic>{type: <dynamic>[]};
    final List<dynamic> list =
        List<dynamic>.from(cur[type] as List? ?? <dynamic>[]);
    final Map<String, dynamic> item = <String, dynamic>{...body};
    item['id'] ??= _genId();
    list.add(item);
    await _saveContent(type, list);
    await _logAdmin('create', type, item['id'] as String?, _clientIp(req));
    await _json(req, <String, dynamic>{'ok': true, 'id': item['id']});
    return;
  }
  if ((method == 'PUT' || method == 'PATCH') && id != null) {
    final Map<String, dynamic>? body = await _readJsonBody(req);
    if (body == null) {
      await _json(req, <String, dynamic>{'ok': false, 'error': 'invalid body'}, status: 400);
      return;
    }
    final Map<String, dynamic> cur =
        await _loadContent(type) ?? <String, dynamic>{type: <dynamic>[]};
    final List<dynamic> list =
        List<dynamic>.from(cur[type] as List? ?? <dynamic>[]);
    final int idx = list.indexWhere((e) => e is Map && e['id'] == id);
    if (idx < 0) {
      await _json(req, <String, dynamic>{'ok': false, 'error': 'not found'}, status: 404);
      return;
    }
    list[idx] = <String, dynamic>{...list[idx] as Map, ...body, 'id': id};
    await _saveContent(type, list);
    await _logAdmin('update', type, id, _clientIp(req));
    await _json(req, <String, dynamic>{'ok': true});
    return;
  }
  if (method == 'DELETE' && id != null) {
    final Map<String, dynamic> cur =
        await _loadContent(type) ?? <String, dynamic>{type: <dynamic>[]};
    final List<dynamic> list =
        List<dynamic>.from(cur[type] as List? ?? <dynamic>[]);
    final int before = list.length;
    list.removeWhere((e) => e is Map && e['id'] == id);
    if (list.length == before) {
      await _json(req, <String, dynamic>{'ok': false, 'error': 'not found'}, status: 404);
      return;
    }
    await _saveContent(type, list);
    await _logAdmin('delete', type, id, _clientIp(req));
    await _json(req,
        <String, dynamic>{'ok': true, 'removed': before - list.length});
    return;
  }
  await _json(req, <String, dynamic>{'ok': false, 'error': 'method not allowed'},
      status: 405);
}

/// 审计日志（JSONL，追加写）：记录后台写操作，供运营追溯。
const String _kAuditLog = 'admin/audit.jsonl';

/// 记录一条审计日志（ts/action/type/id/ip）。
Future<void> _logAdmin(
    String action, String type, String? id, String ip) async {
  try {
    final File f = File(_kAuditLog);
    final Map<String, dynamic> rec = <String, dynamic>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'type': type,
      'id': id,
      'ip': ip,
    };
    await f.writeAsString(jsonEncode(rec) + '\n', mode: FileMode.append);
  } catch (_) {}
}

/// 取客户端 IP（审计用）。
String _clientIp(HttpRequest req) {
  try {
    return req.connectionInfo?.remoteAddress.address ?? 'unknown';
  } catch (_) {
    return 'unknown';
  }
}
