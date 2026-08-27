import 'dart:math';

import '../../models/play_mode.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
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
///
/// 默认按**曲库列表顺序**续播（cl64-3：默认顺序改回曲库列表顺序）。
Track? nextTrackInLibrary(
  List<Track> lib,
  Track? current,
  PlayMode mode,
  int direction,
) {
  if (lib.isEmpty) return null;

  // 默认顺序：曲库列表顺序（保持稳定、可续播）。
  final List<Track> sorted = List<Track>.from(lib);

  if (current == null) {
    return mode == PlayMode.reverse ? sorted.last : sorted.first;
  }

  // cl64-3：按 trackKey 匹配而非 uri——流媒体经 relinkForPlayback 后
  // uri 从 netease:// 变 http 直链，与曲库占位 uri 不一致会导致永远命中
  // idx<0 而回退到第一首。改用 title|artist|sourceId 唯一键匹配。
  final String curKey =
      trackKeyOf(current.title, current.artist, current.sourceId);
  final int idx = sorted.indexWhere(
      (t) => trackKeyOf(t.title, t.artist, t.sourceId) == curKey);
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
