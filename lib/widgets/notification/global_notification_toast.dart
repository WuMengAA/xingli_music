import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/notification_event.dart';
import '../../providers/settings/notification_providers.dart';

/// 全局通知 toast（R26r21·重构）：右上角，3 秒动画（0.35s 右下滑入 → 上浮 →
/// 驻留 → 0.6s 右滑出），每条新事件 = 一次**全新** OverlayEntry（自包含动画、
/// 结束自动 remove），避免长生命周期 widget 的 InheritedElement dependents
/// 累积（框架 `dependents.isEmpty` 断言）。
///
/// `GlobalNotificationToast` 本身只是一个监听者（const 挂在 AppShell），
/// 监听 `recentNotificationsProvider` 新事件 → 插入 `_ToastOverlayEntry`。
class GlobalNotificationToast extends ConsumerWidget {
  const GlobalNotificationToast({super.key});

  /// 当前正在显示的 toast（全局唯一）——右上角只保留最后一个，新事件覆盖旧的。
  static OverlayEntry? _active;
  /// 去重键：与上一条完全相同（标题+正文）则跳过，避免「从复」刷屏。
  static String? _lastKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<List<NotificationEvent>>(recentNotificationsProvider,
        (List<NotificationEvent>? prev, List<NotificationEvent> next) {
      if (next.isEmpty) return;
      final NotificationEvent e = next.first;
      final String key = '${e.title} ${e.message}';
      // 去重：与上一条正在显示的内容完全一致 → 直接跳过（删除多余从复）。
      if (_lastKey == key) return;
      _lastKey = key;
      _show(context, e);
    });
    return const SizedBox.shrink();
  }

  void _show(BuildContext context, NotificationEvent e) {
    _active?.remove(); // 只保留最后一个：先移除上一条
    final OverlayState overlay = Overlay.of(context, rootOverlay: false);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (BuildContext _) => _ToastCard(
        event: e,
        onFinish: () {
          if (entry.mounted) entry.remove();
          if (_active == entry) _active = null;
          // 结束后清空去重键 → 下次再来相同内容允许重新弹出
          _lastKey = null;
        },
      ),
    );
    _active = entry;
    overlay.insert(entry);
  }
}

/// 单条 toast（自包含 3 秒动画 + 自动卸载）。
class _ToastCard extends StatefulWidget {
  const _ToastCard({required this.event, required this.onFinish});

  final NotificationEvent event;
  final VoidCallback onFinish;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _offset;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _offset = TweenSequence<Offset>(<TweenSequenceItem<Offset>>[
      TweenSequenceItem<Offset>(
        tween: Tween<Offset>(
          begin: const Offset(1.0, 0.18),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 0.35,
      ),
      TweenSequenceItem<Offset>(
        tween: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(0, -0.02),
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 0.45,
      ),
      TweenSequenceItem<Offset>(
        tween: ConstantTween<Offset>(const Offset(0, -0.02)),
        weight: 1.60,
      ),
      TweenSequenceItem<Offset>(
        tween: Tween<Offset>(
          begin: const Offset(0, -0.02),
          end: const Offset(1.05, -0.02),
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 0.60,
      ),
    ]).animate(_ctrl);
    _opacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 0.12,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1),
        weight: 2.68,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 0.20,
      ),
    ]).animate(_ctrl);
    _ctrl.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) widget.onFinish();
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // R26fix：滑入/滑出用 SlideTransition（偏移 = **相对自身尺寸**的比例，
    // 而非屏幕全宽平移）——原 Transform.translate 用 width×1.0 会横跨整屏，
    // 视觉上「沾满屏幕」。现在从右侧滑入自身宽度（≤1/3 屏），紧凑小弹条。
    return IgnorePointer(
      child: Positioned(
        right: AppSpace.md,
        top: MediaQuery.paddingOf(context).top + AppSpace.md,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (BuildContext context, Widget? _) => FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _offset,
              child: Container(
                    // R26r21d：超紧凑小弹条——双行改单行、padding/圆点缩小；
                    // cl28+：宽度不超过屏幕 1/3（至多 240，绝不占全屏）。
                    // R26fx2：改固定宽度（替代 maxWidth 约束）——Positioned 右侧
                    // 对齐 + 固定宽 + 单行 ellipsis，任何内容都不可能撑满屏幕。
                    width: MediaQuery.sizeOf(context).width / 3 < 240
                        ? MediaQuery.sizeOf(context).width / 3
                        : 240,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      context.appColors.bgCard.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.appColors.border),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.appColors.accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: widget.event.title,
                              style: context.appText.caption.copyWith(
                                color: context.appColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.event.message.isNotEmpty)
                              TextSpan(
                                text: ' · ${widget.event.message}',
                                style: context.appText.caption.copyWith(
                                  color: context.appColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}