/// 自动播放 / 自动过渡（cl46）。
///
/// - `autoPlayProvider`：当前曲播完后自动按播放顺序 / 歌单顺序播下一首（默认开）。
/// - `autoTransitionProvider`：接近末尾 5 秒淡出旧曲、淡入新曲（默认开，与
///   自动播放配合，构成无感的连续播放体验）。
/// - `autoPlayTrackerProvider`：App 启动挂接，监听曲目完成事件与进度流。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../services/audio/audio_service.dart';
import 'audio_providers.dart';
import 'playback_error_provider.dart';
import 'playback_notifier.dart';

/// 自动播放：曲目播完后自动下一首（默认开）。
final autoPlayProvider = StateProvider<bool>((Ref ref) => true);

/// 自动过渡：接近末尾 5 秒自动淡出淡入（默认开）。
final autoTransitionProvider = StateProvider<bool>((Ref ref) => true);

/// 末尾淡出窗口：距曲末该时长内开始淡出切歌。
const Duration kTransitionWindow = Duration(seconds: 5);

class AutoPlayTracker {
  AutoPlayTracker(this._ref);

  final Ref _ref;

  bool _started = false;
  bool _transitioning = false;
  Duration? _dur;
  AudioService? _audio;
  StreamSubscription<Duration?>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  /// 引擎错误流订阅（#playback-error）：汇入 [playbackErrorProvider]。
  StreamSubscription<String>? _errSub;

  void start() {
    if (_started) return;
    _started = true;
    // 保存实例：dispose 时容器已销毁，不能再用 _ref.read 访问 provider。
    final AudioService audio = _ref.read(audioServiceProvider);
    _audio = audio;
    audio.onCompleted = _onCompleted;
    _posSub = audio.positionStream.listen(_onPos);
    _durSub = audio.durationStream.listen((Duration? d) => _dur = d);
    // #playback-error：引擎错误（中途断流 / 加载失败）汇入常驻错误位。
    _errSub = audio.playErrorStream.listen((String msg) {
      final Track? t = audio.currentTrack;
      _ref.read(playbackErrorProvider.notifier).report(
        PlaybackError(
          message: msg,
          kind: t == null ? PlaybackRetryKind.none : PlaybackRetryKind.playTrack,
          track: t,
        ),
      );
    });
  }

  /// 曲目自然播放完成 → 自动切下一首。
  Future<void> _onCompleted() async {
    if (_transitioning) return; // 淡出切歌中，避免重复触发
    if (!_ref.read(autoPlayProvider)) return;
    if (_audio?.suppressAutoAdvance ?? false) return; // #486：睡眠「本曲结束」生效时不自动续播
    _transitioning = true;
    try {
      // #playback-error：下一首加载失败不再静默丢弃返回值，转常驻错误位。
      final String msg = await _ref.read(playbackActionsProvider).next();
      if (msg.isNotEmpty) {
        _ref.read(playbackErrorProvider.notifier).report(
          PlaybackError(message: msg, kind: PlaybackRetryKind.next),
        );
      }
    } finally {
      _transitioning = false;
    }
  }

  /// 接近末尾 5 秒：淡出当前曲并切下一首（自动过渡）。
  Future<void> _onPos(Duration? pos) async {
    if (_transitioning) return;
    if (!_ref.read(autoPlayProvider)) return;
    if (!_ref.read(autoTransitionProvider)) return;
    final Duration? d = _dur;
    if (pos == null || d == null || d.inMilliseconds <= 0) return;
    final int remain = d.inMilliseconds - pos.inMilliseconds;
    if (remain <= 0 || remain > kTransitionWindow.inMilliseconds) return;
    _transitioning = true;
    try {
      await _ref.read(audioServiceProvider).fadeOutMusic();
      // #playback-error：同上，失败返回值汇入常驻错误位。
      final String msg = await _ref.read(playbackActionsProvider).next();
      if (msg.isNotEmpty) {
        _ref.read(playbackErrorProvider.notifier).report(
          PlaybackError(message: msg, kind: PlaybackRetryKind.next),
        );
      }
    } finally {
      _transitioning = false;
    }
  }

  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _errSub?.cancel();
    _audio?.onCompleted = null;
    _audio = null;
  }
}

/// 自动播放跟踪器（App 启动处 watch 一次即生效）。
final autoPlayTrackerProvider = Provider<AutoPlayTracker>(
  (Ref ref) {
    final AutoPlayTracker t = AutoPlayTracker(ref);
    t.start();
    ref.onDispose(t.dispose);
    return t;
  },
);
