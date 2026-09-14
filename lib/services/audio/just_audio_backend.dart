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
  StreamSubscription<PlaybackEvent>? _errSub;
  StreamController<MusicEngineState>? _stateCtrl;
  final StreamController<String> _errCtrl = StreamController<String>.broadcast();

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
    // 播放中途错误（解码失败 / 网络 403 / 断网）：just_audio 把错误作为
    // **error 事件**投递到 [playbackEventStream]（见其内部
    // `onError: _playbackEventSubject.addError`），[PlayerState] 里并没有
    // error 字段。这里在同一个流上挂 onError，转成可读中文后汇入本后端的
    // [errorStream]（AudioService 再转 playErrorStream）。
    _errSub ??= _player.playbackEventStream.listen(
      (PlaybackEvent _) {},
      onError: (Object e, StackTrace _) {
        final String msg =
            e is PlayerException ? _describeError(e) : '播放中断：$e';
        if (!_errCtrl.isClosed) _errCtrl.add(msg);
      },
    );
    return ctrl.stream;
  }

  @override
  Stream<String> get errorStream => _errCtrl.stream;

  /// 把 just_audio 的 [PlayerException] 转成用户可读中文（含 403 / 网络提示）。
  static String _describeError(PlayerException e) {
    final String m = (e.message ?? '').toLowerCase();
    if (m.contains('403') || m.contains('401') || m.contains('forbidden')) {
      return '播放地址被拒绝（403/401），请检查曲源登录或会员状态';
    }
    if (m.contains('timed out') ||
        m.contains('timeout') ||
        m.contains('network') ||
        m.contains('socket')) {
      return '播放中断：网络不通或连接超时，请检查网络后重试';
    }
    if (m.contains('unable to load') || m.contains('decode') || m.contains('source')) {
      return '无法加载该曲目，源可能已失效或格式不支持';
    }
    return '播放出错：${e.message}';
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
  Future<void> openPath(String path, {Duration? start, Duration? end}) {
    final UriAudioSource src = AudioSource.file(path);
    final AudioSource toLoad = (start != null || end != null)
        ? ClippingAudioSource(child: src, start: start, end: end)
        : src;
    return _player.setAudioSource(toLoad);
  }

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
    await _errSub?.cancel();
    await _stateCtrl?.close();
    await _player.dispose();
    if (!_errCtrl.isClosed) await _errCtrl.close();
  }
}
