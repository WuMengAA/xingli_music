/// ════════════════════════════════════════════════════════════════════════
/// SMTC 桥（Windows System Media Transport Controls，Dart 侧）
///
/// 把星璃播放器状态镜像到 Windows 系统媒体控件（任务栏媒体卡片 + 全局
/// 媒体键：播放/暂停/上一首/下一首/停止/拖动进度）。原生侧见
/// `windows/runner/smtc_bridge.cpp`。
///
/// 仅在 Windows 生效；其他平台走 audio_service 的系统媒体能力（Android/iOS
/// 锁屏、通知栏），本模块直接 no-op。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

const String _kChannel = 'com.stelarith.xingli_music/smtc';

/// 系统媒体键 / 进度拖动事件回调：
/// [action] ∈ play/pause/next/previous/stop；[positionMs] 仅 onSeek 时有效。
typedef SmtcEventHandler = void Function(String action, double positionMs);

final bool _supported = !kIsWeb && Platform.isWindows;
MethodChannel? _channel;

/// 初始化桥并订阅系统媒体键（应在播放控制器就绪后调用一次；
/// 非 Windows 平台为 no-op）。
void smtcInit(SmtcEventHandler onEvent) {
  if (!_supported) return;
  _channel ??= const MethodChannel(_kChannel);
  _channel!.setMethodCallHandler((MethodCall call) async {
    switch (call.method) {
      case 'onButton':
        final String action = call.arguments?['action'] as String? ?? '';
        onEvent(action, 0);
        break;
      case 'onSeek':
        final double ms =
            (call.arguments?['positionMs'] as num?)?.toDouble() ?? 0;
        onEvent('seek', ms);
        break;
    }
  });
}

/// 更新媒体项元数据（title/artist/album/durationMs/artPath）。
void smtcUpdateMediaItem({
  required String title,
  String artist = '',
  String album = '',
  double durationMs = 0,
  String artPath = '',
}) {
  if (!_supported || _channel == null) return;
  _channel!.invokeMethod<void>('updateMediaItem', <String, Object?>{
    'title': title,
    'artist': artist,
    'album': album,
    'duration': durationMs,
    'artPath': artPath,
  });
}

/// 更新播放状态（playing/positionMs/durationMs）。
void smtcUpdatePlayback({
  required bool playing,
  double positionMs = 0,
  double durationMs = 0,
}) {
  if (!_supported || _channel == null) return;
  _channel!.invokeMethod<void>('updatePlayback', <String, Object?>{
    'playing': playing,
    'positionMs': positionMs,
    'durationMs': durationMs,
  });
}

/// 清空媒体会话（停止时调用）。
void smtcClear() {
  if (!_supported || _channel == null) return;
  _channel!.invokeMethod<void>('clear');
}
