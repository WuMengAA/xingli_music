import 'dart:async';

import 'package:audio_service/audio_service.dart' as asvc;

import '../../models/track.dart';
import 'audio_service.dart';
import 'playback_controller.dart';

/// 系统媒体处理器：把星璃的播放状态桥接到 Android/iOS 的锁屏、通知栏与媒体键。
///
/// - 订阅 [AudioService] 的状态流，向系统发布 [asvc.PlaybackState] 与 [asvc.MediaItem]
/// - 系统控件的播放/暂停/切歌/拖动，全部转交 [PlaybackController] 处理
///
/// 这样后台播放、锁屏控件、耳机键都能正确驱动同一个播放引擎。
class StelarithAudioHandler extends asvc.BaseAudioHandler
    with asvc.SeekHandler {
  final PlaybackController _ctrl;

  final List<StreamSubscription<dynamic>> _subs = [];
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  PlaybackState _state = PlaybackState.idle;

  StelarithAudioHandler(this._ctrl) {
    _subs.add(_ctrl.audio.playingStream.listen((p) {
      _playing = p;
      _publishState();
    }));
    _subs.add(_ctrl.audio.positionStream.listen((p) {
      _position = p ?? Duration.zero;
      _publishState();
    }));
    _subs.add(_ctrl.audio.durationStream.listen((d) {
      _duration = d;
      _publishState();
      // 时长确定后用实时值刷新锁屏媒体项
      _publishMediaItem(_ctrl.audio.currentTrack);
    }));
    _subs.add(_ctrl.audio.stateStream.listen((s) {
      _state = s;
      _publishState();
    }));
    _subs.add(_ctrl.audio.trackStream.listen(_publishMediaItem));

    // 初始化当前媒体项与状态
    _publishMediaItem(_ctrl.audio.currentTrack);
    _publishState();
  }

  void _publishState() {
    playbackState.add(asvc.PlaybackState(
      controls: [
        asvc.MediaControl.skipToPrevious,
        _playing ? asvc.MediaControl.pause : asvc.MediaControl.play,
        asvc.MediaControl.skipToNext,
      ],
      systemActions: const {asvc.MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _mapState(_state),
      playing: _playing,
      updatePosition: _position,
    ));
  }

  asvc.AudioProcessingState _mapState(PlaybackState s) {
    switch (s) {
      case PlaybackState.loading:
        return asvc.AudioProcessingState.loading;
      case PlaybackState.playing:
      case PlaybackState.paused:
        return asvc.AudioProcessingState.ready;
      case PlaybackState.idle:
        return asvc.AudioProcessingState.idle;
    }
  }

  void _publishMediaItem(Track? t) {
    if (t == null) {
      mediaItem.add(const asvc.MediaItem(id: '', title: '星璃'));
      return;
    }
    Uri? artUri;
    if (t.coverPath != null) {
      artUri = Uri.file(t.coverPath!);
    } else if (t.coverUrl != null) {
      artUri = Uri.parse(t.coverUrl!);
    }
    mediaItem.add(asvc.MediaItem(
      id: t.uri,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: _duration ?? t.duration,
      artUri: artUri,
    ));
  }

  @override
  Future<void> play() => _ctrl.play();

  @override
  Future<void> pause() => _ctrl.pause();

  @override
  Future<void> seek(Duration position) => _ctrl.seek(position);

  @override
  Future<void> skipToNext() => _ctrl.skip(1);

  @override
  Future<void> skipToPrevious() => _ctrl.skip(-1);

  @override
  Future<void> click([asvc.MediaButton button = asvc.MediaButton.media]) async {
    if (button == asvc.MediaButton.media) await _ctrl.toggle();
  }

  @override
  Future<void> stop() async {
    await _ctrl.audio.pauseOnly();
    await super.stop();
  }

  Future<void> disposeHandler() async {
    for (final StreamSubscription<dynamic> s in _subs) {
      await s.cancel();
    }
  }
}
