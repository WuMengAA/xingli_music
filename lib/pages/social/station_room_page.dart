/// ════════════════════════════════════════════════════════════════════════
/// 电台房主页（社交模块 · 电台核心）：成员列表 + DJ 标识 + 房间码分享 +
/// 点歌队列入口（按 [StationMode] 显隐）。
///
/// VoiceHub 风格（R33）：
/// - 玻璃卡片（LiquidGlass frosted）+ DJ 脉冲徽章 + 正在播放 LIVE 指示器
/// - 顶部 LIVE mini bar：当前播放曲目 + 进度 + 脉冲 LIVE 标
/// - 成员列表玻璃行 + DJ 光晕徽章
///
/// - host 端：顶部展示房间号（房主分享）、DJ 标识、成员列表（含 DJ 角标）。
/// - client 端：展示 DJ 信息、成员列表、跟随一起听（已实现的 listenState 链路）。
/// - 点歌队列：仅在 mode.acceptOrder 时显示入口。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/net/session_provider.dart';
import '../../widgets/liquid_glass.dart';
import 'order_queue_page.dart';
import 'station_lobby_page.dart';

/// 电台房主页。
class StationRoomPage extends ConsumerWidget {
  const StationRoomPage({
    super.key,
    required this.mode,
    required this.isHost,
  });

