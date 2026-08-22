/// ════════════════════════════════════════════════════════════════════════
/// 联机消息协议（G9 多人联机 · 主机-客户端 + WebSocket）
/// ════════════════════════════════════════════════════════════════════════
///
/// 世界地形按 seed 确定性重现，故联机只同步**玩家编辑层 + 玩家位置/视角 +
/// 状态 + 聊天 + 一起听**，不传地形。消息统一 JSON 信封。
library;

import 'dart:convert';

/// 消息类型。索引即线上编码（勿重排，否则旧包不兼容）。
enum NetMsgType {
  hello, // 加入：上报昵称 / 是否主机
  welcome, // 主机→新成员：分配 id + 世界 seed/选项 + 成员列表
  peerJoin, // 广播：有新成员
  peerLeave, // 广播：成员离开
  transform, // 玩家位置 / 视角
  edit, // 方块编辑（破坏 / 放置），payload: x,y,z,v(方块枚举索引)
  vitals, // 生命 / 饥饿 / 经验
  chat, // 聊天
  listenState, // 一起听：当前曲目 + 播放态 + 进度
  requestListen, // 客户端请求主机当前一起听状态
  bye, // 主动离开
  ping, // 心跳
  editSnapshot, // 主机→新成员/重连：编辑层快照（已变方块+发光方块），payload: edits/lights
  requestEditSnapshot, // 客户端请求主机当前编辑层快照（防「welcome 早于 world 视图注册」竞态）
  // ── 校园点歌（电台·点歌队列子能力）──
  orderSubmit, // 听众→DJ：提交一首点歌（track + 寄语 + 匿名），payload: id,trackJson,msg,anon
  orderQueue, // DJ→全体：点歌队列快照（权威队列），payload: items:[...]
  orderDecision, // DJ→提交者：对某条点歌的审批（approve/reject），payload: id,decision
}

/// 一条网络消息（JSON 信封：t=类型 f=发送方 to=接收方(可选) p=负载）。
class NetMessage {
  NetMessage({
    required this.type,
    required this.from,
    this.to,
    required this.payload,
  });

  final NetMsgType type;
  final String from;
  final String? to;
  final Map<String, dynamic> payload;

  factory NetMessage.fromJson(Map<String, dynamic> j) => NetMessage(
        type: NetMsgType.values[(j['t'] as int?) ?? 0],
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

  /// 返回一份带 `to` 的副本（中转模式：标记定向投递目标，由中继服务器路由）。
  NetMessage withTo(String to) =>
      NetMessage(type: type, from: from, to: to, payload: payload);
}

/// 构造 vitals（生命/饥饿/经验）广播消息（纯函数，cl79 供会话层广播复用与单测）。
NetMessage buildVitalsMessage(String from, int health, int hunger, int xp) =>
    NetMessage(
      type: NetMsgType.vitals,
      from: from,
      payload: <String, dynamic>{'hp': health, 'hg': hunger, 'xp': xp},
    );
