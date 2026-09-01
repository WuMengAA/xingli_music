import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/net/session_provider.dart';
import '../../services/audio/audio_service.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 点歌悬浮窗（R32 · 需求 ④：点歌可在底部音乐媒体栏中以悬浮窗形式显示）
/// ════════════════════════════════════════════════════════════════════════
///
/// 挂在外层 Stack（播放控件之上、Dock 之下），监听 [netSessionProvider]：
/// - **DJ 端**：新到 pending 点歌 → 悬浮卡片浮现（歌曲 + 点歌人 + 寄语），
///   直接 通过 / 拒绝；已通过未播放的可一键「推入播放」（复用 AudioService）。
/// - **听众端**：显示自己最近提交的点歌状态（已提交/已通过/播放中…），
///   点击可跳转点歌队列页。
///
/// 自动收起：卡片短暂显示后淡出，仅留角标（未读 pending 数），
/// 点击角标重新展开。全程不阻断底部媒体栏交互。
/// ════════════════════════════════════════════════════════════════════════
class OrderFloatingCard extends ConsumerStatefulWidget {
  const OrderFloatingCard({super.key});

  @override
  ConsumerState<OrderFloatingCard> createState() => _OrderFloatingCardState();
}

class _OrderFloatingCardState extends ConsumerState<OrderFloatingCard> {
  /// 是否展开（false = 仅剩角标）。
  bool _expanded = true;

  /// 上次展示的队列快照（用于检测「新到」事件自动展开）。
  List<OrderItem>? _last;

  @override
  Widget build(BuildContext context) {
    final NetSessionState s = ref.watch(netSessionProvider);
    final List<OrderItem> queue = s.orderQueue;
    final bool isHost = s.role == NetRole.host;

    // 新到 pending（DJ 视角）：自动展开。
    final bool hasPending = queue.any((it) => it.status == OrderStatus.pending);
    final bool isNewPending = hasPending &&
        (_last == null || !_last!.any((it) => it.status == OrderStatus.pending));
    if (isNewPending && !_expanded) {
      // 在帧后置位，避免 build 中改 state。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _expanded = true);
      });
    }
    _last = queue;

    // 无任何可展示内容（DJ 无 pending/待播，听众无自己的点歌）→ 不占位。
    final bool show = isHost
        ? queue.any((it) =>
            it.status == OrderStatus.pending ||
            it.status == OrderStatus.approved)
        : queue.any((it) => it.status != OrderStatus.played &&
            it.status != OrderStatus.rejected);
    if (!show) return const SizedBox.shrink();

    // 未读 pending 数（角标）。
    final int pendingCount = queue
        .where((it) => it.status == OrderStatus.pending)
        .length;

    // 高优先级内容：DJ 取第一条 pending（无则取 approved）。
    final OrderItem focus = queue
            .where((it) => it.status == OrderStatus.pending)
            .firstOrNull ??
        queue.where((it) => it.status == OrderStatus.approved).firstOrNull!;

    // 由外层（AppShell Stack）定位到底部媒体栏之上；本组件只渲染卡片内容。
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (Widget child, Animation<double> anim) =>
                SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.4),
                end: Offset.zero,
              ).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _expanded
                ? _OrderCard(
                    key: ValueKey<String>(focus.id),
                    item: focus,
                    isHost: isHost,
                    pendingCount: pendingCount,
                    onDismiss: () => setState(() => _expanded = false),
                    onApprove: () => ref
                        .read(netSessionProvider.notifier)
                        .decideOrder(focus.id, true),
                    onReject: () => ref
                        .read(netSessionProvider.notifier)
                        .decideOrder(focus.id, false),
                    onPlay: isHost && focus.status == OrderStatus.approved
                        ? () => _playAsDj(focus)
                        : null,
                  )
                : _OrderBadge(
                    key: const ValueKey<String>('badge'),
                    pendingCount: pendingCount,
                    onTap: () => setState(() => _expanded = true),
                  ),
          ),
        ),
    );
  }

  Future<void> _playAsDj(OrderItem item) async {
    final AudioService svc = ref.read(audioServiceProvider);
    await svc.playMusic(item.track, fade: const Duration(milliseconds: 300));
    ref.read(netSessionProvider.notifier).decideOrder(item.id, true);
    // 标记 playing：复用 decideOrder(true) 后队列翻成 approved，
    // 继续由队列页「推入播放」流转（与现有流程一致）。
  }
}

/// 展开态：点歌悬浮卡片。
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    super.key,
    required this.item,
    required this.isHost,
    required this.pendingCount,
    required this.onDismiss,
    required this.onApprove,
    required this.onReject,
    this.onPlay,
  });

  final OrderItem item;
  final bool isHost;
  final int pendingCount;
  final VoidCallback onDismiss;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bool pending = item.status == OrderStatus.pending;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border.withValues(alpha: 0.6)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                pending ? Icons.notifications_active_outlined : Icons.queue_music,
                size: 18,
                color: pending ? c.accent : c.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isHost
                      ? (pending ? '新点歌请求' : '待播放点歌')
                      : '我的点歌',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (pendingCount > 1)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('+${pendingCount - 1}',
                      style: TextStyle(color: c.accent, fontSize: 11)),
                ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.expand_more, size: 18),
                color: c.textTertiary,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Icon(Icons.music_note, size: 16, color: c.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          Text(
            '${item.track.artist} · ${item.anonymous ? '匿名听众' : item.fromName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          if (item.message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              '“${item.message}”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (isHost && pending) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('拒绝'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.danger,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('通过'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
          if (onPlay != null) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('推入播放'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 收起态：右下角小角标（未读 pending 数）。
class _OrderBadge extends StatelessWidget {
  const _OrderBadge({
    super.key,
    required this.pendingCount,
    required this.onTap,
  });

  final int pendingCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(20),
        elevation: 4,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.queue_music, size: 16, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  pendingCount > 0 ? '$pendingCount' : '点歌',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
