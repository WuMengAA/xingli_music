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
import '../../providers/radio/radio_history_provider.dart';
import '../../providers/sources/netease_provider.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../services/audio/audio_service.dart';

/// 点歌队列页。
class OrderQueuePage extends ConsumerStatefulWidget {
  const OrderQueuePage({super.key});

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
          _buildQueueHeader(c, s),
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
                  onPlay: () => _playAsDj(it.track, it.id),
                )),
        ],
      ),
      // 听众端 toast 通知：监听 notifyId 变化，弹出并立即清空，避免重复弹窗。
      bottomSheet: Consumer(
        builder: (BuildContext ctx, WidgetRef ref, Widget? child) {
          final String nid = ref.watch(netSessionProvider).notifyId;
          if (nid.isEmpty) return const SizedBox.shrink();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(nid),
                duration: const Duration(seconds: 2),
              ),
            );
            // 清空 notifyId，触发一次轻量重建（nid 变空）→ 不再弹。
            ref.read(netSessionProvider.notifier).resetNotify();
          });
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _playAsDj(Track track, String orderId) async {
    final NetSessionNotifier notifier =
        ref.read(netSessionProvider.notifier);
    final NetSessionState s = ref.read(netSessionProvider);
    // 先找当前 playing 项并写入已播历史。
    final OrderItem? cur = s.orderQueue
        .where((it) => it.status == OrderStatus.playing)
        .firstOrNull;
    if (cur != null) {
      final PlayedRecord rec = PlayedRecord(
        id: cur.id,
        track: cur.track,
        fromName: cur.anonymous ? '匿名听众' : cur.fromName,
        source: cur.fromId == s.localId ? 'dj' : 'listener',
        at: DateTime.now(),
      );
      ref.read(radioHistoryProvider.notifier).add(rec);
    }
    notifier.markPlayed();
    notifier.playOrder(orderId);
    final AudioService svc = ref.read(audioServiceProvider);
    await svc.playMusic(track, fade: const Duration(milliseconds: 300));
  }

  /// 队列统计头：VoiceHub 风格——按状态分类计数（总 / 待审批 / 待播 / 播放中 / 已播 / 已拒）。
  Widget _buildQueueHeader(AppThemeColors c, NetSessionState s) {
    final int total = s.orderQueue.length;
    final int pending =
        s.orderQueue.where((it) => it.status == OrderStatus.pending).length;
    final int approved =
        s.orderQueue.where((it) => it.status == OrderStatus.approved).length;
    final int playing =
        s.orderQueue.where((it) => it.status == OrderStatus.playing).length;
    final int played =
        s.orderQueue.where((it) => it.status == OrderStatus.played).length;
    final int rejected =
        s.orderQueue.where((it) => it.status == OrderStatus.rejected).length;
    return Row(
      children: <Widget>[
        Text('队列（$total）',
            style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (pending > 0)
          _queueChip('待审批', pending, c.warning),
        if (approved > 0)
          _queueChip('待播', approved, c.accent),
        if (playing > 0)
          _queueChip('播放中', playing, Colors.red),
        if (played > 0)
          _queueChip('已播', played, c.textSecondary),
        if (rejected > 0)
          _queueChip('已拒', rejected, c.danger),
      ],
    );
  }

  Widget _queueChip(String label, int count, Color color) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text.rich(
            TextSpan(
              text: label,
              style: TextStyle(color: color, fontSize: 11),
              children: <InlineSpan>[
                TextSpan(
                  text: ' $count',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      );

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

/// 选曲弹层：本地曲库 / 在线（网易云 + 哔哩哔哩）双标签搜索。
///
/// - 本地：复用 [musicLibraryProvider]（含「听过的歌自动入曲库」）。
/// - 在线：未登录时提示先登录；已登录则并行搜两源，给听众真正的点歌渠道。
/// 顶部「取消」可明确退出选曲（同时底部抽屉仍可下拉关闭）。
class _TrackPicker extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TrackPicker> createState() => _TrackPickerState();
}

class _TrackPickerState extends ConsumerState<_TrackPicker> {
  final TextEditingController _q = TextEditingController();
  bool _online = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      height: 520,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: false, label: Text('本地')),
                  ButtonSegment<bool>(value: true, label: Text('在线')),
                ],
                selected: <bool>{_online},
                onSelectionChanged: (Set<bool> s) =>
                    setState(() => _online = s.first),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _q,
            autofocus: true,
            decoration: InputDecoration(
              hintText: _online ? '搜索网易云 / 哔哩哔哩' : '搜索曲名 / 歌手',
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
          Expanded(child: _online ? _buildOnline(c) : _buildLocal(c)),
        ],
      ),
    );
  }

  Widget _buildLocal(AppThemeColors c) {
    final AsyncValue<List<Track>> lib = ref.watch(musicLibraryProvider);
    return lib.when(
      data: (List<Track> tracks) {
        final String k = _q.text.trim().toLowerCase();
        final List<Track> filtered = k.isEmpty
            ? tracks
            : tracks
                .where((Track t) =>
                    (t.title.toLowerCase().contains(k)) ||
                    (t.artist.toLowerCase().contains(k)))
                .toList();
        if (filtered.isEmpty) {
          return Center(
              child: Text('无匹配', style: TextStyle(color: c.textSecondary)));
        }
        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (_, int i) {
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
      error: (Object e, _) => Center(
          child: Text('读取曲库失败', style: TextStyle(color: c.danger))),
    );
  }

  Widget _buildOnline(AppThemeColors c) {
    final String kw = _q.text.trim();
    if (kw.isEmpty) {
      return Center(
          child: Text('输入关键词搜索在线曲库',
              style: TextStyle(color: c.textSecondary)));
    }
    final bool ne = ref.watch(neteaseAuthProvider).isLoggedIn;
    final bool bi = ref.watch(bilibiliAuthProvider).isLoggedIn;
    if (!ne && !bi) {
      return Center(
          child: Text('点歌需先登录网易云 / 哔哩哔哩',
              style: TextStyle(color: c.textSecondary)));
    }
    final AsyncValue<List<Track>> neRes = ne
        ? ref.watch(neteaseSearchProvider(kw))
        : const AsyncValue<List<Track>>.data(<Track>[]);
    final AsyncValue<List<Track>> biRes = bi
        ? ref.watch(bilibiliSearchProvider(kw))
        : const AsyncValue<List<Track>>.data(<Track>[]);
    final List<Track> neHits = neRes.valueOrNull ?? const <Track>[];
    final List<Track> biHits = biRes.valueOrNull ?? const <Track>[];
    if (neHits.isEmpty && biHits.isEmpty) {
      final bool loading = neRes.isLoading || biRes.isLoading;
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
          child: Text('在线无匹配', style: TextStyle(color: c.textSecondary)));
    }
    final List<Track> all = <Track>[...neHits, ...biHits];
    return ListView.builder(
      itemCount: all.length,
      itemBuilder: (_, int i) {
        final Track t = all[i];
        final String src = t.sourceId == 'netease'
            ? '网易云'
            : t.sourceId == 'bilibili'
                ? 'B站'
                : '本地';
        return ListTile(
          title: Text(t.title, style: TextStyle(color: c.textPrimary)),
          subtitle: Text('$src · ${t.artist}',
              style: TextStyle(color: c.textSecondary, fontSize: 12)),
          onTap: () => Navigator.of(context).pop(t),
        );
      },
    );
  }
}
