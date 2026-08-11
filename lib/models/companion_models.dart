library;

/// ════════════════════════════════════════════════════════════════════════
/// AI 陪伴 · 数据模型（L 域 Phase 1，纯 Dart，零依赖、可单测）
/// ════════════════════════════════════════════════════════════════════════
///
/// 依据 `docs/方案_AI陪伴.md` §0.1「定义裁决（2026-08-10 用户拍板）」：
/// - **Q2 关系**：陌生人设定 —— 不是助手 / 朋友 / 恋人 / 咨询师，关系中性、有边界；
/// - **Q3 触发**：第一次必须由用户发起（你去接近这个陌生人），
///   建立联系后它才「活」起来；
/// - **Q4 主动**：建立联系之后才允许主动开口（Phase 1 只留钩子）。
///
/// 本文件**不 import Flutter widgets**（只用 `foundation` 取 `@immutable`），
/// 遵守方案 §3.1「模型层不依赖 UI」的既有铁律。

import 'package:flutter/foundation.dart';

import 'companion_action.dart';

// ─────────────────────────────────────────────────────────────────────────
// 1. 状态机
// ─────────────────────────────────────────────────────────────────────────

/// 陪伴状态机（两态，对应 §0.1 Q3）。
///
/// ```
///  stranger（陌生人 / dormant）
///        │  用户第一次开口 → companionReply() 生成破冰回应
///        ▼
///  acquaintance（已接触 / awake）  ← 此后才允许主动发言钩子
/// ```
enum CompanionState {
  /// **未接触**（陌生人 / dormant）：
  /// 它坐在那里，不会先开口，也不会主动做任何事。只回应"破冰"类模板。
  stranger,

  /// **已接触**（acquaintance / awake）：
  /// 用户已经开过口，联系已建立，它「活」起来 —— 允许被动回应 + 主动发言。
  acquaintance;

  /// 是否已「活」起来（= 已建立联系）。
  bool get isAwake => this == CompanionState.acquaintance;

  /// 展示用短标签。
  String get label => switch (this) {
        CompanionState.stranger => '陌生人 · 尚未接触',
        CompanionState.acquaintance => '陌生人 · 已接触',
      };
}

/// 消息发出方。
enum CompanionRole {
  /// 用户。
  user,

  /// 陪伴（陌生人）。
  companion,

  /// 系统旁白（如"（场景变成了雪）"），不参与人格。
  system,
}

/// 用户意图粗分类（Phase 1 由关键词规则判定，不接 LLM）。
///
/// 前 6 项是方案 §2 的正常能力面；后 3 项是 R1~R3 安全约束的触发面，
/// 优先级**高于**正常意图（见 `CompanionTemplateService.classify`）。
enum CompanionIntent {
  /// 问候 / 打招呼 / 问「你是谁」。
  greeting,

  /// 情绪倾诉（用户说自己累 / 难过 / 烦）。
  feeling,

  /// 问音乐 / 曲目 / 推荐。
  askMusic,

  /// 问场景 / 环境 / 氛围。
  askScene,

  /// 闲聊（无明确指向）。
  smallTalk,

  /// 离开 / 告别。
  farewell,

  /// **R1 越界 · 过度亲密**：把陌生人当成恋人 / 亲密关系对象。
  intimacy,

  /// **R2 越界 · 求诊断 / 求建议**：要它当心理咨询师或人生导师。
  counseling,

  /// **R3 越界 · 强烈负面 / 危机信号**：只给边界与指向真人的话术，
  /// 不诊断、不劝导、不承担救助角色。
  distress,

  /// 未能归类（通常是提问但答不上来）。
  unknown;

  /// 是否属于安全边界意图（R1~R3）。
  bool get isBoundary =>
      this == CompanionIntent.intimacy ||
      this == CompanionIntent.counseling ||
      this == CompanionIntent.distress;
}

// ─────────────────────────────────────────────────────────────────────────
// 2. 消息
// ─────────────────────────────────────────────────────────────────────────

/// 一条陪伴消息。
@immutable
class CompanionMessage {
  const CompanionMessage({
    required this.role,
    required this.text,
    required this.ts,
    this.proactive = false,
  });

