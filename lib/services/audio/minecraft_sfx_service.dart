import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../log_service.dart';
import 'audio_service.dart';

/// 「我的世界」主题音效调度器。
///
/// 在「我的世界」场景激活时，算法定时（随机间隔）从温和音效池
/// （脚步声/水流/音符/附魔/传送门/洞穴环境）里随机选一个低音量播放，
/// 叠加在背景音乐/音景之上，营造沉浸感。离开场景自动停止。
class MinecraftSfxService {
  MinecraftSfxService(this._audio);

  final AudioService _audio;

  Timer? _timer;
  final Random _rng = Random();
  String? _activeSceneId;
  String? _lastPlayed;
  final List<String> _pool = <String>[];
  bool _loading = false;

  /// 温和音效池（相对 minecraft_music 基础目录）
  static const List<String> _poolDirs = [
    'sfx/sounds/step',
    'sfx/sounds/liquid',
    'sfx/sounds/note',
    'sfx/sounds/enchant',
    'sfx/sounds/portal',
    'ambient/sounds/ambient/cave',
    'ambient/sounds/ambient/underwater',
  ];

  /// 当前是否在「我的世界」主题下运行
  bool get active => _activeSceneId == 'minecraft';

  /// 场景变化时调用：进入「我的世界」启动调度，离开停止
  Future<void> ensureScene(String? sceneId) async {
    if (sceneId == 'minecraft') {
      if (_activeSceneId == sceneId) return;
      _activeSceneId = sceneId;
      LogService.instance.i('sfx', '我的世界音效调度启动');
      await _ensurePool();
      _scheduleNext();
    } else {
      if (_activeSceneId == null) return;
      _activeSceneId = null;
      _cancel();
      await _audio.stopSfx();
      LogService.instance.i('sfx', '我的世界音效调度停止');
    }
  }

  /// 停止调度（应用退出时）
  void dispose() {
    _cancel();
  }

  /// 惰性加载音效池（一次）
  Future<void> _ensurePool() async {
    if (_pool.isNotEmpty || _loading) return;
    _loading = true;
    try {
      final String? base = await _baseDir();
      if (base == null) return;
      for (final String sub in _poolDirs) {
        final Directory dir = Directory('$base/$sub');
        if (!await dir.exists()) continue;
        await for (final FileSystemEntity e
            in dir.list(recursive: true, followLinks: false)) {
          if (e is! File) continue;
          if (e.path.toLowerCase().endsWith('.ogg')) {
            _pool.add(e.path);
          }
        }
      }
      LogService.instance.i(
          'sfx', '音效池加载完成: ${_pool.length} 个（基础目录 $base）');
    } catch (e) {
      LogService.instance.e('sfx', '音效池加载失败: $e');
    } finally {
      _loading = false;
    }
  }

  /// 排下一次播放：随机 8~20 秒后
  void _scheduleNext() {
    _cancel();
    final int delaySec = _rng.nextInt(13) + 8;
    _timer = Timer(Duration(seconds: delaySec), () {
      if (!active) return;
      unawaited(_playRandom());
      _scheduleNext();
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _playRandom() async {
    if (_pool.isEmpty) {
      await _ensurePool();
    }
    if (_pool.isEmpty) return;

    // 避免连续重复同一音效
    String pick;
    if (_pool.length <= 1) {
      pick = _pool.first;
    } else {
      int i = _rng.nextInt(_pool.length);
      if (_pool[i] == _lastPlayed) {
        i = (i + 1) % _pool.length;
      }
      pick = _pool[i];
    }
    _lastPlayed = pick;

    // 低音量叠加（0.15~0.30），不盖住音乐
    final double vol = 0.15 + _rng.nextDouble() * 0.15;
    await _audio.playSfx(pick, volume: vol);
  }

  /// 找到 minecraft_music 基础目录（桌面开发目录 / 移动端公共音乐目录）
  static Future<String?> _baseDir() async {
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
      final File probe = File('$prefix/minecraft_music/sfx/sfx_manifest.json');
      if (await probe.exists()) return '$prefix/minecraft_music';
    }
    return null;
  }
}
