import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/notification_event.dart';
import '../../providers/settings/notification_providers.dart';

/// 全局通知 toast（R27·重写）：
///
/// - **挂在 rootOverlay（最顶层）**：`Overlay.of(context, rootOverlay: true)`，
///   不再被任何 `Dialog` / `BottomSheet` 的 `ModalBarrier` 灰罩盖住
///   （修复安卓上「被弹层遮住 + 灰罩盖满屏看不到」）。
/// - **可同时堆叠多条**：右上角纵向排列，最多 [kMaxToasts] 条；新事件不再顶掉
///   旧事件（修复「一次只显示一条」）。旧事件到时自动移除、其余自动上移补位。
/// - **全程 `IgnorePointer`**：即使叠在最上层也不拦截任何点击，绝不挡操作。
/// - **轻量去重**：同一内容且当前仍显示时跳过，避免重复事件刷屏。
///
/// `GlobalNotificationToast` 自身只是监听者（const 挂在 AppShell），
/// 监听 `recentNotificationsProvider` 新事件 → 插入一条自包含的 `_ToastCard`。
class GlobalNotificationToast extends ConsumerWidget {
  const GlobalNotificationToast({super.key});

  /// 最多同时显示条数。
  static const int kMaxToasts = 4;
  /// 单条估算高度（卡片 ≈ 32 + 间距 14），用于纵向堆叠定位。
  static const double _step = 46;

  /// 当前堆叠的 toast（索引 0 = 最新，置于最上方）。
  static final List<_ToastHandle> _active = <_ToastHandle>[];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<List<NotificationEvent>>(recentNotificationsProvider,
        (List<NotificationEvent>? prev, List<NotificationEvent> next) {
      if (next.isEmpty) return;
      final NotificationEvent e = next.first;
      final String key = '${e.title} ${e.message}';
      // 轻量去重：相同内容且当前仍显示 → 跳过（避免重复事件刷屏）。
      if (_active.any((_ToastHandle h) => h.key == key)) return;
      _show(context, e, key);
    });
    return const SizedBox.shrink();
  }

  void _show(BuildContext context, NotificationEvent e, String key) {
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    final _ToastHandle handle = _ToastHandle(key: key);
    handle.entry = OverlayEntry(
      builder: (BuildContext _) => _ToastCard(
        event: e,
        topOffset: () => _topFor(handle),
        onFinish: () {
          final int idx = _active.indexOf(handle);
          handle.entry?.remove();
          if (idx != -1) _active.removeAt(idx);
          _rebuildAll(); // 其余 toast 上移补位
        },
      ),
    );
    // 最新置顶（索引 0）。
    _active.insert(0, handle);
    // 超出上限：移除最旧的一条（立即卸载，无动画）。
    while (_active.length > kMaxToasts) {
      final _ToastHandle old = _active.removeLast();
      old.entry?.remove();
    }
    _rebuildAll(); // 新插入后让所有 toast 重新定位
    overlay.insert(handle.entry!);
  }

  /// 该 handle 的纵向偏移（索引 0 = 顶部，向下递增）。
  static double _topFor(_ToastHandle h) {
    final int i = _active.indexOf(h);
    return AppSpace.md + (i < 0 ? 0 : i) * _step;
  }

  /// 通知所有存活 toast 重新计算定位（用于增删后补位）。
  static void _rebuildAll() {
    for (final _ToastHandle h in _active) {
      h.entry?.markNeedsBuild();
    }
  }
}

/// toast 句柄：持有 OverlayEntry 与去重键。
class _ToastHandle {
  _ToastHandle({required this.key});
  OverlayEntry? entry;
  final String key;
}

/// 单条 toast（自包含 3 秒动画 + 自动卸载）。
class _ToastCard extends StatefulWidget {
  const _ToastCard({
    required this.event,
    required this.topOffset,
    required this.onFinish,
  });

  final NotificationEvent event;
  final double Function() topOffset;
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
    // 滑入/滑出用 SlideTransition（偏移 = 相对自身尺寸的比例，而非屏幕全宽平移），
    // 绝不占满屏幕；宽度固定（≤1/3 屏，至多 240）。
    return Positioned(
      right: AppSpace.md,
      top: widget.topOffset(),
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (BuildContext context, Widget? _) => FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _offset,
              child: Container(
                width: MediaQuery.sizeOf(context).width / 3 < 240
                    ? MediaQuery.sizeOf(context).width / 3
                    : 240,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
