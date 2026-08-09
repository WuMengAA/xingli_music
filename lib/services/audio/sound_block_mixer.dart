import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/voxel.dart';
import '../log_service.dart';
import 'audio_service.dart';

/// 2.5D 音效块混音器（v2 M5-1 · P0-M5-1）。
///
/// 依据架构 §3.1：按方块数量 / 位置混合 ——
/// - 每类 count → 音量（`count * baseVolume`，上限 1.0）；
/// - x 位置 → 左右声道权重（可选，本版简化为音量微调）。
/// 经既有 [AudioService.playSfx] 播放（一次性 / 循环由调用方控制）。
class SoundBlockMixer {
  SoundBlockMixer(this._audio);

  final AudioService _audio;

  bool _previewing = false;

  /// 是否正在试听。
  bool get previewing => _previewing;

  /// 试听：按当前画布方块统计每类数量，逐类播放对应音效（循环）。
  ///
  /// [controller] 传入画布控制器以读取 blocks。
  Future<void> preview(
    Map<String, String> blocks, {
    bool loop = false,
  }) async {
    await stop();

    final Map<String, int> counts = <String, int>{};
    for (final String typeId in blocks.values) {
      counts[typeId] = (counts[typeId] ?? 0) + 1;
    }
    if (counts.isEmpty) return;

    _previewing = true;
    // 逐类混合：数量越多音量越高（cap 1.0）
    for (final MapEntry<String, int> e in counts.entries) {
      final VoxelBlockType type = voxelBlockTypeById(e.key);
      final String? path = await _resolveSfxPath(type.sfxKey);
      if (path == null) continue;
      final double volume = (type.baseVolume * e.value).clamp(0.0, 1.0);
      await _audio.playSfx(path, volume: volume);
      if (loop) {
        unawaited(_scheduleLoop(path, volume));
      }
    }
    LogService.instance.i(
        'voxel', '试听: ${counts.length} 类音效块, 总数 ${blocks.length}');
  }

  /// 循环重播调度（试听模式）。
  Timer? _loopTimer;
  Future<void> _scheduleLoop(String path, double volume) async {
    _loopTimer?.cancel();
    _loopTimer = Timer(const Duration(seconds: 6), () {
      if (!_previewing) return;
      unawaited(_audio.playSfx(path, volume: volume));
      unawaited(_scheduleLoop(path, volume));
    });
  }

  /// 停止试听。
  Future<void> stop() async {
    _previewing = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    await _audio.stopSfx();
  }

  /// 释放资源（停止试听并取消定时器）。
  void dispose() {
    _previewing = false;
    _loopTimer?.cancel();
    _loopTimer = null;
  }

  /// 解析音效资源路径：`minecraft_music/sfx/sounds/<sfxKey>/` 下的 ogg。
  static Future<String?> _resolveSfxPath(String sfxKey) async {
    if (kIsWeb) return null;
    final String? base = await _sfxBaseDir();
    if (base == null) return null;
    final Directory dir = Directory('$base/sfx/sounds/$sfxKey');
    if (!await dir.exists()) return null;
    await for (final FileSystemEntity e
        in dir.list(recursive: true, followLinks: false)) {
      if (e is File && e.path.toLowerCase().endsWith('.ogg')) {
        return e.path;
      }
    }
    return null;
  }

  /// 找到 minecraft_music 基础目录（与 [MinecraftSfxService] 同策略）。
  static Future<String?> _sfxBaseDir() async {
    if (kIsWeb) return null;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      const String dev = r'd:\Stellara\Music\minecraft_music';
      final File probe = File('$dev/sfx/sfx_manifest.json');
      if (await probe.exists()) return dev;
      return null;
    }
    for (final String prefix in [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
    ]) {
      final File probe =
          File('$prefix/minecraft_music/sfx/sfx_manifest.json');
      if (await probe.exists()) return '$prefix/minecraft_music';
    }
    return null;
  }
}
