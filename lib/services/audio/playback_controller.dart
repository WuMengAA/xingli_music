import 'dart:math';

import '../../models/play_mode.dart';
import '../../models/track.dart';
import 'audio_service.dart';

/// 播放控制器：把「播放 / 暂停 / 跳转 / 上一首 / 下一首」统一成一套动作，
/// 同时供 UI 控件与系统媒体控件（锁屏 / 通知栏 / 耳机键）调用。
///
/// 切歌的「选曲逻辑」（根据曲库 + 播放方式）通过 [setResolvers] 注入，
/// 这样控制器本身不依赖 Riverpod，系统媒体控件也能在无 UI 时正确选曲。
class PlaybackController {
  final AudioService audio;

  Future<Track?> Function(int direction)? _skip;
  Future<Track?> Function()? _first;

  PlaybackController(this.audio);

  /// 注入选曲解析器（由 Riverpod 层用曲库/播放方式/当前曲目构造）
  void setResolvers({
    required Future<Track?> Function(int direction) skip,
    required Future<Track?> Function() first,
  }) {
    _skip = skip;
    _first = first;
  }

  /// 系统「播放」键：已有曲目则续播，否则从曲库挑第一首开始
  Future<void> play() async {
    if (audio.currentTrack != null) {
      await audio.resume();
      return;
    }
    final Track? t = await _first?.call();
    if (t != null) await audio.playMusic(t);
  }

  /// 系统「暂停」键
  Future<void> pause() => audio.pauseOnly();

  /// 系统「播放/暂停」媒体键（耳机键）
  Future<void> toggle() => audio.togglePlay();

  /// 系统进度条拖动
  Future<void> seek(Duration position) => audio.seek(position);

  /// 系统「上一首 / 下一首」
  Future<void> skip(int direction) async {
    final Track? t = await _skip?.call(direction);
    if (t != null) await audio.playMusic(t);
  }
}

/// 在曲库中按播放方式选出下一首。
///
/// 抽取自 ControlBar 的切歌逻辑，UI 与系统控件共用同一套选曲规则，
/// 保证锁屏切歌和界面内切歌行为一致。
Track? nextTrackInLibrary(
  List<Track> lib,
  Track? current,
  PlayMode mode,
  int direction,
) {
  if (lib.isEmpty) return null;

  final List<Track> sorted = List<Track>.from(lib)
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  if (current == null) {
    return mode == PlayMode.reverse ? sorted.last : sorted.first;
  }

  final int idx = sorted.indexWhere((t) => t.uri == current.uri);
  if (idx < 0) {
    return mode == PlayMode.reverse ? sorted.last : sorted.first;
  }

  if (mode == PlayMode.shuffle) {
    if (sorted.length == 1) return sorted.first;
    final Random rnd = Random();
    int r = idx;
    while (r == idx) {
      r = rnd.nextInt(sorted.length);
    }
    return sorted[r];
  }

  if (mode == PlayMode.loop) return current;

  final int next = idx + (mode == PlayMode.reverse ? -1 : 1) * direction.sign;
  if (next < 0) return sorted.last;
  if (next >= sorted.length) return sorted.first;
  return sorted[next];
}
