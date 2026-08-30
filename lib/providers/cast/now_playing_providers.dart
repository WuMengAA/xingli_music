import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../models/track.dart';
import '../../services/audio/playback_controller.dart';
import '../../services/cast/now_playing_server.dart';
import '../../services/log_service.dart';
import '../audio/audio_providers.dart';
import '../net/session_provider.dart';

/// ============================================================================
/// NowPlayingServer 的 Riverpod 组装层（ClassIsland 联动 · docs/方案_ClassIsland联动.md）。
///
/// - [nowPlayingLocalServerProvider]：构造服务，注入「快照读取器」（播放真值 +
///   电台会话）与「远程控制」（复用 [playbackControllerProvider]）。
/// - [nowPlayingLocalBridgeProvider]：AppShell 根部 watch 一次；**Windows 端**常驻
///   启动（Android 上不启动，无暴露面）。
/// ============================================================================

final nowPlayingLocalServerProvider = Provider<NowPlayingServer>((ref) {
  return NowPlayingServer(
    version: AppVersion.display,
    reader: () => _buildSnapshot(ref),
    control: (String action) => _handleControl(ref, action),
  );
});

/// AppShell 根部挂载：Windows 端常驻启动（幂等）。
final nowPlayingLocalBridgeProvider = Provider<void>((ref) {
  if (kIsWeb || !Platform.isWindows) return;
  final NowPlayingServer server = ref.read(nowPlayingLocalServerProvider);
  unawaited(server.start().then((_) {}).catchError((Object e) {
    LogService.instance.w('np', 'NowPlaying 服务启动失败: $e');
  }));
});

NowPlayingSnapshot _buildSnapshot(Ref ref) {
  final Track? track = ref.read(nowPlayingProvider);
  final bool playing = ref.read(isPlayingProvider).valueOrNull ?? false;
  final Duration? pos = ref.read(musicPositionProvider).valueOrNull;
  final Duration? dur = ref.read(musicDurationProvider).valueOrNull;

  final NetSessionState net = ref.read(netSessionProvider);
  NowPlayingRadio? radio;
  if (net.role != NetRole.offline) {
    final String? djName;
    if (net.dj) {
      djName = net.localName;
    } else {
      djName = net.peers.where((PeerInfo p) => p.isHost).map((PeerInfo p) => p.name).firstOrNull;
    }
    final Map<String, dynamic>? meta = net.roomMeta;
    radio = NowPlayingRadio(
      role: net.role.name,
      isDj: net.dj,
      djName: djName,
      roomName: meta?['name'] as String?,
      roomCode: net.roomCode ?? (meta?['code'] as String?),
      mode: meta?['mode'] as String?,
      memberCount: meta?['members'] as int?,
    );
  }

  return NowPlayingSnapshot(
    track: track == null
        ? null
        : NowPlayingTrack(
            title: track.title,
            artist: track.artist,
            album: track.album,
            coverUrl: track.coverUrl,
            isLiveStream: track.isLiveStream,
            sourceId: track.sourceId.isEmpty ? null : track.sourceId,
          ),
    isPlaying: playing,
    positionMs: pos?.inMilliseconds,
    durationMs: dur?.inMilliseconds,
    radio: radio,
  );
}

Future<bool> _handleControl(Ref ref, String action) async {
  final PlaybackController ctrl = ref.read(playbackControllerProvider);
  try {
    switch (action) {
      case 'play':
        await ctrl.play();
      case 'pause':
        await ctrl.pause();
      case 'toggle':
        await ctrl.toggle();
      case 'next':
        await ctrl.skip(1);
      case 'prev':
        await ctrl.skip(-1);
    }
    return true;
  } catch (_) {
    return false;
  }
}