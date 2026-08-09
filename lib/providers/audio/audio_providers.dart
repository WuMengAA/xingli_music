import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/local_dir_config.dart';
import '../../models/play_mode.dart';
import '../../models/scene.dart';
import '../../models/server_config.dart';
import '../../models/track.dart';
import '../../providers/scene/scene_providers.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/minecraft_sfx_service.dart';
import '../../services/audio/playback_controller.dart';
import '../../services/log_service.dart';
import '../../services/music_sources/demo_source.dart';
import '../../services/music_sources/local_dir_music_source.dart';
import '../../services/music_sources/local_music_source.dart';
import '../../services/music_sources/minecraft_music_source.dart';
import '../../services/music_sources/music_source.dart';
import '../../services/music_sources/radio_source.dart';
import '../../services/music_sources/subsonic_source.dart';
import 'local_dir_providers.dart';
import 'server_config_provider.dart';

export '../../models/play_mode.dart';

/// Android 平台共享的 `AndroidEqualizer` 实例（v2 EQ）。
///
/// 非 Android 平台返回 `null`（不创建，避免平台通道调用）。
/// 该实例必须与下方 [audioServiceProvider] 的 `AudioPipeline` 使用
/// **同一个**实例，才能作用到正在播放的音乐。
final Provider<AndroidEqualizer?> androidEqualizerProvider =
    Provider<AndroidEqualizer?>((ref) {
  if (kIsWeb || !Platform.isAndroid) return null;
  return AndroidEqualizer();
});

