import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/local_dir_config.dart';
import '../../models/play_mode.dart';
import '../../models/scene.dart';
import '../../models/server_config.dart';
import '../../models/track.dart';
import '../../providers/scene/scene_custom_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/settings/performance_providers.dart';
import '../../providers/sources/netease_provider.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/media_kit_backend.dart';
import '../../services/audio/minecraft_sfx_service.dart';
import '../../services/audio/playback_controller.dart';
import '../../services/audio/sources/netease/netease_source.dart';
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
///
/// 兼容性兜底：Wear OS / 裁剪系统不支持 AudioEffect 时 `AndroidEqualizer()`
/// 构造会抛 [PlatformException]；捕获后返回 `null`，EQ 功能降级为关闭，
/// 不阻断音频服务初始化（之前会直接闪退）。
final Provider<AndroidEqualizer?> androidEqualizerProvider =
    Provider<AndroidEqualizer?>((ref) {
  if (kIsWeb || !Platform.isAndroid) return null;
  try {
    return AndroidEqualizer();
  } catch (e, st) {
    LogService.instance.w('eq', 'AndroidEqualizer 不可用（系统不支持？）: $e\n$st');
    return null;
  }
});

/// 音频服务单例
final audioServiceProvider = Provider<AudioService>((ref) {
  // v2 EQ：Android 经 AudioPipeline(androidAudioEffects:) 装配真 EQ；
  // 其余平台走默认管线（模拟层）。
  final AndroidEqualizer? eq = ref.watch(androidEqualizerProvider);
  // S2：播放引擎可选（设置→画面→性能与质量→播放引擎）。
  // just_audio：默认，支持 Android 真 EQ；media_kit：全格式/Hi-Res/无缝
  // （media_kit 下 AndroidEqualizer 不生效，EQ 走内置模拟层）。
  final bool useMediaKit =
      ref.watch(musicEngineProvider) == MusicEngine.mediaKit;
  final AudioService service = AudioService(
    musicPipeline: eq != null
        ? AudioPipeline(androidAudioEffects: <AndroidEqualizer>[eq])
        : null,
    musicBackend: useMediaKit ? MediaKitBackend() : null,
  );
  // 注入占位符解析器：netease://song/<id> 等占位 uri 在播放前解析成
  // 真实 CDN 地址并附加请求头（见 [buildStreamResolver]）。
  service.setStreamResolver(buildStreamResolver(ref.read));
  ref.onDispose(service.dispose);
  return service;
});

/// 只读 Provider 取值函数（`Ref.read` 与 `ProviderContainer.read` 均满足）。
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// 构造「按 sourceId 反查源并解析播放地址」的解析器，注入 [AudioService]。
///
/// - uri 已是 http(s) 直连地址 → 返回 null（走默认直连分支）；
/// - 占位符（如 `netease://song/<id>`）→ 找到对应源调 [MusicSource.resolveStreamUrl]，
///   得到 http 地址则连同源的 [MusicSource.playbackHeaders] 一起返回；
/// - 源缺失 / 解析异常 → null（回落默认分支，本地文件路径不受影响）；
/// - 源抛出 [NeteaseResolveException] → 转 [StreamResolveException] 供 UI 展示中文。
StreamResolver buildStreamResolver(ProviderReader read) {
  return (Track track) async {
    if (track.uri.startsWith('http')) return null;
    for (final MusicSource s in read(activeSourcesProvider)) {
      if (s.sourceId != track.sourceId) continue;
      try {
        final String url = await s.resolveStreamUrl(track);
        if (url.startsWith('http')) {
          return ResolvedStream(url, s.playbackHeaders);
        }
      } on NeteaseResolveException catch (e) {
        throw StreamResolveException(e.message);
      } catch (_) {
        return null;
      }
      return null;
    }
    return null;
  };
}

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
  // 网易云：enabled 随登录态变化；getTracks() 当前返回空（歌单后续接入），
  // 仅承担「搜索 + 懒解析播放」，加入集合不污染曲库聚合。
  sources.add(ref.watch(neteaseSourceProvider));
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

/// 音乐声音量（0.0~1.0，R12 初始 0.7 = 70%）
final musicVolumeProvider = StateProvider<double>((ref) => 0.7);

