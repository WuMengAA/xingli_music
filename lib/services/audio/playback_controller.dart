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
/// [recordOrder]：按播放记录推导的有序 trackKey 列表（最近播放在前）。
/// 非空时，顺序 / 倒序模式改按**播放记录顺序**切歌（而不是字母序），
/// 满足「上下歌切换考虑播放记录、默认下一首按播放记录」。
Track? nextTrackInLibrary(
  List<Track> lib,
  Track? current,
  PlayMode mode,
  int direction, {
  List<String>? recordOrder,
}) {
  if (lib.isEmpty) return null;

  final List<Track> sorted = _sortedByRecord(lib, recordOrder);

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

/// 排序：优先按 [recordOrder]（播放记录顺序），未收录的曲目按字母序追加；
/// 无记录顺序时按字母序（兼容旧行为）。
List<Track> _sortedByRecord(List<Track> lib, List<String>? recordOrder) {
  if (recordOrder == null || recordOrder.isEmpty) {
    return List<Track>.from(lib)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
  final Map<String, Track> byKey = <String, Track>{
    for (final Track t in lib) trackKeyOf(t.title, t.artist, t.sourceId): t,
  };
  final List<Track> ordered = <Track>[];
  for (final String k in recordOrder) {
    final Track? t = byKey.remove(k);
    if (t != null) ordered.add(t);
  }
  final List<Track> rest = byKey.values.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  ordered.addAll(rest);
  return ordered;
}
