library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/companion_action.dart';
import '../../models/companion_models.dart';
import '../../services/companion/companion_template_service.dart';
import '../../services/llm/llm_client.dart';
import '../settings/llm_providers.dart';
import '../storage/storage_providers.dart';

/// ════════════════════════════════════════════════════════════════════════
/// AI 陪伴 · 状态 Provider（Phase 1 本地模板内核 + 聊天历史持久化）
/// ════════════════════════════════════════════════════════════════════════
///
/// - `companionStateProvider`：持有 [CompanionSession]（消息 + 状态机 + 接触标志）；
/// - 用户通过 `userSay` 开口，`companionReply` 由模板内核同步生成；
/// - `tryProactive` 供 UI 定时调用主动发言钩子（Q4）；
/// - `reset` 回到陌生人初始态；
/// - **聊天历史持久化**：每次状态变化写 SharedPreferences（JSON，最多
///   [CompanionSession.kMaxPersistedMessages] 条），冷启动自动恢复——
///   它仍记得你说过的话（符合"记忆"能力，不改变陌生人关系设定）。
/// - 后续接入第三方大模型时，同一段历史可直接作上下文喂给 LLM。

/// 模板内核服务（无状态单例）。
final Provider<CompanionTemplateService> companionTemplateServiceProvider =
    Provider<CompanionTemplateService>(
  (Ref ref) => const CompanionTemplateService(),
);

/// 持久化键（JSON 串）。
const String kCompanionHistoryKey = 'companion.history.v1';

/// LLM 系统提示词（保持"陌生人"设定：安静克制、有边界，不假装熟络）。
const String _kLlmSystemPrompt =
    '你是一个安静克制的陌生人，与用户没有亲密关系。'
    '回答要简短（一般不超过 40 字），尽量不用感叹号，'
    '不评价用户、不劝导、不假装熟络。'
    '用户在玩一个音乐与体素世界的应用，可能与你聊音乐、场景或生活话题；'
    '若用户提到"去水边 / 树下 / 山顶 / 转一圈 / 开关声音"这类世界操作，'
    '先用一句话确认，再用动作描述回应。';

/// 第三方大模型回复回调（有配置返回 LLM 文本；无配置/失败返回 null 走模板）。
typedef LlmReplyFn = Future<String?> Function(List<CompanionMessage> history);

/// 陪伴会话状态。
final StateNotifierProvider<CompanionNotifier, CompanionSession>
    companionStateProvider =
    StateNotifierProvider<CompanionNotifier, CompanionSession>(
  (Ref ref) => CompanionNotifier(
    ref.watch(companionTemplateServiceProvider),
    persist: (CompanionSession s) =>
        _saveCompanion(ref.read(prefsProvider), s),
    load: () => _loadCompanion(ref.read(prefsProvider)),
    llmReply: _buildLlmReply(ref),
  ),
);

/// 构造 LLM 回复回调：配置齐全才真正调模型，失败一律返回 null（模板兜底）。
LlmReplyFn _buildLlmReply(Ref ref) {
  return (List<CompanionMessage> history) async {
    final LlmConfig config = ref.read(llmConfigProvider);
    if (!config.valid) return null;
    final Iterable<LlmMessage> recent = history
        .skip((history.length - 30).clamp(0, history.length))
        .map(
          (CompanionMessage m) => LlmMessage(
            role: switch (m.role) {
              CompanionRole.user => 'user',
              CompanionRole.companion => 'assistant',
              CompanionRole.system => 'system',
            },
            content: m.text,
          ),
        );
    final List<LlmMessage> messages = <LlmMessage>[
      const LlmMessage(role: 'system', content: _kLlmSystemPrompt),
      ...recent,
    ];
    try {
      return await ref
          .read(llmClientProvider)
          .chat(config: config, messages: messages);
    } catch (_) {
      return null; // LLM 不可用 → 上层回退模板
    }
  };
}

CompanionSession? _loadCompanion(SharedPreferences prefs) {
  final String? raw = prefs.getString(kCompanionHistoryKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    return CompanionSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null; // 损坏历史：回退陌生人初始态
  }
}

void _saveCompanion(SharedPreferences prefs, CompanionSession session) {
  try {
    unawaited(prefs.setString(kCompanionHistoryKey, jsonEncode(session.toJson())));
  } catch (_) {
    // 持久化失败不影响会话
  }
}

/// 陪伴会话状态机驱动器。
class CompanionNotifier extends StateNotifier<CompanionSession> {
  CompanionNotifier(
    this._service, {
    required this.persist,
    required this.load,
    this.llmReply,
  }) : super(const CompanionSession.initial()) {
    restore();
  }

