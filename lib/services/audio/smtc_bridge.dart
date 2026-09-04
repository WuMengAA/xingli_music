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

import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String _kChannel = 'com.stelarith.xingli_music/smtc';

/// 系统媒体键 / 进度拖动事件回调：
/// [action] ∈ play/pause/next/previous/stop；[positionMs] 仅 onSeek 时有效。
typedef SmtcEventHandler = void Function(String action, double positionMs);

final bool _supported = !kIsWeb && Platform.isWindows;
MethodChannel? _channel;

/// 网络封面下载缓存：URL → 临时文件路径（避免切歌重复下载）。
/// 固定目录 + 上限淘汰，防止切歌长时间累积垃圾文件（曾每首都新建目录）。
final Map<String, String> _artCache = <String, String>{};
const int _kArtCacheMax = 8;

/// 把网络封面 URL 下载到临时文件（原生侧 SMTC 只接受本地文件路径）。
/// 返回本地路径；失败/超时返回空串。带内存缓存（超出上限淘汰最旧的）。
Future<String> _downloadArt(String url) async {
  final String? cached = _artCache[url];
  if (cached != null && File(cached).existsSync()) return cached;
  try {
    final http.Response resp =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return '';
    // 固定目录（launch 参数隔离），文件名按 URL 哈希，避免无界建目录。
    final Directory dir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}smtc_art');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final String path = '${dir.path}${Platform.pathSeparator}'
        '${url.hashCode.toRadixString(16)}.jpg';
    File(path).writeAsBytesSync(resp.bodyBytes, flush: true);
    // 淘汰最旧条目（超出上限）。
    if (_artCache.length >= _kArtCacheMax) {
      final String oldest = _artCache.keys.first;
      final String? oldPath = _artCache.remove(oldest);
      if (oldPath != null && oldPath != path) {
        try { File(oldPath).deleteSync(); } catch (_) { /* 忽略 */ }
      }
    }
    _artCache[url] = path;
    return path;
  } catch (_) {
    return '';
  }
}

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
/// [artPath] 为本地文件路径（原生 SMTC 只接受本地）；[artUrl] 为网络封面，
/// 当 [artPath] 为空时自动下载到临时文件后再同步（带缓存）。
void smtcUpdateMediaItem({
  required String title,
  String artist = '',
  String album = '',
  double durationMs = 0,
  String artPath = '',
  String artUrl = '',
}) {
  if (!_supported || _channel == null) return;
  _pushMediaItem(title, artist, album, durationMs, artPath);
  if (artPath.isEmpty && artUrl.isNotEmpty) {
    // 异步下载网络封面成功后补发一次（原生侧以最后一次为准）。
    _downloadArt(artUrl).then((String path) {
      if (path.isEmpty) return;
      _pushMediaItem(title, artist, album, durationMs, path);
    });
  }
}

void _pushMediaItem(String title, String artist, String album,
    double durationMs, String artPath) {
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
