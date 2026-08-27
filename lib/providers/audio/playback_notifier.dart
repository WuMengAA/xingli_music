import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scene.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/playback_controller.dart';
import '../scene/scene_providers.dart';
import '../stats/playback_relink_provider.dart';
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
        await ref.read(activePlaybackListProvider.future);
    if (library.isEmpty) return '曲库为空，请先在曲库设置添加音乐';
    final Track? current = ref.read(nowPlayingProvider);
    // cl64-3：nextTrackInLibrary 内部按 trackKey 匹配（不依赖 uri，
    // 流媒体 relink 后 uri 会变），默认按曲库列表顺序续播。
    // cl64-5：library 为 activePlaybackList（搜索队列 ?? 曲库）。
    final Track? chosen;
    if (current != null) {
      chosen = nextTrackInLibrary(
          library, current, ref.read(playModeProvider), direction);
    } else {
      chosen = nextTrackInLibrary(
          library, null, ref.read(playModeProvider), 1);
    }
    if (chosen == null) return '';
    return _play(chosen);
  }

  /// 直接播放指定曲目。
  ///
  /// [queue]：可选播放上下文列表（如聚合搜索结果）。非 null 时写入
  /// [playbackQueueProvider]，使后续续播在该列表内循环；为 null 时清空队列
  /// 回退曲库（cl64-5：搜索列表作播放队列）。
  Future<String> playTrack(Track track, {List<Track>? queue}) {
    ref.read(playbackQueueProvider.notifier).state =
        (queue != null && queue.isNotEmpty) ? queue : null;
    return _play(track);
  }

  /// 播放曲库第一首（仅当曲库非空）。
  ///
  /// R6：不再一律取「名称正序第一首」——优先取当前场景的默认曲目
  /// （`scene.track` 在曲库中命中时），否则回退到曲库首项。
  /// cl51-A：场景默认曲目优先；其次按播放记录顺序取「最近播过」的曲目；
  /// 都没有才回退曲库首项。
  Future<String> _playFirst() async {
    final List<Track> library =
        await ref.read(effectiveMusicLibraryProvider.future);
    if (library.isEmpty) return '曲库为空，请先在曲库设置添加音乐';
    final Track target = await _sceneDefaultTrack(library);
    return _play(target);
  }

  /// 取「当前场景默认曲目」：场景 `track` 名称在曲库中匹配到则用它，
  /// 否则按播放记录顺序取最近播过的曲目；都没有回退 `library.first`
  /// （R6，避免无脑正序第一首；cl51-A 增加记录顺序）。
  /// cl54-G4：await recordPlayOrderProvider.future（.valueOrNull 首帧为 null）。
  Future<Track> _sceneDefaultTrack(List<Track> library) async {
    final Scene scene = ref.read(activeSceneProvider);
    final String name = scene.track;
    if (name.isNotEmpty) {
      for (final Track t in library) {
        if (t.title.trim().toLowerCase() == name.trim().toLowerCase()) {
          return t;
        }
      }
    }
    final List<String> order = await ref.read(recordPlayOrderProvider.future);
    if (order.isNotEmpty) {
      for (final String key in order) {
        for (final Track t in library) {
          if (trackKeyOf(t.title, t.artist, t.sourceId) == key) return t;
        }
      }
    }
    return library.first;
  }

  Future<String> _play(Track track) async {
    try {
      // cl51-A：播放前重匹配直链——缓存链接优先，失效则按
      // 名称/时长/歌手聚合搜索自动匹配（见 playback_relink_provider）。
      final Track playable = await relinkForPlayback(ref, track);
      await _audio.playMusic(playable);
    } catch (e) {
      // 防御性兜底：播放失败返回提示而非向上抛（避免 UI 层闪退）
      return '无法播放「${track.title}」，请稍后重试';
    }
    // 仅当引擎确实加载成功（currentTrack 指向该曲）才更新 nowPlayingProvider；
    // 失败（如网易云解析失败）保持引擎真源，避免「曲名对不上」。
    if (_audio.currentTrack?.uri == track.uri) {
      ref.read(nowPlayingProvider.notifier).state = track;
    }
    if (_audio.currentTrack == null) {
      return '无法播放「${track.title}」，文件可能不支持或不存在';
    }
    return '';
  }

  /// 设置播放模式
  void setMode(PlayMode mode) =>
      ref.read(playModeProvider.notifier).state = mode;

  /// 设置倍速（0.25~4.0，1.0 为原速）。同步写入 [musicSpeedProvider] 与引擎。
  Future<void> setSpeed(double rate) async {
    ref.read(musicSpeedProvider.notifier).state = rate;
    await _audio.setMusicSpeed(rate);
  }
}

/// Module 5：播放动作 Provider（UI 统一入口）
final playbackActionsProvider =
    Provider<PlaybackActions>((ref) => PlaybackActions(ref));