/// 音频服务单例
final audioServiceProvider = Provider<AudioService>((ref) {
  // v2 EQ：Android 经 AudioPipeline(androidAudioEffects:) 装配真 EQ；
  // 其余平台走默认管线（模拟层）。
  final AndroidEqualizer? eq = ref.watch(androidEqualizerProvider);
  final AudioService service = AudioService(
    musicPipeline: eq != null
        ? AudioPipeline(androidAudioEffects: <AndroidEqualizer>[eq])
        : null,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// 「我的世界」主题音效调度器（场景激活时自动启停）
final minecraftSfxServiceProvider = Provider<MinecraftSfxService>(
  (ref) => MinecraftSfxService(ref.watch(audioServiceProvider)),
);

/// 已启用的数据源集合（本地 + 各外部源），供曲库聚合消费
final activeSourcesProvider = Provider<List<MusicSource>>((ref) {
  final List<ServerConfig> configs = ref.watch(serverConfigsProvider);
  final List<LocalDirConfig> dirs = ref.watch(localDirConfigsProvider);
  final List<MusicSource> sources = <MusicSource>[
    const LocalMusicSource(),
  ];
  for (final LocalDirConfig d in dirs) {
    if (!d.enabled) continue;
    sources.add(LocalDirMusicSource(d));
  }
  for (final ServerConfig c in configs) {
    if (!c.enabled) continue;
    if (c.type == SourceType.subsonic) {
      sources.add(SubsonicSource(c));
    } else {
      sources.add(RadioSource(tags: c.tags, sourceId: c.name));
    }
  }
  return sources;
});

/// 曲库：聚合所有启用的数据源（本地 / 自建服务器 / 电台）
///
/// 任一源失败不影响其它源；全部为空时回退到演示流媒体（无版权、可公网播放）。
final musicLibraryProvider = FutureProvider<List<Track>>((ref) async {
  final List<MusicSource> sources = ref.watch(activeSourcesProvider);
  final List<List<Track>> results = await Future.wait(
    sources.map((MusicSource s) async {
      try {
        return await s.getTracks();
      } catch (_) {
        return <Track>[];
      }
    }),
  );
  final List<Track> all = results.expand((e) => e).toList();
  LogService.instance.i(
      'library', '曲库聚合完成: ${all.length} 首 / ${sources.length} 个源');
  if (all.isEmpty) {
    LogService.instance.w('library', '所有源为空，回退演示流');
    return const DemoSource().getTracks();
  }
  return all;
});

/// 实际可用曲库：按当前场景过滤。
///
/// - 当前场景未指定专属音源 -> 返回聚合全量曲库
/// - 指定了（如 snow -> 'minecraft'）-> 只返回该音源的曲；缺失时回退全量
final effectiveMusicLibraryProvider = FutureProvider<List<Track>>((ref) async {
  final Scene scene = ref.watch(activeSceneProvider);
  if (scene.musicSourceId == null) {
    return ref.watch(musicLibraryProvider.future);
  }
  try {
    final List<Track> src = await const MinecraftMusicSource().getTracks();
    if (src.isNotEmpty) {
      LogService.instance.i(
          'library', '场景 ${scene.id} 使用专属音源 minecraft: ${src.length} 首');
      return src;
    }
  } catch (e) {
    LogService.instance.e('library', '场景专属音源加载失败: $e');
  }
  return ref.watch(musicLibraryProvider.future);
});

/// 当前播放曲目
final nowPlayingProvider = StateProvider<Track?>((ref) => null);

/// 是否播放中（由 just_audio 真实状态流驱动，永远与引擎一致）
final isPlayingProvider = StreamProvider<bool>((ref) {
  return ref.watch(audioServiceProvider).playingStream;
});

/// 显式播放状态机流（loading / playing / paused / idle），供 UI 精确判断
final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return ref.watch(audioServiceProvider).stateStream;
});

/// 当前音景场景 id
final activeSoundscapeProvider = StateProvider<String?>((ref) => null);

/// 播放方式：顺序 / 倒叙 / 随机 / 单曲循环（定义见 models/play_mode.dart）

/// 当前播放方式（默认顺序播放）
final playModeProvider = StateProvider<PlayMode>((ref) => PlayMode.order);

/// 播放控制器：统一 UI 与系统媒体控件（锁屏/通知栏/耳机键）的播放动作。
///
/// 切歌的「选曲逻辑」注入曲库 + 播放方式 + 当前曲目，保证系统控件切歌与界面一致。
final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final PlaybackController ctrl = PlaybackController(ref.watch(audioServiceProvider));
  ctrl.setResolvers(
    skip: (int dir) async {
      final List<Track> lib = await ref.read(effectiveMusicLibraryProvider.future);
      final Track? current = ref.read(nowPlayingProvider);
      final PlayMode mode = ref.read(playModeProvider);
      final Track? t = nextTrackInLibrary(lib, current, mode, dir);
      if (t != null) ref.read(nowPlayingProvider.notifier).state = t;
      return t;
    },
    first: () async {
      final List<Track> lib = await ref.read(effectiveMusicLibraryProvider.future);
      final PlayMode mode = ref.read(playModeProvider);
      final Track? t = nextTrackInLibrary(lib, null, mode, 1);
      if (t != null) ref.read(nowPlayingProvider.notifier).state = t;
      return t;
    },
  );
  return ctrl;
});

/// 收藏的曲目 uri 集合
final favoriteProvider = StateProvider<Set<String>>((ref) => <String>{});

/// 当前播放位置（用于进度反馈）
final musicPositionProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(audioServiceProvider).positionStream;
});

/// 当前曲目时长
final musicDurationProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(audioServiceProvider).durationStream;
});

/// 音乐声音量（0.0~1.0，默认 0.5 = 50%）
final musicVolumeProvider = StateProvider<double>((ref) => 0.5);

/// 背景声（音景）音量（默认 0.25 = 25%）
final soundscapeVolumeProvider = StateProvider<double>((ref) => 0.25);

/// 音乐声是否静音
final musicMutedProvider = StateProvider<bool>((ref) => false);

/// 背景声是否静音
final soundscapeMutedProvider = StateProvider<bool>((ref) => false);

/// 音量条是否展开（上滑音量按钮后出现）
final volumeSliderOpenProvider = StateProvider<bool>((ref) => false);

/// 音量交互计数：每次音量操作 +1（面板 3 秒无操作自动收起用）
final volumeActivityProvider = StateProvider<int>((ref) => 0);

/// 展示：是否显示粒子效果（默认开）
final showParticlesProvider = StateProvider<bool>((ref) => true);
