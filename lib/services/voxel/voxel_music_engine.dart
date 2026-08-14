/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 · 游戏内背景音乐引擎（#322）
/// ════════════════════════════════════════════════════════════════════════
///
/// 规则（用户要求）：**游戏内没有音乐播放时**，自动轮换播放「我的世界」主题
/// 背景音乐；一旦用户在 App 里播放曲目（[nowPlayingProvider]/[isPlayingProvider]
/// 指示正在播放），立即让位暂停，避免两层音乐打架。
///
/// 与 [WorldAudioEngine]（空间环境音效）互补：本引擎只管「整曲轮换」的单轨 BGM。
///
/// 素材：用户把自己的合法音频按约定命名放入目录即可生效；缺失文件 = 安全 no-op。
///   - 桌面：`d:\Stellara\Music\minecraft_music\voxel_audio\music\track_01.m4a`
///           （或 `…\music\track_01.m4a`）
///   - 移动：`/storage/emulated/0/Music/minecraft_music/voxel_audio/music/…`
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart' as ap;

import '../../services/log_service.dart';
import 'voxel_audio_bundle.dart';

/// 游戏内背景音乐轮换引擎。
///
/// 用法：
/// ```dart
/// final engine = VoxelMusicEngine();
/// await engine.init();           // 扫描素材（无素材 = 空列表）
/// engine.setActive(true);        // 游戏内无音乐 → 播放
/// // 用户在 App 放歌：engine.setActive(false);  // 暂停让位
/// // 用户停止放歌：engine.setActive(true);     // 续播
/// await engine.dispose();
/// ```
class VoxelMusicEngine {
  VoxelMusicEngine();

  ap.AudioPlayer? _player;
  List<String> _tracks = const <String>[];
  int _idx = 0;
  bool _started = false;
  bool _initDone = false;

  /// 懒创建播放器：仅在真正要播放时才分配，避免「建了却没用」的浪费，
  /// 也让缺素材 / 未启用的场景（纯单测）无需触碰 audioplayers 全局绑定。
  ap.AudioPlayer _ensurePlayer() {
    _player ??= ap.AudioPlayer();
    return _player!;
  }

  /// 扫描素材目录（桌面 / 移动通用），构建可播放曲目表。
  ///
  /// 取 `track_01`…`track_30`（[kVoxelMusicSlotCount]）命名最稳妥，但也接受
  /// 目录下任意音频文件（按文件名排序，最多 30 首）。
  Future<void> init() async {
    if (_initDone) return;
    final String? base = await _baseDir();
    if (base != null) {
      for (final String sub in <String>['voxel_audio/music', 'music']) {
        final Directory dir = Directory('$base/$sub');
        if (!await dir.exists()) continue;
        final List<FileSystemEntity> files = await dir
            .list()
            .where((FileSystemEntity e) => e is File && _isAudio(e.path))
            .toList();
        files.sort(
          (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path),
        );
        _tracks = files
            .take(kVoxelMusicSlotCount)
            .map((FileSystemEntity e) => e.path)
            .toList();
        if (_tracks.isNotEmpty) break;
      }
    }
    _initDone = true;
    LogService.instance
        .i('voxel-music', '背景音乐扫描完成: ${_tracks.length} 首');
  }

  /// 激活 / 让位：
  /// - [active]=true → 游戏内无音乐，播放 BGM；
  /// - [active]=false → 用户在 App 放歌，暂停让位。
  Future<void> setActive(bool active) async {
    if (!active) {
      if (_started) {
        try {
          await _player?.pause();
        } catch (_) {}
      }
      return;
    }
    if (!_initDone) await init();
    if (_tracks.isEmpty) return; // 无素材 = 安全 no-op（不创建播放器）
    if (!_started) {
      _ensurePlayer().onPlayerComplete.listen((_) => _advance());
      _started = true;
    }
    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    if (_tracks.isEmpty) return;
    try {
      final ap.AudioPlayer p = _ensurePlayer();
      await p.setReleaseMode(ap.ReleaseMode.stop); // 逐曲播完进下一首
      await p.setSource(ap.DeviceFileSource(_tracks[_idx]));
      await p.resume();
    } catch (e) {
      LogService.instance.w('voxel-music', '播放失败: $e');
    }
  }

  void _advance() {
    if (_tracks.isEmpty) return;
    _idx = (_idx + 1) % _tracks.length;
    unawaited(_playCurrent());
  }

  Future<void> dispose() async {
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }

  static bool _isAudio(String p) {
    final String l = p.toLowerCase();
    return l.endsWith('.m4a') ||
        l.endsWith('.ogg') ||
        l.endsWith('.mp3') ||
        l.endsWith('.mp4') ||
        l.endsWith('.wav');
  }

  /// 「我的世界」资源根目录（桌面开发目录 / 移动端公共音乐目录）。
  static Future<String?> _baseDir() async {
    if (kIsWeb) return null;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      const String dev = r'd:\Stellara\Music\minecraft_music';
      if (await Directory('$dev/voxel_audio/music').exists() ||
          await Directory('$dev/music').exists()) {
        return dev;
      }
      return null;
    }
    for (final String prefix in <String>[
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
    ]) {
      if (await Directory('$prefix/minecraft_music/voxel_audio/music').exists() ||
          await Directory('$prefix/minecraft_music/music').exists()) {
        return '$prefix/minecraft_music';
      }
    }
    return null;
  }
}
