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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme_colors.dart';
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
    return Scaffold(
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
                if (isHost) _buildRoomCode(c, s),
                _buildDjCard(c, s),
                const SizedBox(height: 16),
                _buildMembers(c, s),
                if (mode.syncListen) ...<Widget>[
                  const SizedBox(height: 16),
                  _buildListenHint(c, s),
                ],
              ],
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

  Widget _buildRoomCode(AppThemeColors c, NetSessionState s) => Container(
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
                      : () => SharePlus.instance.share(
                          ShareParams(
                            text: '来我的星璃电台房听听～ 房间号：${s.roomCode}',
                          ),
                        ),
                  icon: const Icon(Icons.share),
                  label: const Text('分享'),
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

  Widget _buildListenHint(AppThemeColors c, NetSessionState s) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.sync, color: c.textSecondary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.role == NetRole.client
                    ? '已开启一起听：播放进度跟随 DJ。'
                    : '一起听已开启：你的播放会同步给所有听众。',
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      );
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