  final StationMode mode;
  final bool isHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final NetSessionState s = ref.watch(netSessionProvider);
    final bool isConnected = s.status == ConnStatus.connected;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        // cl15：返回主页不退出房间。连接由 netSessionProvider 单例维护，
        // 下次创建/加入新房时 host()/join() 会自动清理残留节点。
        // 仅「离开」按钮显式调用 leave() 断线退房。
      },
      child: Scaffold(
        backgroundColor: c.bgPage,
        appBar: AppBar(
          title: Text(mode.label),
          backgroundColor: c.bgPage,
          foregroundColor: c.textPrimary,
          elevation: 0,
          actions: <Widget>[
            if (mode.acceptOrder)
              IconButton(
                icon: const Icon(Icons.playlist_add_check),
                tooltip: '点歌队列',
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const OrderQueuePage(),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '离开',
              onPressed: () async {
                await ref.read(netSessionProvider.notifier).leave();
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        body: !isConnected
            ? _buildStatus(c, s)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  if (isHost) _buildRoomCode(context, c, s),
                  _buildDjCard(c, s),
                  const SizedBox(height: 14),
                  _buildNowPlayingBar(context, ref, c),
                  const SizedBox(height: 14),
                  if (mode.acceptOrder) ...[
                    _buildOrderQueueCard(context, c, s),
                    const SizedBox(height: 14),
                  ],
                  _buildMembers(c, s),
                  if (mode.syncListen) ...<Widget>[
                    const SizedBox(height: 14),
                    _buildListenHint(ref, c, s),
                  ],
                ],
              ),
      ),
    );
  }

  /// 复制房间号到剪贴板：先确认，再复制，提示「已复制」。
  Future<void> _copyRoomCode(BuildContext context, String roomCode) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dc) => AlertDialog(
        title: const Text('复制房间号'),
        content: Text('将房间号 $roomCode 复制到剪贴板？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dc).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dc).pop(true),
            child: const Text('复制'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Clipboard.setData(ClipboardData(text: roomCode));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildStatus(AppThemeColors c, NetSessionState s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 16),
              Text('连接中…',
                  style: TextStyle(color: c.textPrimary, fontSize: 16)),
              if (s.error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(s.error!, style: TextStyle(color: c.danger)),
              ],
            ],
          ),
        ),
      );

  /// 房间号卡片（房主）—— 玻璃质感。
  Widget _buildRoomCode(BuildContext context, AppThemeColors c, NetSessionState s) =>
      LiquidGlass(
    radius: 16,
    style: GlassStyle.frosted,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.cast, color: c.accent, size: 16),
            const SizedBox(width: 6),
            Text('房间号（分享给好友加入）',
                style: TextStyle(color: c.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                s.roomCode ?? '——',
                style: TextStyle(
                  color: c.accent,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: s.roomCode == null
                  ? null
                  : () => _copyRoomCode(context, s.roomCode!),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('复制'),
            ),
          ],
        ),
      ],
    ),
  );

  /// DJ 卡片（VoiceHub 风格）—— 玻璃质感 + 脉冲徽章 + 在线状态。
  Widget _buildDjCard(AppThemeColors c, NetSessionState s) {
    final PeerInfo? dj = s.peers.where((p) => p.isHost).firstOrNull ??
        (s.role == NetRole.host
            ? PeerInfo(id: s.localId ?? '', isHost: true, name: s.localName)
            : null);
    return LiquidGlass(
      radius: 16,
      style: GlassStyle.frosted,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          // DJ 头像：图标 + 脉冲光环（DJ 在线指示）。
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                const _LivePulse(color: Colors.red, size: 52),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: c.accent,
                  child: const Icon(
                    Icons.radio,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text('DJ · 音源',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text('LIVE',
                          style: TextStyle(
                              color: c.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(dj?.name ?? '连接中…',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (s.role == NetRole.host)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: c.accent.withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Text('你',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  /// 正在播放 LIVE mini bar（VoiceHub Player 风格）。
  /// 顶部玻璃条：脉冲 LIVE 标 + 当前曲目 + 进度 / 总长。
  Widget _buildNowPlayingBar(BuildContext context, WidgetRef ref, AppThemeColors c) {
    final Track? now = ref.read(nowPlayingProvider);
    final Duration? pos = ref.read(musicPositionProvider).valueOrNull;
    final Duration total = now?.duration ?? Duration.zero;
    final bool isPlaying = ref
            .read(playbackStateProvider)
            .valueOrNull
            ?.name
            .contains('playing') ??
        false;
    final String fmt = _fmt(pos);
    final String totalFmt = _fmt(total);
    final bool showProgress = now != null && total.inMilliseconds > 0 && pos != null;
    final double ratio =
        total.inMilliseconds > 0 && pos != null ? pos.inMilliseconds / total.inMilliseconds : 0;

    return LiquidGlass(
      radius: 14,
      style: GlassStyle.frosted,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (isPlaying)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _LivePulse(color: c.accent, size: 22),
                ),
              if (isPlaying)
                Text('正在播出',
                    style: TextStyle(
                        color: c.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              const Spacer(),
              Icon(Icons.volume_up, color: c.textTertiary, size: 16),
            ],
          ),
          const SizedBox(height: 6),
          if (now == null)
            Text('（等待 DJ 开始播放）',
                style: TextStyle(color: c.textSecondary, fontSize: 13))
          else
            Text('${now.title}  —  ${now.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          if (showProgress) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 3,
                      backgroundColor: c.border.withValues(alpha: 0.4),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(c.accent),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$fmt / $totalFmt',
                    style: TextStyle(
                        color: c.textSecondary, fontSize: 11)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 点歌队列卡片 —— 玻璃质感。
  Widget _buildOrderQueueCard(
      BuildContext context, AppThemeColors c, NetSessionState s) {
    final List<OrderItem> pending = s.orderQueue
        .where((it) => it.status == OrderStatus.pending)
        .toList();
    final List<OrderItem> approved = s.orderQueue
        .where((it) => it.status == OrderStatus.approved)
        .toList();
    // VoiceHub 风格：点歌队列在房间内可见——待审批 + 待播放两张小卡。
    return LiquidGlass(
      radius: 16,
      style: GlassStyle.frosted,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.queue_music, color: c.accent, size: 18),
              const SizedBox(width: 8),
              Text('点歌队列',
                  style: TextStyle(
                      color: c.textPrimary, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (pending.isNotEmpty || approved.isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const OrderQueuePage(),
                    ),
                  ),
                  child: const Text('查看全部'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (s.orderQueue.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('暂无点歌，听众可点歌',
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
            )
          else ...<Widget>[
            if (pending.isNotEmpty) ...<Widget>[
              _queueRow(c: c, icon: Icons.pending_actions, label: '待审批', items: pending),
              const SizedBox(height: 8),
            ],
            if (approved.isNotEmpty) ...<Widget>[
              _queueRow(c: c, icon: Icons.playlist_play, label: '待播放', items: approved),
            ],
          ],
        ],
      ),
    );
  }

  /// 单行队列分组：最多展示 3 条，其余「+N」。
  Widget _queueRow({
    required AppThemeColors c,
    required IconData icon,
    required String label,
    required List<OrderItem> items,
  }) {
    final List<OrderItem> shown = items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 14, color: c.textSecondary),
            const SizedBox(width: 4),
            Text('$label（${items.length}）',
                style: TextStyle(color: c.textSecondary, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        ...shown.map((OrderItem it) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: <Widget>[
                  Icon(Icons.music_note, size: 14, color: c.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      it.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textPrimary, fontSize: 12),
                    ),
                  ),
                  Text(it.anonymous ? '匿名' : it.fromName,
                      style:
                          TextStyle(color: c.textTertiary, fontSize: 11)),
                ],
              ),
            )),
        if (items.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('+${items.length - shown.length} 首',
                style: TextStyle(color: c.textTertiary, fontSize: 11)),
          ),
      ],
    );
  }

  Widget _buildMembers(AppThemeColors c, NetSessionState s) {
    final List<PeerInfo> members = <PeerInfo>[
      if (s.role == NetRole.host)
        PeerInfo(id: s.localId ?? '', isHost: true, name: s.localName),
      ...s.peers,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('成员（${members.length}）',
            style: TextStyle(color: c.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        ...members.map((p) => _MemberTile(c: c, p: p, isSelf: p.id == s.localId)),
      ],
    );
  }

  Widget _buildListenHint(WidgetRef ref, AppThemeColors c, NetSessionState s) {
    final Track? now = ref.watch(nowPlayingProvider);
    final Duration? pos =
        ref.watch(musicPositionProvider).valueOrNull;
    final String fmt = _fmt(pos);
    final bool isClient = s.role == NetRole.client;

    return LiquidGlass(
      radius: 14,
      style: GlassStyle.frosted,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Icon(Icons.sync, color: c.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  isClient ? '与房主同步中' : '你正在播出，同步给全员',
                  style: TextStyle(color: c.accent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  now == null
                      ? '（等待 DJ 开始播放）'
                      : '${now.title} — ${now.artist}   ·  $fmt',
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 毫秒 → `m:ss` 简易格式化（用于跟随态进度展示）。
  String _fmt(Duration? d) {
    if (d == null) return '0:00';
    final int total = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

/// 脉冲 LIVE 点（VoiceHub 风格）—— 呼吸光环 + 中心实心点。
/// 可嵌入任意位置（DJ 头像光环、LIVE 标等）。
class _LivePulse extends StatefulWidget {
  const _LivePulse({
    super.key,
    required this.color,
    this.size = 20,
  });
  final Color color;
  final double size;

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeInOut);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double r = widget.size / 2;
    return AnimatedBuilder(
      animation: _a,
      builder: (BuildContext ctx, Widget? _) => SizedBox(
        width: r * 2,
        height: r * 2,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // 呼吸光环。
            Container(
              width: r * 2 + 8 * _a.value,
              height: r * 2 + 8 * _a.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(
                    alpha: (0.45 - 0.35 * _a.value) * 0.7),
              ),
            ),
            // 中心实心点。
            Container(
              width: r * 1.4,
              height: r * 1.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.8),
                    blurRadius: 6 + 4 * _a.value,
                    spreadRadius: -1 + 0.5 * _a.value,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.c,
    required this.p,
    required this.isSelf,
  });
  final AppThemeColors c;
  final PeerInfo p;
  final bool isSelf;

  @override
  Widget build(BuildContext context) => LiquidGlass(
        radius: 10,
        style: GlassStyle.frosted,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: <Widget>[
              Icon(Icons.person, color: c.textSecondary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.name + (isSelf ? '（你）' : ''),
                    style: TextStyle(color: c.textPrimary)),
              ),
              if (p.isHost)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: c.accent.withValues(alpha: 0.55),
                        blurRadius: 8,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                  child: Text('DJ',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      );
}