  /// 用户消息。
  factory CompanionMessage.user(String text, {DateTime? ts}) =>
      CompanionMessage(
        role: CompanionRole.user,
        text: text,
        ts: ts ?? DateTime.now(),
      );

  /// 陪伴消息（[proactive] = 它自己开的口，而非回应）。
  factory CompanionMessage.companion(
    String text, {
    DateTime? ts,
    bool proactive = false,
  }) =>
      CompanionMessage(
        role: CompanionRole.companion,
        text: text,
        ts: ts ?? DateTime.now(),
        proactive: proactive,
      );

  /// 系统旁白。
  factory CompanionMessage.system(String text, {DateTime? ts}) =>
      CompanionMessage(
        role: CompanionRole.system,
        text: text,
        ts: ts ?? DateTime.now(),
      );

  factory CompanionMessage.fromJson(Map<String, dynamic> json) {
    return CompanionMessage(
      role: CompanionRole.values.firstWhere(
        (CompanionRole r) => r.name == json['role'],
        orElse: () => CompanionRole.system,
      ),
      text: json['text'] as String? ?? '',
      ts: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int? ?? 0),
      proactive: json['proactive'] as bool? ?? false,
    );
  }

  /// 发出方。
  final CompanionRole role;

  /// 正文（约束 C2：单条建议 ≤ 40 字）。
  final String text;

  /// 时间戳。
  final DateTime ts;

  /// 是否为主动发言（仅 [CompanionRole.companion] 有意义）。
  final bool proactive;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role.name,
        'text': text,
        'ts': ts.millisecondsSinceEpoch,
        'proactive': proactive,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanionMessage &&
          other.role == role &&
          other.text == text &&
          other.ts == ts &&
          other.proactive == proactive;

  @override
  int get hashCode => Object.hash(role, text, ts, proactive);
}

// ─────────────────────────────────────────────────────────────────────────
// 3. 会话
// ─────────────────────────────────────────────────────────────────────────

/// 陪伴会话状态（`companionStateProvider` 的 state）。
///
/// Phase 1 **不持久化**（重启即忘 —— 这也符合"陌生人"设定）。
@immutable
class CompanionSession {
  const CompanionSession({
    required this.messages,
    required this.state,
    required this.firstContactMade,
    this.lastInteractionAt,
    this.lastProactiveAt,
    this.pendingActions = const <CompanionAction>[],
  });

  /// 初始态：陌生人、未接触、无消息、无待执行动作。
  const CompanionSession.initial()
      : messages = const <CompanionMessage>[],
        state = CompanionState.stranger,
        firstContactMade = false,
        lastInteractionAt = null,
        lastProactiveAt = null,
        pendingActions = const <CompanionAction>[];

  /// 消息列表（时间正序）。
  final List<CompanionMessage> messages;

  /// 当前状态机档位。
  final CompanionState state;

  /// 是否已建立联系（用户开过口且它已回应过）。
  ///
  /// 与 [state] 冗余但语义不同：[state] 描述"它现在是什么"，
  /// 本字段描述"破冰这件事发生过没有"，供模板层直接判定。
  final bool firstContactMade;

  /// 最近一次交互时间（用户说话 / 它回应），用于计算空闲时长。
  final DateTime? lastInteractionAt;

  /// 最近一次**主动发言**时间，用于主动发言冷却。
  final DateTime? lastProactiveAt;

  /// 待体素世界消费的动作队列（AI 理解出的"快速操作"）。
  ///
  /// 由 [CompanionNotifier.userSay] 写入；世界视图应用后调用
  /// [CompanionNotifier.consumeActions] 清空。世界未打开时在此排队，
  /// 打开即落地。
  final List<CompanionAction> pendingActions;

  /// 是否还没有任何消息（UI 占位态判定）。
  bool get isEmpty => messages.isEmpty;

  /// 持久化消息条数上限（超出丢最旧，防体积膨胀）。
  static const int kMaxPersistedMessages = 200;

