/// ════════════════════════════════════════════════════════════════════════
/// 电台房主页（社交模块 · 电台核心）：成员列表 + DJ 标识 + 房间码分享 +
/// 点歌队列入口（按 [StationMode] 显隐）。
///
/// - host 端：顶部展示房间号（房主分享）、DJ 标识、成员列表（含 DJ 角标）。
/// - client 端：展示 DJ 信息、成员列表、跟随一起听（已实现的 listenState 链路）。
/// - 点歌队列：仅在 mode.acceptOrder 时显示入口。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/net/session_provider.dart';
import 'station_lobby_page.dart';
import 'order_queue_page.dart';

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
    // 退出清理：无论点「离开」按钮还是系统返回键/手势 pop，都先 leave()
    // 清空 netSessionProvider._node，否则残留连接导致后续「创建/加入」失败。
    Future<void> onExit() async {
      await ref.read(netSessionProvider.notifier).leave();
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) return;
        onExit();
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
                    builder: (_) => OrderQueuePage(mode: mode),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '离开',
              onPressed: () async {
                await onExit();
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
                  const SizedBox(height: 16),
                  _buildMembers(c, s),
                  if (mode.syncListen) ...<Widget>[
                    const SizedBox(height: 16),
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

  Widget _buildRoomCode(BuildContext context, AppThemeColors c, NetSessionState s) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('房间号（分享给好友加入）',
                style: TextStyle(color: c.textSecondary, fontSize: 12)),
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
                  icon: const Icon(Icons.copy),
                  label: const Text('复制'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildDjCard(AppThemeColors c, NetSessionState s) {
    final PeerInfo? dj = s.peers.where((p) => p.isHost).firstOrNull ??
        (s.role == NetRole.host
            ? PeerInfo(id: s.localId ?? '', isHost: true, name: s.localName)
            : null);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: c.accent,
            child: const Icon(Icons.radio, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('DJ · 音源',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text(dj?.name ?? '连接中…',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (s.role == NetRole.host)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('你', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.accent.withValues(alpha: 0.35)),
      ),
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
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(10),
        ),
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('DJ',
                    style: TextStyle(color: c.accent, fontSize: 11)),
              ),
          ],
        ),
      );
}
