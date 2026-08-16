/// ════════════════════════════════════════════════════════════════════════
/// just_audio 后端（S2 · 现状保持，行为零变化）
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'music_backend.dart';

/// 基于 just_audio 0.9.x 的实现（AudioService 现有引擎）。
class JustAudioBackend implements MusicBackend {
  JustAudioBackend({AudioPipeline? audioPipeline})
      : _player = AudioPlayer(audioPipeline: audioPipeline);

  final AudioPlayer _player;
  StreamSubscription<PlayerState>? _psSub;
  StreamController<MusicEngineState>? _stateCtrl;

  @override
  bool get playing => _player.playing;

  @override
  double get volume => _player.volume;

  @override
  Stream<MusicEngineState> get stateStream {
    final StreamController<MusicEngineState> ctrl =
        _stateCtrl ??= StreamController<MusicEngineState>.broadcast();
    _psSub ??= _player.playerStateStream.listen((PlayerState ps) {
      ctrl.add(MusicEngineState(
        processing: switch (ps.processingState) {
          ProcessingState.idle => MusicProcess.idle,
          ProcessingState.loading ||
          ProcessingState.buffering =>
            MusicProcess.loading,
          ProcessingState.ready => MusicProcess.ready,
          ProcessingState.completed => MusicProcess.completed,
        },
        playing: ps.playing,
      ));
    });
    return ctrl.stream;
  }

  @override
  Stream<Duration?> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Future<void> openUri(Uri uri, {Map<String, String>? headers}) =>
      _player.setAudioSource(
        AudioSource.uri(uri, headers: headers),
      );

  @override
  Future<void> openUrl(String url, {Map<String, String>? headers}) =>
      headers == null || headers.isEmpty
          ? _player.setUrl(url)
          : _player.setUrl(url, headers: headers);

  @override
  Future<void> openPath(String path) => _player.setFilePath(path);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSpeed(double rate) => _player.setSpeed(rate);

  // I（均衡器）：just_audio 桌面无 EQ API → 不支持（返回 false，回退模拟层）。
  @override
  Future<bool> setEqualizerFilter(String afFilter) async => false;

  @override
  Future<void> dispose() async {
    await _psSub?.cancel();
    await _stateCtrl?.close();
    await _player.dispose();
  }
}