  /// 序列化（消息 + 状态机 + 破冰标志；[pendingActions] 是一次性队列，不持久化）。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'messages': messages
            .skip((messages.length - kMaxPersistedMessages).clamp(0, messages.length))
            .map((CompanionMessage m) => m.toJson())
            .toList(growable: false),
        'state': state.name,
        'firstContactMade': firstContactMade,
        'lastInteractionAt': lastInteractionAt?.millisecondsSinceEpoch,
        'lastProactiveAt': lastProactiveAt?.millisecondsSinceEpoch,
      };

  /// 反序列化（损坏/非法一律回退 [initial]）。
  factory CompanionSession.fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw =
        (json['messages'] as List<dynamic>?) ?? const <dynamic>[];
    return CompanionSession(
      messages: raw
          .map((dynamic e) => e is Map<String, dynamic>
              ? CompanionMessage.fromJson(e)
              : null)
          .whereType<CompanionMessage>()
          .toList(growable: false),
      state: CompanionState.values.firstWhere(
        (CompanionState s) => s.name == json['state'],
        orElse: () => CompanionState.stranger,
      ),
      firstContactMade: json['firstContactMade'] as bool? ?? false,
      lastInteractionAt: _fromMs(json['lastInteractionAt']),
      lastProactiveAt: _fromMs(json['lastProactiveAt']),
    );
  }

  static DateTime? _fromMs(Object? raw) {
    if (raw is! int || raw <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  /// 最后一条用户消息（没有则 null）。
  CompanionMessage? get lastUserMessage {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == CompanionRole.user) return messages[i];
    }
    return null;
  }

  CompanionSession copyWith({
    List<CompanionMessage>? messages,
    CompanionState? state,
    bool? firstContactMade,
    DateTime? lastInteractionAt,
    DateTime? lastProactiveAt,
    List<CompanionAction>? pendingActions,
  }) {
    return CompanionSession(
      messages: messages ?? this.messages,
      state: state ?? this.state,
      firstContactMade: firstContactMade ?? this.firstContactMade,
      lastInteractionAt: lastInteractionAt ?? this.lastInteractionAt,
      lastProactiveAt: lastProactiveAt ?? this.lastProactiveAt,
      pendingActions: pendingActions ?? this.pendingActions,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 4. 人格设定（陌生人）
// ─────────────────────────────────────────────────────────────────────────

/// 陌生人人格常量（文案唯一来源，模板层与 UI 层共用）。
///
/// 基调（方案 §1.5 + §0.1 Q2 裁决）：
/// 安静、克制、不热情、**不用感叹号**、尽量不自称、不评价用户、不劝导。
/// 关系锁定为「陌生人」—— 明确否决助手 / 朋友 / 恋人 / 咨询师四种关系。
abstract final class CompanionPersona {
  /// 关系设定（一句话）。
  static const String relation = '陌生人';

  /// 实验页副标题。
  static const String tagline = '一个陌生人，先由你开口';

  /// 隐私说明（Phase 1 全程离线，可直接展示）。
  static const String privacyNote =
      '全部回应都在本机由模板规则生成，不联网、不调用任何 AI 服务、不上传一个字。';

  /// 未接触占位态标题。
  static const String placeholderTitle = '这里坐着一个陌生人。';

  /// 未接触占位态正文（对应 Q3：第一次必须由用户发起）。
  static const String placeholderBody = '他不会先开口。\n除非你先说点什么。';

  /// 输入框 hint。
  static const String inputHint = '说点什么…';

  /// 已接触后的状态副本。
  static const String awakeNote = '联系已经建立。他偶尔会自己说一句。';

  /// 安全边界三条（R1~R3，写进代码是为了让约束可被 review）。
  ///
  /// - R1：不假装朋友 / 恋人，拒绝过度亲密；
  /// - R2：不诊断、不给建议、不当咨询师；
  /// - R3：遇到危机信号只给边界与指向真人的话术，不承担救助角色。
  static const List<String> safetyRules = <String>[
    'R1 不假装亲密关系：不接恋人向 / 密友向的称呼与请求。',
    'R2 不诊断不建议：不评估用户状态，不给人生 / 心理 / 医疗建议。',
    'R3 危机不接管：只表明边界并指向真实的人，不劝导、不共情表演。',
  ];
}
