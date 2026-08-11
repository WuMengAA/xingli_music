import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/companion_models.dart';
import '../../providers/companion/companion_providers.dart';
import 'companion_bubble.dart';

/// 浮层几何常量（同文件内多个私有 Widget 共享）。
///
/// 收起态是**贴右边缘的窄把手**（14×64），不是圆形 FAB ——
/// 圆形 FAB 会压住播放面板右侧按钮与弹窗「同意/确认」，导致点击被吞。
const double _kHandleW = 14;
const double _kHandleH = 64;

/// 展开卡片距底部的间距（避让 Dock + 播放面板）。
const double _kFabBottom = 96;
const double _kCardW = 320;
const double _kCardH = 420;

/// ════════════════════════════════════════════════════════════════════════
/// AI 陪伴 · 全局浮层（Phase 2 接入 app_shell）
/// ════════════════════════════════════════════════════════════════════════
///
/// - 默认收起为右下角小圆点；点击展开为聊天气泡（复用 [CompanionBubble]）。
/// - 陌生人设定：未建立联系（[CompanionSession.firstContactMade]==false）时
///   浮层不主动发言，仅作占位提示，由用户在气泡里先开口。
/// - 建立联系后，定时器周期性触发 [tryProactive]，AI 可主动开口；
///   未展开时以红点点亮提示。
class CompanionGlobalFab extends ConsumerStatefulWidget {
  const CompanionGlobalFab({super.key});

  @override
  ConsumerState<CompanionGlobalFab> createState() => _CompanionGlobalFabState();
}

class _CompanionGlobalFabState extends ConsumerState<CompanionGlobalFab> {
  bool _expanded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 主动发言轮询：仅建立联系后，让 AI 偶尔主动开口（不诊断/不咨询/不假装朋友）。
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      final CompanionSession s = ref.read(companionStateProvider);
      if (s.firstContactMade) {
        ref.read(companionStateProvider.notifier).tryProactive(120);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final CompanionSession session = ref.watch(companionStateProvider);
    final bool showDot = !_expanded &&
        session.messages.isNotEmpty &&
        session.messages.last.role == CompanionRole.companion &&
        session.messages.last.proactive;

    // 关键：FAB 本体整片区域默认不拦截指针（全屏 IgnorePointer 透明层），
    // 只把手与展开卡片可交互，避免铺满全屏的容器吞掉下层页面点击。
    return Stack(
      children: <Widget>[
        const Positioned.fill(
          child: IgnorePointer(child: SizedBox.expand()),
        ),
        if (_expanded)
          Positioned(
            right: AppSpace.sm,
            bottom: _kFabBottom,
            child: _ExpandedCard(onClose: _toggle),
          ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: _Handle(
              expanded: _expanded,
              showDot: showDot,
              onTap: _toggle,
            ),
          ),
        ),
      ],
    );
  }
}

/// 贴右边缘的窄把手（收起态入口）。
class _Handle extends StatelessWidget {
  const _Handle({
    required this.expanded,
    required this.showDot,
    required this.onTap,
  });

  final bool expanded;
  final bool showDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg =
        expanded ? context.appColors.bgSurfaceSunken : context.appColors.accent;
    return Semantics(
      button: true,
      label: expanded ? '收起 AI 陪伴' : '打开 AI 陪伴',
      child: Material(
        color: bg,
        elevation: 4,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(AppRadius.md),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(AppRadius.md),
          ),
          child: SizedBox(
            width: _kHandleW,
            height: _kHandleH,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Icon(
                  expanded
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
                  size: AppSize.iconSm,
                  color: expanded
                      ? context.appColors.textSecondary
                      : context.appColors.onAccent,
                ),
                if (showDot)
                  const Positioned(
                    top: 8,
                    child: _RedDot(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RedDot extends StatelessWidget {
  const _RedDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFFE5484D),
          shape: BoxShape.circle,
        ),
      );
}

class _ExpandedCard extends ConsumerWidget {
  const _ExpandedCard({required this.onClose});
  final VoidCallback onClose;

  /// 快捷指令：点一下即"让 AI 理解并执行"，等价于对 AI 说一句自然语言。
  static const List<(String, String)> _quick = <(String, String)>[
    ('去水边', '去水边'),
    ('去树下', '去树下'),
    ('看山顶', '看山顶'),
    ('转一圈', '转一圈'),
    ('关声音', '关掉世界音效'),
    ('开声音', '打开世界音效'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 小屏 / 横屏兜底：卡片不得超出可用区域，否则会 overflow。
    final Size screen = MediaQuery.sizeOf(context);
    final double w = _kCardW.clamp(0.0, screen.width - AppSpace.md * 2);
    final double h = _kCardH.clamp(
      0.0,
      (screen.height - _kFabBottom - AppSpace.lg).clamp(160.0, _kCardH),
    );

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      color: context.appColors.bgSurface,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: SizedBox(
          width: w,
          height: h,
          child: Column(
            children: <Widget>[
              _CardHeader(onClose: onClose),
              const Expanded(child: CompanionBubble()),
              _QuickChips(
                onTap: (String text) =>
                    ref.read(companionStateProvider.notifier).userSay(text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部一排快捷指令：把"AI 理解并快速操作"做成一键入口。
class _QuickChips extends StatelessWidget {
  const _QuickChips({required this.onTap});
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm,
          AppSpace.sm),
      decoration: BoxDecoration(
        color: context.appColors.bgSurfaceSunken,
        border: Border(top: BorderSide(color: context.appColors.border)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final (String label, String cmd) in _ExpandedCard._quick)
            InkWell(
              onTap: () => onTap(cmd),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.appColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: context.appColors.accent.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  label,
                  style: context.appText.body.copyWith(
                    color: context.appColors.accent,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      decoration: BoxDecoration(
        color: context.appColors.bgSurfaceSunken,
        border: Border(
          bottom: BorderSide(color: context.appColors.border),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.person_outline_rounded,
              size: AppSize.iconSm, color: context.appColors.textSecondary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'AI 陪伴',
              style: context.appText.body.copyWith(
                color: context.appColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close_rounded,
                size: AppSize.iconSm, color: context.appColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

