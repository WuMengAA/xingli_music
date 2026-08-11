import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/companion_models.dart';
import '../../providers/companion/companion_providers.dart';

/// ════════════════════════════════════════════════════════════════════════
/// AI 陪伴 · 文字气泡组件（Phase 1 形态 A）
/// ════════════════════════════════════════════════════════════════════════
///
/// 组成：
/// - 未接触占位态（陌生人坐在那里，不先开口，[CompanionPersona.placeholder*]）；
/// - 消息列表（用户右 / 陪伴左，时间正序，自动滚到底）；
/// - 底部输入栏（[CompanionPersona.inputHint]）。
///
/// 本组件**只消费** `companionStateProvider`，不持有任何业务状态；
/// 直接挂进实验页即可（Phase 2 才会挂进 app_shell 做全局气泡）。
class CompanionBubble extends ConsumerWidget {
  const CompanionBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompanionSession session = ref.watch(companionStateProvider);

    return Container(
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.appColors.border),
      ),
      child: Column(
        children: <Widget>[
          // 消息区（占位 or 列表）
          Expanded(
            child: session.isEmpty
                ? _Placeholder()
                : _MessageList(messages: session.messages),
          ),
          // 输入栏
          _InputBar(),
        ],
      ),
    );
  }
}

/// 未接触占位态（陌生人 · 不先开口）。
class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.person_outline_rounded,
            size: 48,
            color: context.appColors.textTertiary,
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            CompanionPersona.placeholderTitle,
            style: context.appText.subtitle
                .copyWith(color: context.appColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            CompanionPersona.placeholderBody,
            style: context.appText.bodyMuted,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 消息列表（自动滚到底）。
class _MessageList extends StatefulWidget {
  const _MessageList({required this.messages});

  final List<CompanionMessage> messages;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_MessageList old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length) {
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: AppMotion.normal,
          curve: AppMotion.ease,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(AppSpace.md),
      itemCount: widget.messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (_, int i) => _Bubble(message: widget.messages[i]),
    );
  }
}

/// 单条气泡（用户右 / 陪伴左）。
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final CompanionMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == CompanionRole.user;
    final bool isSystem = message.role == CompanionRole.system;

    // 系统旁白：居中灰字，不气泡。
    if (isSystem) {
      return Center(
        child: Text(
          message.text,
          style: context.appText.caption,
          textAlign: TextAlign.center,
        ),
      );
    }

    // 主动发言（陪伴开的口）加一个极小标记。
    final Widget bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: isUser
            ? context.appColors.accent
            : context.appColors.bgSurfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        message.text,
        style: (isUser ? context.appText.body : context.appText.body).copyWith(
          color: isUser
              ? context.appColors.onAccent
              : context.appColors.textPrimary,
        ),
      ),
    );

    return Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: <Widget>[
        if (message.proactive && !isUser)
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.xs),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: AppSize.iconSm,
              color: context.appColors.textTertiary,
            ),
          ),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.72,
            ),
            child: bubble,
          ),
        ),
      ],
    );
  }
}

/// 底部输入栏。
class _InputBar extends ConsumerStatefulWidget {
  @override
  ConsumerState<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends ConsumerState<_InputBar> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    final String text = _ctrl.text;
    if (text.trim().isEmpty) return;
    // 智能开口：配置了大模型则异步 LLM 回复，否则模板即时回复。
    unawaited(ref.read(companionStateProvider.notifier).userSaySmart(text));
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _ctrl,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: CompanionPersona.inputHint,
                hintStyle: context.appText.hint,
                filled: true,
                fillColor: context.appColors.bgInput,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          IconButton(
            onPressed: _send,
            icon: Icon(
              Icons.send_rounded,
              color: context.appColors.accent,
              size: AppSize.icon,
            ),
          ),
        ],
      ),
    );
  }
}
