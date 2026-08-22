/// ════════════════════════════════════════════════════════════════════════
/// 点歌队列页（社交模块 · 电台点歌队列子能力）。
///
/// - 听众端：搜索选曲 + 寄语 + 匿名 → 提交点歌（[NetSessionNotifier.submitOrder]）。
/// - DJ 端：对 pending 项审批（通过/拒绝 → [decideOrder]），状态实时回显。
/// - 状态机见 [OrderStatus]：pending/approved/playing/played/rejected。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/net/session_provider.dart';
import '../../services/audio/audio_service.dart';
import 'station_lobby_page.dart';

/// 点歌队列页。
class OrderQueuePage extends ConsumerStatefulWidget {
  const OrderQueuePage({super.key, required this.mode});
  final StationMode mode;

  @override
  ConsumerState<OrderQueuePage> createState() => _OrderQueuePageState();
}

class _OrderQueuePageState extends ConsumerState<OrderQueuePage> {
  Track? _picked;
  final TextEditingController _msgCtrl = TextEditingController();
  bool _anon = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTrack() async {
    final Track? t = await showModalBottomSheet<Track?>(
      context: context,
      backgroundColor: context.appColors.bgCard,
      builder: (_) => _TrackPicker(),
    );
    if (t != null && mounted) setState(() => _picked = t);
  }

  void _submit() {
    if (_picked == null) return;
    ref.read(netSessionProvider.notifier).submitOrder(
          _picked!,
          message: _msgCtrl.text.trim(),
          anonymous: _anon,
        );
    setState(() {
      _picked = null;
      _msgCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已提交点歌，等待 DJ 审批')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final NetSessionState s = ref.watch(netSessionProvider);
    final bool isHost = s.role == NetRole.host;
    return Scaffold(
      backgroundColor: c.bgPage,
      appBar: AppBar(
        title: const Text('点歌队列'),
        backgroundColor: c.bgPage,
        foregroundColor: c.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!isHost) _buildSubmitCard(c),
          const SizedBox(height: 12),
          Text('队列（${s.orderQueue.length}）',
              style: TextStyle(color: c.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          if (s.orderQueue.isEmpty)
            _EmptyHint(c: c)
          else
            ...s.orderQueue.map((it) => _OrderTile(
                  c: c,
                  item: it,
                  isHost: isHost,
                  onApprove: () => ref
                      .read(netSessionProvider.notifier)
                      .decideOrder(it.id, true),
                  onReject: () => ref
                      .read(netSessionProvider.notifier)
                      .decideOrder(it.id, false),
                  onPlay: () => _playAsDj(it.track),
                )),
        ],
      ),
    );
  }

  Future<void> _playAsDj(Track track) async {
    // DJ 端：把点歌推入当前播放（复用音频服务），并标记 playing。
    final AudioService svc = ref.read(audioServiceProvider);
    await svc.playMusic(track, fade: const Duration(milliseconds: 300));
    if (widget.mode == StationMode.orderOnly) {
      // 纯点歌台：推入播放即视为 played（不同步），保持队列清爽。
      ref.read(netSessionProvider.notifier).decideOrder(
            // 找到该 track 对应 pending/approved 项
            ref.read(netSessionProvider).orderQueue
                .where((it) => it.track.uri == track.uri && it.status != OrderStatus.played && it.status != OrderStatus.rejected)
                .firstOrNull
                ?.id ?? '',
            true,
          );
    }
  }

  Widget _buildSubmitCard(AppThemeColors c) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('点一首歌', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _pickTrack,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.bgPage,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.music_note, color: c.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _picked?.title ?? '点击选择歌曲',
                        style: TextStyle(
                            color: _picked == null ? c.textSecondary : c.textPrimary),
                      ),
                    ),
                    if (_picked != null)
                      Text(_picked!.artist,
                          style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _msgCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: '点歌寄语（可选）',
                hintStyle: TextStyle(color: c.textSecondary),
                filled: true,
                fillColor: c.bgPage,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              style: TextStyle(color: c.textPrimary),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Switch(
                  value: _anon,
                  onChanged: (v) => setState(() => _anon = v),
                  activeThumbColor: WidgetStateColor.resolveWith(
                    (_) => c.accent,
                  ),
                ),
                Text('匿名点歌', style: TextStyle(color: c.textSecondary)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _picked == null ? null : _submit,
                  icon: const Icon(Icons.send),
                  label: const Text('提交'),
                ),
              ],
            ),
          ],
        ),
      );
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.c,
    required this.item,
    required this.isHost,
    required this.onApprove,
    required this.onReject,
    required this.onPlay,
  });
  final AppThemeColors c;
  final OrderItem item;
  final bool isHost;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(item.track.title,
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
                ),
                _StatusBadge(c: c, status: item.status),
              ],
            ),
            const SizedBox(height: 2),
            Text(item.track.artist,
                style: TextStyle(color: c.textSecondary, fontSize: 12)),
            if (item.message.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text('“${item.message}”',
                  style: TextStyle(color: c.textTertiary, fontSize: 12, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 4),
            Text(
              item.anonymous ? '匿名听众' : item.fromName,
              style: TextStyle(color: c.textSecondary, fontSize: 11),
            ),
            if (isHost && item.status == OrderStatus.pending) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('拒绝'),
                    style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('通过'),
                  ),
                ],
              ),
            ],
            if (isHost && item.status == OrderStatus.approved) ...<Widget>[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('推入播放'),
                ),
              ),
            ],
          ],
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.c, required this.status});
  final AppThemeColors c;
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      OrderStatus.pending => ('待审批', c.warning),
      OrderStatus.approved => ('已通过', c.success),
      OrderStatus.playing => ('播放中', c.accent),
      OrderStatus.played => ('已播放', c.textSecondary),
      OrderStatus.rejected => ('已拒绝', c.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.c});
  final AppThemeColors c;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text('暂无点歌，听众可在此点歌',
            style: TextStyle(color: c.textSecondary)),
      );
}

/// 简易选曲弹层：从本地曲库搜索过滤。
class _TrackPicker extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final TextEditingController q = TextEditingController();
    final AsyncValue<List<Track>> lib = ref.watch(musicLibraryProvider);
    return StatefulBuilder(
      builder: (context, setState) => Container(
        padding: const EdgeInsets.all(16),
        height: 480,
        child: Column(
          children: <Widget>[
            TextField(
              controller: q,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索曲名 / 歌手',
                hintStyle: TextStyle(color: c.textSecondary),
                prefixIcon: Icon(Icons.search, color: c.textSecondary),
                filled: true,
                fillColor: c.bgPage,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              style: TextStyle(color: c.textPrimary),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: lib.when(
                data: (tracks) {
                  final String k = q.text.trim().toLowerCase();
                  final List<Track> filtered = k.isEmpty
                      ? tracks
                      : tracks
                          .where((t) =>
                              (t.title.toLowerCase().contains(k)) ||
                              (t.artist.toLowerCase().contains(k)))
                          .toList();
                  if (filtered.isEmpty) {
                    return Center(
                        child: Text('无匹配', style: TextStyle(color: c.textSecondary)));
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final Track t = filtered[i];
                      return ListTile(
                        title: Text(t.title, style: TextStyle(color: c.textPrimary)),
                        subtitle: Text(t.artist,
                            style: TextStyle(color: c.textSecondary, fontSize: 12)),
                        onTap: () => Navigator.of(context).pop(t),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                    child: Text('读取曲库失败', style: TextStyle(color: c.danger))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
