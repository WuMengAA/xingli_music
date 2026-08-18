/// ════════════════════════════════════════════════════════════════════════
/// 联机会话状态（G9）：编排传输层、维护成员、广播/分发同步消息。
/// ════════════════════════════════════════════════════════════════════════
///
/// 拓扑：**主机-客户端**（任何人可当主机，即用户理解的 P2P）。地形按 seed
/// 确定性重现，故只同步：方块编辑(chunk delta) + 玩家变换 + 生命/饥饿/经验 +
/// 聊天 + 一起听(曲目+进度)。v1 一起听以**主机为 DJ**，客户端跟随。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../services/audio/audio_service.dart';
import '../../providers/audio/audio_providers.dart';
import '../../services/net/lan_discovery.dart';
import '../../services/net/net_message.dart';
import '../../services/net/net_node.dart';

// ── 角色 / 连接状态 ─────────────────────────────────────

enum NetRole { offline, host, client }

enum ConnStatus { idle, connecting, connected, reconnecting, error }

/// 一名联机成员（远端玩家）的状态快照。
class PeerInfo {
  PeerInfo({
    required this.id,
    this.name = '玩家',
    this.isHost = false,
    this.x,
    this.y,
    this.z,
    this.yaw = 0,
    this.pitch = 0,
    this.viewMode = 2,
    this.health = 20,
    this.hunger = 20,
    this.xp = 0,
    this.px,
    this.py,
    this.pz,
    this.pyaw,
    this.ppitch,
    this.arrivedAt,
    this.snapInterval = const Duration(milliseconds: 100),
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String id;
  String name;
  bool isHost;
  double? x, y, z;
  double yaw, pitch;
  int viewMode;
  int health, hunger, xp;
  DateTime lastSeen;

  // cl83net：联机远端玩家渲染插值状态。transform 每 ~100ms 一帧、渲染每帧跑，
  // 不插值就会每 100ms 跳一下（瞬移）。prev 为上一个快照位置/朝向，arrivedAt
  // 为当前快照到达时刻，snapInterval 为上一帧间隔，渲染端据此 lerp。
  double? px, py, pz;
  double? pyaw, ppitch;
  DateTime? arrivedAt;
  Duration snapInterval;

  PeerInfo copyWith({
    String? name,
    bool? isHost,
    double? x,
    double? y,
    double? z,
    double? yaw,
    double? pitch,
    int? viewMode,
    int? health,
    int? hunger,
    int? xp,
  }) =>
      PeerInfo(
        id: id,
        name: name ?? this.name,
        isHost: isHost ?? this.isHost,
        x: x ?? this.x,
        y: y ?? this.y,
        z: z ?? this.z,
        yaw: yaw ?? this.yaw,
        pitch: pitch ?? this.pitch,
        viewMode: viewMode ?? this.viewMode,
        health: health ?? this.health,
        hunger: hunger ?? this.hunger,
        xp: xp ?? this.xp,
        lastSeen: DateTime.now(),
      );

  factory PeerInfo.fromJson(Map<String, dynamic> j) => PeerInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? '玩家',
        isHost: j['host'] as bool? ?? false,
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
        z: (j['z'] as num?)?.toDouble(),
        yaw: (j['yaw'] as num?)?.toDouble() ?? 0,
        pitch: (j['pitch'] as num?)?.toDouble() ?? 0,
        viewMode: j['vm'] as int? ?? 2,
        health: j['hp'] as int? ?? 20,
        hunger: j['hg'] as int? ?? 20,
        xp: j['xp'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'host': isHost,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (z != null) 'z': z,
        'yaw': yaw,
        'pitch': pitch,
        'vm': viewMode,
        'hp': health,
        'hg': hunger,
        'xp': xp,
      };
}

/// 一条聊天消息。
class ChatLine {
  ChatLine({
    required this.fromId,
    required this.name,
    required this.text,
    DateTime? at,
  }) : at = at ?? DateTime.now();
  final String fromId;
  final String name;
  final String text;
  final DateTime at;
}

/// 纯函数（cl79）：把收到的 vitals 负载（hp/hg/xp，缺省保留原值）合并进
/// 成员列表，供 vitals 接收分支复用与单测（不碰网络/引擎）。
List<PeerInfo> applyVitalsToPeers(
  List<PeerInfo> peers,
  String from,
  Map<String, dynamic> payload,
) =>
    peers
        .map((pp) => pp.id == from
            ? pp.copyWith(
                health: payload['hp'] as int? ?? pp.health,
                hunger: payload['hg'] as int? ?? pp.hunger,
                xp: payload['xp'] as int? ?? pp.xp,
              )
            : pp)
        .toList();

/// 联机会话整体状态（Riverpod 真相源）。
class NetSessionState {
  const NetSessionState({
    this.role = NetRole.offline,
    this.status = ConnStatus.idle,
    this.localId,
    this.localName = '玩家',
    this.hostIp,
    this.port,
    this.peers = const <PeerInfo>[],
    this.error,
    this.chat = const <ChatLine>[],
    this.hostSeed,
    this.hostOptions,
    this.dj = false,
    this.reconnectAttempt = 0,
    this.roomCode,
    this.relayUrl,
    this.lastSeenAt,
  });

  final NetRole role;
  final ConnStatus status;
  final String? localId;
  final String localName;
  final String? hostIp;
  final int? port;
  final List<PeerInfo> peers;
  final String? error;
  final List<ChatLine> chat;
  final int? hostSeed;
  final Map<String, dynamic>? hostOptions;
  final bool dj; // 本端是否 DJ（一起听音源）
  final int reconnectAttempt; // 重连尝试次数（status==reconnecting 时 UI 展示）
  final String? roomCode; // 中转模式：房间号（房主展示给好友）
  final String? relayUrl; // 中转模式：中转服务器地址

  /// cl06：最近一次收到远端消息的时间（HUD 显示联机「延迟/当前状态」）。
  final DateTime? lastSeenAt;

  NetSessionState copyWith({
    NetRole? role,
    ConnStatus? status,
    String? localId,
    String? localName,
    String? hostIp,
    int? port,
    List<PeerInfo>? peers,
    String? error,
    List<ChatLine>? chat,
    int? hostSeed,
    Map<String, dynamic>? hostOptions,
    bool? dj,
    int? reconnectAttempt,
    String? roomCode,
    String? relayUrl,
    DateTime? lastSeenAt,
  }) =>
      NetSessionState(
        role: role ?? this.role,
        status: status ?? this.status,
        localId: localId ?? this.localId,
        localName: localName ?? this.localName,
        hostIp: hostIp ?? this.hostIp,
        port: port ?? this.port,
        peers: peers ?? this.peers,
        error: error ?? this.error,
        chat: chat ?? this.chat,
        hostSeed: hostSeed ?? this.hostSeed,
        hostOptions: hostOptions ?? this.hostOptions,
        dj: dj ?? this.dj,
        reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
        roomCode: roomCode ?? this.roomCode,
        relayUrl: relayUrl ?? this.relayUrl,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      );

  PeerInfo? peer(String id) {
    for (final PeerInfo p in peers) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// 联机会话 Notifier（单例，跨页面存活）。
final netSessionProvider =
    StateNotifierProvider<NetSessionNotifier, NetSessionState>(
  (ref) => NetSessionNotifier(ref),
);

class NetSessionNotifier extends StateNotifier<NetSessionState> {
  NetSessionNotifier(this.ref) : super(const NetSessionState());

  /// 注入的 Riverpod Ref（一起听 DJ 广播需读取播放状态）。
  final Ref ref;

  NetNode? _node;
  RawDatagramSocket? _beacon;
  Timer? _posTimer;
  bool _djListeners = false;
  Completer<void>? _joined;

  /// 测试缝隙（cl79）：fake 传输层——`_node` 未建连时广播消息转交此回调，
  /// 供单测断言信封（t/f/to/p）正确，不碰真实网络/引擎。
  @visibleForTesting
  void Function(NetMessage message)? debugOnSend;

  /// 测试缝隙（cl79）：直接设置本地 id（正常流程由建连/欢迎消息写入）。
  @visibleForTesting
  void debugSetLocalIdForTest(String id) {
    state = state.copyWith(localId: id);
  }

  // ── 断线重连（G9 cl65，仅客户端）──
  bool _reconnecting = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  bool _intentionalLeave = false;
  /// 重连成功回调（世界视图注册）：清旧远端玩家缓存等；仅重连成功触发，
  /// 初次加入不触发。
  void Function()? onReconnected;

  // ── G9 cl67：编辑层快照（按玩家位置范围同步，仅编辑层，地形不同步）──
  /// 主机提供编辑层快照（世界视图注册，仅主机调用）：以请求者的机位
  /// (cx,cz) 与范围半径 radius 裁剪，返回
  /// `{edits: [...], lights: [...]}`（[VoxelWorld.editLayerJsonNear]）。
  /// 签名带机位参数，使主机能按需只下发请求者周围 N 格区块，避免大世界全量。
  Map<String, dynamic>? Function(int cx, int cz, int radius)? editSnapshotProvider;
  /// 客户端收到编辑层快照后应用（世界视图注册）：把他人已建结构落到本地世界。
  void Function(List<dynamic> edits, List<dynamic> lights)? onEditSnapshot;

  // 重连参数：指数退避（1.5s 起，封顶 8s），最多 12 次后转致命错误。
  static const int _kReconnectMaxAttempts = 12;
  static const Duration _kReconnectBase = Duration(milliseconds: 1500);
  static const Duration _kReconnectMaxBackoff = Duration(seconds: 8);

  /// 远端方块编辑回调（世界视图注册；最后一次注册者生效）。
  void Function(int x, int y, int z, int v)? onRemoteEdit;
  /// 远端玩家变换回调（id, x, y, z, yaw, pitch, viewMode）。
  void Function(String id, double x, double y, double z, double yaw, double pitch,
      int vm)? onRemoteTransform;

  // ── 主持 ──
  Future<bool> host({
    int port = kNetDefaultPort,
    required int seed,
    Map<String, dynamic>? options,
    String name = '玩家',
    String? relayUrl,
    String? room,
  }) async {
    if (_node != null) return false;
    try {
      state = state.copyWith(
        status: ConnStatus.connecting,
        port: port,
        localName: name,
        hostSeed: seed,
        hostOptions: options,
        error: null,
        relayUrl: relayUrl,
        roomCode: room,
      );
      if (relayUrl != null) {
        // 中转模式：连中转服务器并登记房间，由服务器做星型扇出（跨 NAT）。
        final String roomCode = (room ?? _genRoom()).toUpperCase();
        _node =
            await NetNode.relay(relayUrl, roomCode, name, isHostGame: true);
        await _node!.ready.timeout(const Duration(seconds: 6));
        // cl79：服务器 ctl:error（如 room full）经 [NetNode.relayError] 透传。
        final String? relayErr = _node!.relayError;
        if (relayErr != null) throw Exception(relayErr);
        state = state.copyWith(
          role: NetRole.host,
          status: ConnStatus.connected,
          localId: _node!.localId,
          dj: true,
          roomCode: roomCode,
        );
        _subscribe();
        _startDj();
        _sendHello();
        return true;
      }
      _node = await NetNode.host(port: port);
      state = state.copyWith(
        role: NetRole.host,
        status: ConnStatus.connected,
        localId: _node!.localId,
        dj: true,
      );
      _subscribe();
      _startDj();
      _beacon = await LanDiscovery.startBeacon(port: port, name: name);
      _sendHello();
      return true;
    } catch (e) {
      state = state.copyWith(
        status: ConnStatus.error,
        error: '主持失败：${friendlyRelayError(e)}',
      );
      await _node?.close();
      _node = null;
      return false;
    }
  }

  // ── 加入 ──
  Future<bool> join(
    String ip,
    int port, {
    String name = '玩家',
    String? relayUrl,
    String? room,
  }) async {
    if (_node != null) return false;
    _joined = Completer<void>();
    try {
      state = state.copyWith(
        status: ConnStatus.connecting,
        hostIp: ip,
        port: port,
        localName: name,
        error: null,
        relayUrl: relayUrl,
        roomCode: room,
      );
      if (relayUrl != null) {
        // 中转模式：凭房间号加入，无需房主 IP。
        if (room == null || room.isEmpty) {
          throw Exception('房间号不能为空');
        }
        _node = await NetNode.relay(
          relayUrl,
          room.toUpperCase(),
          name,
          isHostGame: false,
        );
        await _node!.ready.timeout(const Duration(seconds: 6));
        // cl79：服务器 ctl:error（room required / room full）经 relayError 透传。
        final String? relayErr = _node!.relayError;
        if (relayErr != null) throw Exception(relayErr);
        state = state.copyWith(
          role: NetRole.client,
          status: ConnStatus.connected,
          localId: _node!.localId,
        );
        _subscribe();
        _sendHello();
        await _joined!.future.timeout(const Duration(seconds: 6));
        return true;
      }
      _node = await NetNode.connect(ip, port);
      state = state.copyWith(
        role: NetRole.client,
        status: ConnStatus.connected,
        localId: _node!.localId,
      );
      _subscribe();
      _sendHello();
      await _joined!.future.timeout(const Duration(seconds: 6));
      return true;
    } catch (e) {
      state = state.copyWith(
        status: ConnStatus.error,
        error: '连接失败：${friendlyRelayError(e)}',
      );
      await _node?.close();
      _node = null;
      return false;
    }
  }

  /// 生成 6 位无歧义房间号（去除了 0/O/1/I/L 等易混字符）。
  String _genRoom() {
    const String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final math.Random r = math.Random();
    return String.fromCharCodes(
      Iterable<int>.generate(
        6,
        (_) => alphabet.codeUnitAt(r.nextInt(alphabet.length)),
      ),
    );
  }

  void _subscribe() => _node!.events.listen(_onEvent);

  void _onEvent(NetEvent e) {
    if (e is NetPeerConnected) {
      // 主机侧：向新成员发送完整 welcome（含世界 seed/选项/昵称/成员列表）。
      _node?.sendTo(
        e.peerId,
        NetMessage(
          type: NetMsgType.welcome,
          from: state.localId ?? '',
          payload: <String, dynamic>{
            'id': e.peerId,
            'host': state.localId,
            'hostName': state.localName,
            'seed': state.hostSeed,
            'options': state.hostOptions,
            'peers': <Map<String, dynamic>>[
              for (final PeerInfo p
                  in state.peers.where((pp) => pp.id != e.peerId))
                p.toJson(),
            ],
          },
        ),
      );
      // 广播 peerJoin 给其它成员。
      _node?.send(
        NetMessage(
          type: NetMsgType.peerJoin,
          from: state.localId ?? '',
          payload: <String, dynamic>{'id': e.peerId},
        ),
        exceptId: e.peerId,
      );
      state = state.copyWith(
        peers: <PeerInfo>[...state.peers, PeerInfo(id: e.peerId)],
      );
      // G9 cl67：不再在 NetPeerConnected 时主动下发编辑层快照。
      // 原因：新成员刚接入时尚无上报机位，范围裁剪无从谈起；且范围同步下
      // 全量下发违背「只同步自身周围区块」的设计。改为客户端 world 视图注册
      // 回调后，按自身机位调用 [requestEditSnapshot] 主动拉取（见下
      // requestEditSnapshot case / 方法），主机按机位裁剪回发。
    } else if (e is NetPeerDisconnected) {
      state = state.copyWith(
        peers: state.peers.where((p) => p.id != e.peerId).toList(),
      );
    } else if (e is NetClosed) {
      // G9 cl65：客户端非主动断开 → 自动重连；否则致命错误。
      if (state.role == NetRole.client && !_intentionalLeave) {
        _beginReconnect();
      } else {
        state = state.copyWith(
          status: ConnStatus.error,
          error: '连接已断开',
          role: NetRole.offline,
        );
      }
    } else if (e is NetMessageEvent) {
      _onMessage(e.from, e.message);
    }
  }

  void _onMessage(String from, NetMessage msg) {
    // cl06：记录最近通信时间，HUD 用其估算联机延迟/存活状态。
    state = state.copyWith(lastSeenAt: DateTime.now());
    switch (msg.type) {
      case NetMsgType.welcome:
        // 仅接受带 seed 的权威 welcome（NetNode 自动发的无 seed 忽略）。
        if (msg.payload['seed'] == null) return;
        state = state.copyWith(
          localId: msg.payload['id'] as String? ?? state.localId,
          hostSeed: msg.payload['seed'] as int?,
          hostOptions: msg.payload['options'] as Map<String, dynamic>?,
        );
        final String? hostId = msg.payload['host'] as String?;
        final List<PeerInfo> list = <PeerInfo>[];
        if (hostId != null && state.peer(hostId) == null) {
          list.add(PeerInfo(
            id: hostId,
            isHost: true,
            name: msg.payload['hostName'] as String? ?? '房主',
          ));
        }
        final List<dynamic>? existing =
            msg.payload['peers'] as List<dynamic>?;
        if (existing != null) {
          for (final dynamic p in existing) {
            list.add(PeerInfo.fromJson(p as Map<String, dynamic>));
          }
        }
        state = state.copyWith(peers: list);
        // 客户端：请求主机当前一起听状态。
        if (state.role == NetRole.client) {
          _node?.send(NetMessage(
            type: NetMsgType.requestListen,
            from: state.localId ?? '',
            payload: const <String, dynamic>{},
          ));
        }
        _joined?.complete();
        break;

      case NetMsgType.hello: // 昵称上报（含 id 以便转发）
        final String id = msg.payload['id'] as String? ?? from;
        if (id == state.localId) return; // 中转模式自环过滤
        final String name = msg.payload['name'] as String? ?? '玩家';
        state = state.copyWith(
          peers: state.peers
              .map((p) => p.id == id
                  ? p.copyWith(
                      name: name,
                      isHost: msg.payload['host'] as bool? ?? p.isHost,
                    )
                  : p)
              .toList(),
        );
        // 主机：转发给其它成员，使其也拿到该成员昵称。
        if (state.role == NetRole.host && id != from) {
          _node?.send(
            NetMessage(
              type: NetMsgType.hello,
              from: state.localId ?? '',
              payload: <String, dynamic>{
                'id': id,
                'name': name,
                'host': msg.payload['host'] as bool? ?? false,
              },
            ),
            exceptId: from,
          );
        }
        break;

      case NetMsgType.peerJoin:
        final String id = msg.payload['id'] as String? ?? from;
        if (id == state.localId) return; // 中转模式自环过滤
        if (state.peer(id) == null) {
          state = state.copyWith(
            peers: <PeerInfo>[...state.peers, PeerInfo(id: id)],
          );
        }
        break;

      case NetMsgType.peerLeave:
        final String id = msg.payload['id'] as String? ?? from;
        if (id == state.localId) return; // 中转模式自环过滤
        state = state.copyWith(
          peers: state.peers.where((p) => p.id != id).toList(),
        );
        break;

      case NetMsgType.transform:
        final PeerInfo? p = state.peer(from);
        if (p != null) {
          state = state.copyWith(
            peers: state.peers
                .map((pp) => pp.id == from
                    ? pp.copyWith(
                        x: (msg.payload['x'] as num?)?.toDouble(),
                        y: (msg.payload['y'] as num?)?.toDouble(),
                        z: (msg.payload['z'] as num?)?.toDouble(),
                        yaw: (msg.payload['yaw'] as num?)?.toDouble() ?? 0,
                        pitch: (msg.payload['pitch'] as num?)?.toDouble() ?? 0,
                        viewMode: msg.payload['vm'] as int? ?? 2,
                      )
                    : pp)
                .toList(),
          );
          onRemoteTransform?.call(
            from,
            (msg.payload['x'] as num?)?.toDouble() ?? 0,
            (msg.payload['y'] as num?)?.toDouble() ?? 0,
            (msg.payload['z'] as num?)?.toDouble() ?? 0,
            (msg.payload['yaw'] as num?)?.toDouble() ?? 0,
            (msg.payload['pitch'] as num?)?.toDouble() ?? 0,
            msg.payload['vm'] as int? ?? 2,
          );
        }
        break;

      case NetMsgType.edit:
        final int x = msg.payload['x'] as int? ?? 0;
        final int y = msg.payload['y'] as int? ?? 0;
        final int z = msg.payload['z'] as int? ?? 0;
        final int v = msg.payload['v'] as int? ?? 0;
        onRemoteEdit?.call(x, y, z, v);
        break;

      case NetMsgType.editSnapshot:
        // 客户端：把主机下发的编辑层快照（他人已建结构）应用到本地世界。
        final List<dynamic>? edits =
            msg.payload['edits'] as List<dynamic>?;
        final List<dynamic>? lights =
            msg.payload['lights'] as List<dynamic>?;
        if (edits != null && lights != null) {
          onEditSnapshot?.call(edits, lights);
        }
        break;

      case NetMsgType.requestEditSnapshot:
        // 仅主机响应：按请求者机位 (cx,cz) 与半径 radius 裁剪编辑层快照，单发
        // 给请求者（客户端 world 视图注册回调后主动请求，规避 welcome 早于
        // 视图回调注册的竞态）。主机用请求者上报的机位就近裁剪，只回发其周围
        // N 格区块，避免大世界全量淹没（cl67 范围同步）。
        if (state.role == NetRole.host) {
          final int cx = (msg.payload['cx'] as int?) ?? 0;
          final int cz = (msg.payload['cz'] as int?) ?? 0;
          final int radius = (msg.payload['radius'] as int?) ?? -1;
          final Map<String, dynamic>? snap =
              editSnapshotProvider?.call(cx, cz, radius);
          if (snap != null) {
            _node?.sendTo(
              from,
              NetMessage(
                type: NetMsgType.editSnapshot,
                from: state.localId ?? '',
                payload: snap,
              ),
            );
          }
        }
        break;

      case NetMsgType.vitals:
        if (state.peer(from) != null) {
          state = state.copyWith(
            peers: applyVitalsToPeers(state.peers, from, msg.payload),
          );
        }
        break;

      case NetMsgType.chat:
        final String text = msg.payload['text'] as String? ?? '';
        final String name = msg.payload['name'] as String? ??
            (state.peer(from)?.name ?? '玩家');
        state = state.copyWith(
          chat: <ChatLine>[
            ...state.chat,
            ChatLine(fromId: from, name: name, text: text),
          ],
        );
        break;

      case NetMsgType.listenState:
        _applyRemoteListen(msg.payload);
        break;

      case NetMsgType.requestListen:
        if (state.role == NetRole.host) _broadcastListen(force: true);
        break;

      case NetMsgType.bye:
        state = state.copyWith(
          peers: state.peers.where((p) => p.id != from).toList(),
        );
        break;

      case NetMsgType.ping:
        break;
    }
  }

  void _sendHello() {
    _node?.send(NetMessage(
      type: NetMsgType.hello,
      from: state.localId ?? '',
      payload: <String, dynamic>{
        'id': state.localId,
        'name': state.localName,
        'host': state.role == NetRole.host,
      },
    ));
  }

  /// 广播玩家位置 / 视角（世界视图每 ~100ms 调用）。
  void broadcastTransform(
    double x,
    double y,
    double z,
    double yaw,
    double pitch,
    int vm,
  ) {
    if (_node == null) return;
    _node!.send(NetMessage(
      type: NetMsgType.transform,
      from: state.localId ?? '',
      payload: <String, dynamic>{
        'x': x,
        'y': y,
        'z': z,
        'yaw': yaw,
        'pitch': pitch,
        'vm': vm,
      },
    ));
  }

  /// 广播方块编辑（破坏 / 放置）。v = Voxel.values 索引。
  void broadcastEdit(int x, int y, int z, int v) {
    if (_node == null) return;
    _node!.send(NetMessage(
      type: NetMsgType.edit,
      from: state.localId ?? '',
      payload: <String, dynamic>{'x': x, 'y': y, 'z': z, 'v': v},
    ));
  }

  /// 广播生命 / 饥饿 / 经验（cl79 起复用 [buildVitalsMessage] 纯函数；
  /// 未建连时转交 [debugOnSend] 测试缝隙）。
  void broadcastVitals(int health, int hunger, int xp) {
    final NetMessage msg =
        buildVitalsMessage(state.localId ?? '', health, hunger, xp);
    if (_node == null) {
      debugOnSend?.call(msg);
      return;
    }
    _node!.send(msg);
  }

  /// G9 cl67：客户端按自身机位请求主机编辑层快照（范围同步）。
  /// [cx],[cz] 为请求者所在 chunk 坐标，[radius] 为需覆盖的 chunk 半径；
  /// 主机据此就近裁剪回发（只下发周围区块）。在 world 视图注册 onEditSnapshot
  /// 后立即调用，避免「welcome/Snapshot 早于 world 视图回调注册」竞态导致快照
  /// 被静默丢弃；后续机位跨 chunk 时再按需重新请求（游走加载/卸载）。
  void requestEditSnapshot(int cx, int cz, int radius) {
    if (_node == null || state.role != NetRole.client) return;
    _node!.send(NetMessage(
      type: NetMsgType.requestEditSnapshot,
      from: state.localId ?? '',
      payload: <String, dynamic>{
        'cx': cx,
        'cz': cz,
        'radius': radius,
      },
    ));
  }

  /// 发送聊天。
  void sendChat(String text) {
    if (_node == null || text.trim().isEmpty) return;
    _node!.send(NetMessage(
      type: NetMsgType.chat,
      from: state.localId ?? '',
      payload: <String, dynamic>{'text': text, 'name': state.localName},
    ));
    state = state.copyWith(
      chat: <ChatLine>[
        ...state.chat,
        ChatLine(fromId: state.localId ?? '', name: state.localName, text: text),
      ],
    );
  }

  // ── 一起听（主机为 DJ）──

  void _startDj() {
    if (_djListeners) return;
    _djListeners = true;
    ref.listen(nowPlayingProvider, (_, __) => _broadcastListen());
    ref.listen(isPlayingProvider, (_, __) => _broadcastListen());
    _posTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _broadcastListen(force: true));
  }

  void _broadcastListen({bool force = false}) {
    if (state.role != NetRole.host) return;
    final Track? t = ref.read(nowPlayingProvider);
    if (!force && t == null) return;
    final bool? playing = ref.read(isPlayingProvider).valueOrNull;
    final Duration? pos = ref.read(musicPositionProvider).valueOrNull;
    _node?.send(NetMessage(
      type: NetMsgType.listenState,
      from: state.localId ?? '',
      payload: <String, dynamic>{
        'uri': t?.uri ?? '',
        'title': t?.title ?? '',
        'artist': t?.artist ?? '',
        'sourceId': t?.sourceId ?? '',
        'playing': playing ?? false,
        'pos': (pos?.inMilliseconds) ?? 0,
      },
    ));
  }

  void _applyRemoteListen(Map<String, dynamic> p) {
    if (state.role != NetRole.client) return;
    final String uri = (p['uri'] as String?) ?? '';
    if (uri.isEmpty) return;
    final Track? cur = ref.read(nowPlayingProvider);
    final AudioService svc = ref.read(audioServiceProvider);
    if (cur?.uri != uri) {
      final Track track = Track(
        title: (p['title'] as String?) ?? '未知曲目',
        artist: (p['artist'] as String?) ?? '',
        uri: uri,
        sourceId: (p['sourceId'] as String?) ?? '',
        source: TrackSource.stream,
      );
      unawaited(svc.playMusic(track, fade: Duration.zero));
    }
    final int posMs = (p['pos'] as int?) ?? 0;
    unawaited(svc.seek(Duration(milliseconds: posMs)));
    if ((p['playing'] as bool?) ?? false) {
      unawaited(svc.resume());
    } else {
      unawaited(svc.pauseOnly());
    }
  }

  // ── G9 cl65：断线重连（仅客户端）───────────────────

  /// 开始重连：关闭旧节点，进入 reconnecting 态，调度首次尝试。
  /// 保留 hostIp/port/seed/options/peers，使世界在重连期间继续渲染。
  Future<void> _beginReconnect() async {
    if (_reconnecting) return;
    _reconnecting = true;
    _reconnectAttempt = 0;
    _joined = Completer<void>();
    state = state.copyWith(
      status: ConnStatus.reconnecting,
      error: null,
      reconnectAttempt: 0,
    );
    await _node?.close().catchError((_) {});
    _node = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectAttempt++;
    if (_reconnectAttempt > _kReconnectMaxAttempts) {
      _failReconnect();
      return;
    }
    final int sec = math.min(
      _kReconnectMaxBackoff.inSeconds,
      (_kReconnectBase.inMilliseconds *
              math.pow(2, _reconnectAttempt - 1) /
              1000)
          .ceil(),
    );
    state = state.copyWith(reconnectAttempt: _reconnectAttempt);
    _reconnectTimer = Timer(Duration(seconds: sec), _attemptReconnect);
  }

  Future<void> _attemptReconnect() async {
    if (!_reconnecting) return;
    final String? ip = state.hostIp;
    final int? port = state.port;
    if (ip == null || port == null) {
      _failReconnect();
      return;
    }
    try {
      _node = await NetNode.connect(ip, port);
      state = state.copyWith(localId: _node!.localId);
      _subscribe();
      _sendHello();
      await _joined!.future.timeout(const Duration(seconds: 6));
      // 重连成功：恢复连接态，清空重连状态并回调（供世界视图清远端缓存）。
      _reconnecting = false;
      _reconnectAttempt = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      state = state.copyWith(
        status: ConnStatus.connected,
        reconnectAttempt: 0,
      );
      onReconnected?.call();
    } catch (_) {
      if (!_reconnecting) return;
      if (_reconnectAttempt >= _kReconnectMaxAttempts) {
        _failReconnect();
      } else {
        _scheduleReconnect();
      }
    }
  }

  void _failReconnect() {
    _reconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _node = null;
    state = state.copyWith(
      status: ConnStatus.error,
      error: '连接已断开，无法重连',
      role: NetRole.offline,
      reconnectAttempt: 0,
    );
  }

  /// 取消重连（用户主动离开时调用）。
  void _cancelReconnect() {
    _reconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// 离开联机（保持世界，仅断开连接）。
  Future<void> leave() async {
    _intentionalLeave = true;
    _cancelReconnect();
    if (_node != null) {
      _node!.send(NetMessage(
        type: NetMsgType.bye,
        from: state.localId ?? '',
        payload: const <String, dynamic>{},
      ));
      await _node!.close();
    }
    _posTimer?.cancel();
    _posTimer = null;
    try {
      _beacon?.close();
    } catch (_) {}
    _beacon = null;
    _node = null;
    _djListeners = false;
    onRemoteEdit = null;
    onRemoteTransform = null;
    onReconnected = null;
    editSnapshotProvider = null;
    onEditSnapshot = null;
    _intentionalLeave = false;
    state = const NetSessionState();
  }

  @override
  void dispose() {
    _intentionalLeave = true;
    _cancelReconnect();
    _posTimer?.cancel();
    try {
      _beacon?.close();
    } catch (_) {}
    unawaited(_node?.close());
    super.dispose();
  }
}
