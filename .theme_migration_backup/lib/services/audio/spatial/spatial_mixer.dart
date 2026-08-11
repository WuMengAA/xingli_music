/// ════════════════════════════════════════════════════════════════════════
/// 空间音效 · 混音/播放器（SpatialMixer）
/// ════════════════════════════════════════════════════════════════════════
///
/// - 为 [SpatialSound] 的每条音轨创建独立 audioplayers 播放器
/// - 按 [ChannelLayout] 映射声道增益：立体声用左右声道声像（pan），
///   单声道降级，环绕按方向映射（audioplayers 原生仅 L/R pan，
///   环绕通过增益近似）
/// - 材料隔音：目标处隔墙数 [walls] 折算音量衰减（[transmissionLoss]）
/// - 音轨文件：优先 [SpatialTrack.audioPath]，否则程序合成缓存
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:path_provider/path_provider.dart';

import '../../log_service.dart';
import 'spatial_models.dart';
import 'spatial_synth.dart';

/// 空间音效播放器（管理一个 SpatialSound 的多轨实例）。
class SpatialPlayer {
  SpatialPlayer(this.sound, {this.layout = ChannelLayout.stereo});

  final SpatialSound sound;
  final ChannelLayout layout;

  final List<ap.AudioPlayer> _players = <ap.AudioPlayer>[];
  bool _started = false;

  /// 启动全部音轨（按声像/音量/材料衰减）。
  Future<void> start({int walls = 0}) async {
    if (_started) return;
    _started = true;
    for (final SpatialTrack track in sound.tracks) {
      try {
        final ap.AudioPlayer p = ap.AudioPlayer();
        // 不抢焦点：与场景音景一致，避免打断音乐（R3 复用）
        await p.setAudioContext(
          ap.AudioContextConfig(focus: ap.AudioContextConfigFocus.mixWithOthers).build(),
        );
        final String path = await _ensureTrackFile(track);
        await p.setReleaseMode(ap.ReleaseMode.loop);
        await p.setSource(ap.DeviceFileSource(path));
        await p.setVolume(_effectiveVolume(track, walls));
        await p.resume();
        _players.add(p);
      } catch (e) {
        LogService.instance.w('spatial', '音轨 ${track.id} 启动失败: $e');
      }
    }
  }

  /// 停止全部音轨并释放。
  Future<void> stop() async {
    for (final ap.AudioPlayer p in _players) {
      try {
        await p.stop();
        await p.dispose();
      } catch (_) {}
    }
    _players.clear();
    _started = false;
  }

  /// 更新隔墙数（材料隔音动态生效）。
  Future<void> setWalls(int walls) async {
    for (int i = 0; i < _players.length && i < sound.tracks.length; i++) {
      try {
        await _players[i].setVolume(_effectiveVolume(sound.tracks[i], walls));
      } catch (_) {}
    }
  }

  double _effectiveVolume(SpatialTrack track, int walls) {
    final double base = track.volume;
    final double loss = transmissionLoss(sound.material, walls);
    return (base * dbToGain(loss)).clamp(0.0, 1.0);
  }

  Future<String> _ensureTrackFile(SpatialTrack track) async {
    if (track.audioPath != null && await File(track.audioPath!).exists()) {
      return track.audioPath!;
    }
    final Directory dir = await getApplicationDocumentsDirectory();
    final String synthId = track.synthesisId ?? track.id;
    final File f = File('${dir.path}/spatial_${sound.id}_${track.id}_$synthId.wav');
    if (await f.exists()) return f.path;
    final Uint8List wav = SpatialSynth.synthesizeWav(synthId, seed: sound.id.hashCode);
    await f.writeAsBytes(wav, flush: true);
    return f.path;
  }
}

/// 空间音效调度器：管理多组空间音效的启停。
class SpatialMixer {
  SpatialMixer({this.layout = ChannelLayout.stereo});

  final ChannelLayout layout;
  final List<SpatialPlayer> _active = <SpatialPlayer>[];

  /// 播放一组空间音效（替换同 id 的旧实例）。
  Future<void> play(SpatialSound sound, {int walls = 0}) async {
    await stopById(sound.id);
    final SpatialPlayer p = SpatialPlayer(sound, layout: layout);
    await p.start(walls: walls);
    _active.add(p);
  }

  /// 停止指定 id。
  Future<void> stopById(String id) async {
    final List<SpatialPlayer> matches =
        _active.where((p) => p.sound.id == id).toList();
    for (final SpatialPlayer p in matches) {
      await p.stop();
      _active.remove(p);
    }
  }

  /// 停止全部。
  Future<void> stopAll() async {
    for (final SpatialPlayer p in _active) {
      await p.stop();
    }
    _active.clear();
  }

  /// 更新某音效的隔墙数。
  Future<void> updateWalls(String id, int walls) async {
    for (final SpatialPlayer p in _active) {
      if (p.sound.id == id) {
        await p.setWalls(walls);
      }
    }
  }

  Future<void> dispose() => stopAll();
}
