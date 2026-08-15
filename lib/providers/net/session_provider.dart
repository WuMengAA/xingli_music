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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../services/audio/audio_service.dart';
import '../../providers/audio/audio_providers.dart';
import '../../services/net/lan_discovery.dart';
import '../../services/net/net_message.dart';
import '../../services/net/net_node.dart';

// ── 角色 / 连接状态 ─────────────────────────────────────

enum NetRole { offline, host, client }

enum ConnStatus { idle, connecting, connected, error }

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
      );
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
      state = state.copyWith(status: ConnStatus.error, error: '主持失败：$e');
      await _node?.close();
      _node = null;
      return false;
    }
  }

  // ── 加入 ──
  Future<bool> join(String ip, int port, {String name = '玩家'}) async {
    if (_node != null) return false;
    _joined = Completer<void>();
    try {
      state = state.copyWith(
        status: ConnStatus.connecting,
        hostIp: ip,
        port: port,
        localName: name,
        error: null,
      );
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
        error: '连接失败：$e',
      );
      await _node?.close();
      _node = null;
      return false;
    }
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
    } else if (e is NetPeerDisconnected) {
      state = state.copyWith(
        peers: state.peers.where((p) => p.id != e.peerId).toList(),
      );
    } else if (e is NetClosed) {
      state = state.copyWith(
        status: ConnStatus.error,
        error: '连接已断开',
        role: NetRole.offline,
      );
    } else if (e is NetMessageEvent) {
      _onMessage(e.from, e.message);
    }
  }

  void _onMessage(String from, NetMessage msg) {
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
        if (state.peer(id) == null) {
          state = state.copyWith(
            peers: <PeerInfo>[...state.peers, PeerInfo(id: id)],
          );
        }
        break;

      case NetMsgType.peerLeave:
        final String id = msg.payload['id'] as String? ?? from;
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

      case NetMsgType.vitals:
        final PeerInfo? p = state.peer(from);
        if (p != null) {
          state = state.copyWith(
            peers: state.peers
                .map((pp) => pp.id == from
                    ? pp.copyWith(
                        health: msg.payload['hp'] as int? ?? pp.health,
                        hunger: msg.payload['hg'] as int? ?? pp.hunger,
                        xp: msg.payload['xp'] as int? ?? pp.xp,
                      )
                    : pp)
                .toList(),
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

  /// 广播生命 / 饥饿 / 经验。
  void broadcastVitals(int health, int hunger, int xp) {
    if (_node == null) return;
    _node!.send(NetMessage(
      type: NetMsgType.vitals,
      from: state.localId ?? '',
      payload: <String, dynamic>{'hp': health, 'hg': hunger, 'xp': xp},
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

  /// 离开联机（保持世界，仅断开连接）。
  Future<void> leave() async {
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
    state = const NetSessionState();
  }

  @override
  void dispose() {
    _posTimer?.cancel();
    try {
      _beacon?.close();
    } catch (_) {}
    unawaited(_node?.close());
    super.dispose();
  }
}