  final CompanionTemplateService _service;
  final void Function(CompanionSession) persist;
  final CompanionSession? Function() load;

  /// 第三方大模型回复回调（null = 未配置，全部走模板内核）。
  final LlmReplyFn? llmReply;

  /// 冷启动恢复聊天历史（有则替换初始态）。
  void restore() {
    final CompanionSession? saved = load();
    if (saved != null && !saved.isEmpty) {
      state = saved;
    }
  }

  /// 用户开口。
  ///
  /// 把用户消息入列，并**立即**用模板内核生成一条陪伴回应；
  /// 首次开口即建立联系（[firstContactMade]=true、状态切到 [CompanionState.acquaintance]）。
  void userSay(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return;

    final CompanionMessage userMsg = CompanionMessage.user(text);

    // 用"接触前"标志决定本次回应是否走破冰分支。
    final String replyText = _service.respond(
      state: state.state,
      firstContactMade: state.firstContactMade,
      userText: text,
    );
    final CompanionMessage reply = CompanionMessage.companion(replyText);

    // 理解用户意图 → 派生可在体素世界落地的"快速操作"（离线关键词）。
    final List<CompanionAction> actions = _service.deriveActions(text);

    final DateTime now = DateTime.now();
    state = state.copyWith(
      messages: <CompanionMessage>[...state.messages, userMsg, reply],
      // 任何一次开口都建立联系。
      state: CompanionState.acquaintance,
      firstContactMade: true,
      lastInteractionAt: now,
      pendingActions: <CompanionAction>[...state.pendingActions, ...actions],
    );
    persist(state);
  }

  /// 体素世界消费完待执行动作后调用，清空队列。
  void consumeActions() {
    if (state.pendingActions.isEmpty) return;
    state = state.copyWith(pendingActions: const <CompanionAction>[]);
    persist(state);
  }

  /// 智能开口（UI 发送统一走这里）：
  ///
  /// 1. 用户消息立即入列（含世界操作派生），先落历史；
  /// 2. 若配置了第三方大模型 → 异步调 LLM 生成回复（带最近 30 条上下文 +
  ///    "陌生人"系统提示词）；LLM 失败 / 未配置 → 回退离线模板即时回复；
  /// 3. 回复入列并持久化。
  Future<void> userSaySmart(String raw) async {
    final String text = raw.trim();
    if (text.isEmpty) return;

    final DateTime now = DateTime.now();
    final CompanionMessage userMsg = CompanionMessage.user(text);
    final List<CompanionAction> actions = _service.deriveActions(text);

    // 先入列用户消息（任何一次开口都建立联系）。
    state = state.copyWith(
      messages: <CompanionMessage>[...state.messages, userMsg],
      state: CompanionState.acquaintance,
      firstContactMade: true,
      lastInteractionAt: now,
      pendingActions: <CompanionAction>[...state.pendingActions, ...actions],
    );
    persist(state);

    // 回复：优先 LLM，失败/未配置回退模板。
    String replyText;
    final String? llm = llmReply == null ? null : await _safeLlm();
    if (llm == null || llm.isEmpty) {
      replyText = _service.respond(
        state: state.state,
        firstContactMade: state.firstContactMade,
        userText: text,
      );
    } else {
      replyText = llm;
    }

    state = state.copyWith(
      messages: <CompanionMessage>[
        ...state.messages,
        CompanionMessage.companion(replyText),
      ],
      lastInteractionAt: DateTime.now(),
    );
    persist(state);
  }

  Future<String?> _safeLlm() async {
    try {
      return await llmReply!(state.messages);
    } catch (_) {
      return null;
    }
  }

  /// 主动发言钩子（供 UI 定时调用）。
  ///
  /// 仅在已建立联系、空闲超阈值且过冷却时，由内核挑一句环境闲话入列
  /// （[CompanionMessage.proactive]=true）。其余情况静默无操作。
  void tryProactive(int idleSeconds) {
    if (!state.firstContactMade) return;

    final String? line = _service.maybeProactive(
      state: state.state,
      firstContactMade: state.firstContactMade,
      idleSeconds: idleSeconds,
      lastProactiveAt: state.lastProactiveAt,
    );
    if (line == null) return;

    final CompanionMessage msg = CompanionMessage.companion(
      line,
      proactive: true,
    );
    state = state.copyWith(
      messages: <CompanionMessage>[...state.messages, msg],
      lastProactiveAt: msg.ts,
      lastInteractionAt: msg.ts,
    );
    persist(state);
  }

  /// 回到陌生人初始态（清空消息、断联），并清除持久化历史。
  void reset() {
    state = const CompanionSession.initial();
    persist(state);
  }
}
