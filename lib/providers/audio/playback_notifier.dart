import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/playback_controller.dart';
import 'audio_providers.dart';

/// 播放动作封装（对应规格 Module 5：StateNotifier 封装 AudioPlayer）
///
/// 把"切换曲目 / 播放 / 暂停 / 选曲"等命令集中到这里，
/// 让 UI 只调用意图（toggle / next / prev / playTrack），
/// 具体如何选下一首、更新 nowPlaying、处理空曲库提示都由本类负责。
class PlaybackActions {
  PlaybackActions(this.ref);
  final Ref ref;

  AudioService get _audio => ref.read(audioServiceProvider);

  /// 切换播放 / 暂停：无曲目时播第一首。
  /// 返回需提示给用户的消息（空串表示成功、无需提示）。
  Future<String> toggle() async {
    final Track? now = ref.read(nowPlayingProvider);
    if (now == null) return _playFirst();
    await _audio.togglePlay();
    return '';
  }

  /// 切歌：direction = 1 下一首 / -1 上一首，遵循当前播放模式。
  /// 返回需提示给用户的消息（空串表示成功）。
  Future<String> next({int direction = 1}) async {
    final List<Track> library =
        await ref.read(effectiveMusicLibraryProvider.future);
    if (library.isEmpty) return '曲库为空，请先在曲库设置添加音乐';
    final Track? current = ref.read(nowPlayingProvider);
    final Track? chosen;
    if (current != null &&
        library.any((t) => t.uri == current.uri)) {
      chosen = nextTrackInLibrary(
          library, current, ref.read(playModeProvider), direction);
    } else {
      chosen =
          nextTrackInLibrary(library, null, ref.read(playModeProvider), 1);
    }
    if (chosen == null) return '';
    return _play(chosen);
  }

  /// 直接播放指定曲目
  Future<String> playTrack(Track track) => _play(track);

  /// 播放曲库第一首（仅当曲库非空）
  Future<String> _playFirst() async {
    final List<Track> library =
        await ref.read(effectiveMusicLibraryProvider.future);
    if (library.isEmpty) return '曲库为空，请先在曲库设置添加音乐';
    return _play(library.first);
  }

  Future<String> _play(Track track) async {
    await _audio.playMusic(track);
    ref.read(nowPlayingProvider.notifier).state = track;
    if (_audio.currentTrack == null) {
      return '无法播放「${track.title}」，文件可能不支持或不存在';
    }
    return '';
  }

  /// 设置播放模式
  void setMode(PlayMode mode) =>
      ref.read(playModeProvider.notifier).state = mode;
}

/// Module 5：播放动作 Provider（UI 统一入口）
final playbackActionsProvider =
    Provider<PlaybackActions>((ref) => PlaybackActions(ref));