/// 主音量（Master，R23i：全局整体音量，所有通道 × master，默认 1.0 = 100%）
final masterVolumeProvider = StateProvider<double>((ref) => 1.0);

/// 音效（SFX）通道音量（R23i：独立于音乐/背景/白噪，默认 0.5）
final sfxVolumeProvider = StateProvider<double>((ref) => 0.5);

/// 背景声（音景）音量（默认 0.12 = 12%，R23n 源响度降半后默认也降半）
final soundscapeVolumeProvider = StateProvider<double>((ref) => 0.12);

/// 音乐声是否静音
final musicMutedProvider = StateProvider<bool>((ref) => false);

/// 背景声是否静音
final soundscapeMutedProvider = StateProvider<bool>((ref) => false);

/// 白噪音是否开启（R4，全局开关，独立于场景音景）
/// 默认开启：用户反馈希望默认就有环境白噪底噪。
final whiteNoiseEnabledProvider = StateProvider<bool>((ref) => true);

/// 白噪音音量（R4，0.0~1.0，默认 0.15 = 15%，R23n 源响度降半后默认也降半）
final whiteNoiseVolumeProvider = StateProvider<double>((ref) => 0.15);

/// 世界空间音效通道音量（#170，0.0~1.0，默认 0.6）。
///
/// 由体素 3D 视图下发到 `WorldAudioEngine.setGlobalVolume`（引擎实例随视图
/// 创建/销毁，故不经 AudioService 直接持有）。
final worldSfxVolumeProvider = StateProvider<double>((ref) => 0.6);

/// 提示音通道音量（#170，0.0~1.0，默认 0.5）。
final uiCueVolumeProvider = StateProvider<double>((ref) => 0.5);

// ── #167：白噪音跟随场景 / 全局播放 ───────────────────

/// 白噪音是否**跟随当前场景**（#167，默认 true = 跟随）。
///
/// - `true`（跟随场景）：白噪音开关与音量取自 [activeSceneProvider] 的
///   `Scene.whiteNoise` / `Scene.whiteNoiseVolume`，换场景自动切换；
/// - `false`（全局播放）：忽略场景设置，统一用
///   [whiteNoiseEnabledProvider] / [whiteNoiseVolumeProvider]。
final whiteNoiseFollowsSceneProvider = StateProvider<bool>((ref) => true);

/// 白噪音的**生效状态**（#167）：按跟随开关在「场景 / 全局」两个来源间取值。
///
/// 这是白噪音的唯一权威来源 —— 场景切换、跟随开关、全局开关三者任一变化
/// 都会让它重算，`settingsSyncProvider` 监听它并下发到 [AudioService]。
typedef WhiteNoiseState = ({bool on, double volume});

final effectiveWhiteNoiseProvider = Provider<WhiteNoiseState>((ref) {
  if (!ref.watch(whiteNoiseFollowsSceneProvider)) {
    return (
      on: ref.watch(whiteNoiseEnabledProvider),
      volume: ref.watch(whiteNoiseVolumeProvider),
    );
  }
  final Scene scene = ref.watch(activeSceneProvider);
  return (on: scene.whiteNoise, volume: scene.whiteNoiseVolume);
});

/// 把白噪音设置写入**当前场景**（#167：跟随场景模式下的编辑入口）。
///
/// 内置场景以「覆盖副本」（同 id）形式存进 [customScenesProvider]，因此
/// 设置随场景持久化、重启仍在。传 null 的参数保持原值。
Future<void> saveSceneWhiteNoise(
  WidgetRef ref, {
  bool? on,
  double? volume,
}) async {
  final Scene scene = ref.read(activeSceneProvider);
  await ref.read(customScenesProvider.notifier).save(
        scene.copyWith(whiteNoise: on, whiteNoiseVolume: volume),
      );
}

/// 音量均衡模式（R15：高保真 / 普通，默认普通）
final balanceModeProvider = StateProvider<BalanceMode>((ref) => BalanceMode.normal);

/// 音量条是否展开（上滑音量按钮后出现）
final volumeSliderOpenProvider = StateProvider<bool>((ref) => false);

/// 音量交互计数：每次音量操作 +1（面板 3 秒无操作自动收起用）
final volumeActivityProvider = StateProvider<int>((ref) => 0);

/// 展示：是否显示粒子效果（默认开）
final showParticlesProvider = StateProvider<bool>((ref) => true);
