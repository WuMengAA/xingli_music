import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/throttled_binding.dart';
import '../../models/scene.dart';
import '../../models/track.dart';
import '../../repositories/settings_repository.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/eq_engine.dart';
import '../../services/log_service.dart';
import '../audio/audio_providers.dart';
import '../audio/equalizer_providers.dart';
import '../scene/scene_providers.dart';
import '../session/session_providers.dart';
import '../storage/storage_providers.dart';
import '../theme/theme_providers.dart';
import '../voxel/graphics_quality_provider.dart';
import 'oobe_choice_providers.dart';
import '../../widgets/voxel/voxel_world_view3d.dart' show GraphicsQuality;
import 'log_upload_providers.dart';
import 'llm_providers.dart';
import 'performance_providers.dart';
import '../../widgets/voxel/voxel_renderer.dart' show LodQuality;

/// 全局设置仓库（R10/R11 收口）。
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(prefsProvider)),
);

/// 冷启动恢复（R10）：把 [SettingsRepository] 里的值灌回各 StateProvider。
///
/// 由 AppShell.initState 帧后调用一次（Provider 初始化期禁止改其它
/// provider，因此这里做成普通函数，不放进 Provider 的 build）。
Future<void> restoreSettings(WidgetRef ref) async {
  final SettingsRepository repo = ref.read(settingsRepositoryProvider);

  // 音量
  ref.read(musicVolumeProvider.notifier).state = repo.musicVolume;
  ref.read(musicSpeedProvider.notifier).state = repo.musicSpeed;
  ref.read(soundscapeVolumeProvider.notifier).state = repo.soundscapeVolume;
  ref.read(masterVolumeProvider.notifier).state = repo.masterVolume;
  ref.read(sfxVolumeProvider.notifier).state = repo.sfxVolume;
  ref.read(musicMutedProvider.notifier).state = repo.musicMuted;
  ref.read(soundscapeMutedProvider.notifier).state = repo.soundscapeMuted;

  // 白噪音（#167：含「跟随场景 / 全局播放」开关）
  ref.read(whiteNoiseEnabledProvider.notifier).state = repo.whiteNoiseEnabled;
  ref.read(whiteNoiseVolumeProvider.notifier).state = repo.whiteNoiseVolume;
  ref.read(whiteNoiseFollowsSceneProvider.notifier).state =
      repo.whiteNoiseFollowsScene;

  // #170：世界空间音效 / 提示音通道音量
  ref.read(worldSfxVolumeProvider.notifier).state = repo.worldSfxVolume;
  ref.read(uiCueVolumeProvider.notifier).state = repo.uiCueVolume;

  // 播放模式
  final PlayMode mode = PlayMode.values.firstWhere(
    (m) => m.name == repo.playMode,
    orElse: () => PlayMode.order,
  );
  ref.read(playModeProvider.notifier).state = mode;

  // 主题
  ref.read(themeModeNameProvider.notifier).state = repo.themeMode;
  ref.read(themeSkinProvider.notifier).state = repo.themeSkin;

  // EQ
  ref.read(eqEnabledProvider.notifier).state = repo.eqEnabled;
  final String presetId = repo.eqPresetId;
  final EqPreset preset = kEqPresets.firstWhere(
    (p) => p.id == presetId,
    orElse: () => kEqPresets.first,
  );
  ref.read(eqPresetProvider.notifier).state = preset;
  final List<double> gains = repo.eqGains;
  if (gains.length == kEqFrequencies.length) {
    ref.read(eqCustomGainsProvider.notifier).state = gains;
  }

  // 均衡模式
  ref.read(balanceModeProvider.notifier).state =
      repo.balanceMode == 'hifi' ? BalanceMode.hifi : BalanceMode.normal;

  // 性能与质量体系（R21 两档；旧三档值自动迁移）
  final String perf = repo.performanceMode;
  ref.read(performanceModeProvider.notifier).state =
      _mapLegacyPerformance(perf);
  ref.read(fpsLimitProvider.notifier).state = FpsLimit.values.firstWhere(
    (FpsLimit f) => '${f.value}' == repo.fpsLimit,
    orElse: () => FpsLimit.fps60,
  );
  // 同步全局帧率节流目标（ThrottledWidgetsBinding 读取）
  throttledFps = ref.read(fpsLimitProvider).value;
  // 体素区块 / LOD（R23m）
  ref.read(viewDistanceChunksProvider.notifier).state =
      repo.viewDistanceChunks.clamp(2, 4); // cl76_hotfix3：视距上限 4
  ref.read(lodStartChunksProvider.notifier).state =
      repo.lodStartChunks.clamp(0, 6);
  ref.read(lodStepChunksProvider.notifier).state =
      repo.lodStepChunks.clamp(1, 4);
  // R26r18·P6/P3：LOD 质量档位 + 视锥剔除开关持久化恢复
  ref.read(lodQualityProvider.notifier).state = repo.lodQuality;
  ref.read(lodFrustumCullProvider.notifier).state = repo.lodFrustumCull;
  // R26m：3D 画质档（流畅/标准/高清）持久化恢复
  ref.read(graphicsQualityProvider.notifier).state = GraphicsQuality.values[
      repo.graphicsQuality.clamp(0, GraphicsQuality.values.length - 1)];
  // 图形后端：Vulkan 在 Windows 引擎不可用（R22），遗留配置自动回退 DX11
  EngineBackend backend = EngineBackend.values.firstWhere(
    (EngineBackend e) => e.name == repo.engineBackend,
    orElse: () => EngineBackend.auto,
  );
  if (backend == EngineBackend.impellerVulkan) {
    backend = EngineBackend.impellerD3D11;
    repo.setEngineBackend(backend.name);
  }
  ref.read(engineBackendProvider.notifier).state = backend;
  ref.read(noiseOverrideProvider.notifier).state = repo.noiseOverride;
  ref.read(faceCullEnabledProvider.notifier).state =
      repo.faceCull ?? ref.read(faceCullEnabledProvider);
  ref.read(occlusionCullEnabledProvider.notifier).state =
      repo.occlusionCull ?? ref.read(occlusionCullEnabledProvider);
  ref.read(backFaceCullEnabledProvider.notifier).state =
      repo.backFaceCull ?? ref.read(backFaceCullEnabledProvider);
  ref.read(frustumCullEnabledProvider.notifier).state =
      repo.frustumCull ?? ref.read(frustumCullEnabledProvider);
  ref.read(underwaterFilterEnabledProvider.notifier).state =
      repo.underwaterFilter ?? ref.read(underwaterFilterEnabledProvider);
  ref.read(waterFlowEnabledProvider.notifier).state =
      repo.waterFlow ?? ref.read(waterFlowEnabledProvider);
  ref.read(flashlightEnabledProvider.notifier).state =
      repo.flashlight ?? ref.read(flashlightEnabledProvider);
  ref.read(lodEnabledProvider.notifier).state =
      repo.lodEnabled ?? ref.read(lodEnabledProvider);
  ref.read(lodStepBlocksProvider.notifier).state =
      repo.lodStepBlocks?.clamp(1, 24) ?? ref.read(lodStepBlocksProvider);
  ref.read(lodSampleBaseProvider.notifier).state =
      repo.lodSampleBase?.clamp(1, 8) ?? ref.read(lodSampleBaseProvider);
  ref.read(lodMaxChunksProvider.notifier).state =
      repo.lodMaxChunks?.clamp(1, 64) ?? ref.read(lodMaxChunksProvider);
  ref.read(shadowRenderProvider.notifier).state =
      repo.shadowRender ?? ref.read(shadowRenderProvider);
  ref.read(aoEnabledProvider.notifier).state =
      repo.aoEnabled ?? ref.read(aoEnabledProvider);
  ref.read(outlineEnabledProvider.notifier).state =
      repo.outlineEnabled ?? ref.read(outlineEnabledProvider);
  ref.read(boundaryFogEnabledProvider.notifier).state =
      repo.boundaryFog ?? ref.read(boundaryFogEnabledProvider);
  // R26fx3：单一「渲染精度」滑杆取代原 renderScale(分辨率)×renderRatio(比例)。
  ref.read(renderPrecisionScaleProvider.notifier).state =
      repo.renderPrecisionScale?.clamp(0.25, 2.0) ??
          ref.read(renderPrecisionScaleProvider);
  ref.read(picturePresetProvider.notifier).state =
      PicturePreset.values.firstWhere(
    (PicturePreset p) => p.name == repo.picturePreset,
    orElse: () => PicturePreset.standard,
  );
  ref.read(renderPrecisionProvider.notifier).state =
      repo.renderPrecision?.clamp(0.5, 2.0) ?? ref.read(renderPrecisionProvider);
  // cl76_hotfix：OOBE 仅对新人开放——无 oobeDone 记录时按「是否有历史设置键」
  // 判断：老用户升级视为已完成（跳过 OOBE 开屏），全新安装才走 OOBE。
  ref.read(oobeDoneProvider.notifier).state =
      repo.oobeDone ?? repo.hasLegacySettings;
  ref.read(glassBlurOverrideProvider.notifier).state = repo.glassBlurOverride;
  ref.read(bgAnimationOverrideProvider.notifier).state =
      repo.bgAnimationOverride;
  ref.read(liquidGlassOverrideProvider.notifier).state =
      repo.liquidGlassOverride;
  ref.read(uiDensityProvider.notifier).state =
      UiDensity.values.firstWhere(
    (UiDensity d) => d.name == repo.uiDensity,
    orElse: () => UiDensity.standard,
  );
  // R26skel-b3：全局 UI 大小恢复（越界夹紧）。
  ref.read(uiScaleProvider.notifier).state =
      repo.uiScale.clamp(kUiScaleMin, kUiScaleMax);
  // 引擎：仅当用户显式选过才覆盖；否则沿用 [musicEngineProvider] 的平台默认值
  // （Android 默认 media_kit，规避 ExoPlayer 切歌崩溃）。
  final String engineName = repo.musicEngine;
  if (engineName.isNotEmpty) {
    ref.read(musicEngineProvider.notifier).state = MusicEngine.values.firstWhere(
      (MusicEngine e) => e.name == engineName,
      orElse: () => ref.read(musicEngineProvider),
    );
  }

  // 日志上报（云端日志）
  ref.read(logUploadEnabledProvider.notifier).state = repo.logUploadEnabled;
  ref.read(logUploadEndpointProvider.notifier).state = repo.logUploadEndpoint;
  // 详细日志（DEBUG）开关 → 直接作用于 LogService
  ref.read(logDebugEnabledProvider.notifier).state = repo.logDebugEnabled;
  LogService.debugEnabled = repo.logDebugEnabled;

  // 第三方大模型（地址/模型名普通持久化；API Key 从 SecureBox 密文恢复）
  ref.read(llmBaseUrlProvider.notifier).state = repo.llmBaseUrl;
  ref.read(llmModelProvider.notifier).state = repo.llmModel;
  // OOBE 选择/询问（cl75）：初始化收集的用户偏好灌回。
  ref.read(audioQualityProvider.notifier).state = repo.audioQuality;
  ref.read(analyticsConsentProvider.notifier).state = repo.analyticsConsent;
  ref.read(listenSourcesProvider.notifier).state = repo.listenSources.isEmpty
      ? <String>{}
      : repo.listenSources.split(',').toSet();
  await restoreLlmApiKey(ref.read);

  // 当前场景（按 id 映射到会话顺序中的索引）
  final String? sceneId = repo.currentSceneId;
  if (sceneId != null) {
    final List<Scene> scenes = ref.read(sceneOrderProvider);
    final int idx = scenes.indexWhere((s) => s.id == sceneId);
    if (idx >= 0) {
      ref.read(currentSceneIndexProvider.notifier).state = idx;
    }
  }

  // 上次曲目（仅恢复展示，不自动播放）
  final String? uri = repo.lastTrackUri;
  if (uri != null) {
    ref.read(nowPlayingProvider.notifier).state = Track(
      title: repo.lastTrackTitle ?? '上次播放',
      artist: repo.lastTrackArtist ?? '',
      uri: uri,
      source: TrackSource.local,
      sourceId: 'restored',
    );
  }

  // 应用音量/均衡/白噪音到引擎
  final AudioService audio = ref.read(audioServiceProvider);
  await audio.setMasterVolume(repo.masterVolume);
  await audio.setSfxVolume(repo.sfxVolume);
  await audio.setMusicVolume(repo.musicVolume);
  await audio.setMusicSpeed(repo.musicSpeed);
  await audio.setSoundscapeVolume(repo.soundscapeVolume);
  await audio.setMusicMuted(repo.musicMuted);
  await audio.setSoundscapeMuted(repo.soundscapeMuted);
  await audio.setBalanceMode(
      repo.balanceMode == 'hifi' ? BalanceMode.hifi : BalanceMode.normal);
  await audio.setWorldSfxVolume(repo.worldSfxVolume);
  await audio.setUiCueVolume(repo.uiCueVolume);
  // #167：白噪音按「生效来源」恢复 —— 跟随场景时用当前场景的设置，
  // 全局播放时用全局开关/音量（不再直接读 repo 的全局值）。
  final WhiteNoiseState wn = ref.read(effectiveWhiteNoiseProvider);
  await audio.setWhiteNoiseVolume(wn.volume);
  await audio.setWhiteNoise(wn.on);
}

/// 运行期同步写回（R11）：监听关键 StateProvider 变化，即时落盘。
///
/// 由 AppShell.build 顶层 `ref.watch(settingsSyncProvider)` 保持存活。
final settingsSyncProvider = Provider<void>((ref) {
  final SettingsRepository repo = ref.watch(settingsRepositoryProvider);

  ref.listen<double>(musicVolumeProvider, (_, v) => repo.setMusicVolume(v));
  ref.listen<double>(musicSpeedProvider, (_, v) => repo.setMusicSpeed(v));
  ref.listen<double>(soundscapeVolumeProvider, (_, v) => repo.setSoundscapeVolume(v));
  ref.listen<double>(masterVolumeProvider, (_, v) {
    repo.setMasterVolume(v);
    unawaited(ref.read(audioServiceProvider).setMasterVolume(v));
  });
  ref.listen<double>(sfxVolumeProvider, (_, v) {
    repo.setSfxVolume(v);
    unawaited(ref.read(audioServiceProvider).setSfxVolume(v));
  });
  ref.listen<bool>(musicMutedProvider, (_, v) => repo.setMusicMuted(v));
  ref.listen<bool>(soundscapeMutedProvider, (_, v) => repo.setSoundscapeMuted(v));
  // #167：白噪音的全局开关/音量只负责落盘；真正下发引擎统一交给下方
  // [effectiveWhiteNoiseProvider] 监听（避免「跟随场景」时被全局值覆盖）。
  ref.listen<bool>(whiteNoiseEnabledProvider, (_, v) {
    repo.setWhiteNoiseEnabled(v);
  });
  ref.listen<double>(whiteNoiseVolumeProvider, (_, v) {
    repo.setWhiteNoiseVolume(v);
  });
  ref.listen<bool>(whiteNoiseFollowsSceneProvider, (_, v) {
    repo.setWhiteNoiseFollowsScene(v);
  });
  // #167：白噪音生效状态（场景 / 全局）→ 引擎。
  // 场景切换、跟随开关、全局开关任一变化都会命中这里，白噪音永远与来源一致。
  ref.listen<WhiteNoiseState>(effectiveWhiteNoiseProvider, (_, WhiteNoiseState s) {
    final AudioService a = ref.read(audioServiceProvider);
    unawaited(a.setWhiteNoiseVolume(s.volume));
    unawaited(a.setWhiteNoise(s.on));
  }, fireImmediately: true);
  // #170：世界空间音效 / 提示音通道音量
  ref.listen<double>(worldSfxVolumeProvider, (_, v) {
    repo.setWorldSfxVolume(v);
    unawaited(ref.read(audioServiceProvider).setWorldSfxVolume(v));
  });
  ref.listen<double>(uiCueVolumeProvider, (_, v) {
    repo.setUiCueVolume(v);
    unawaited(ref.read(audioServiceProvider).setUiCueVolume(v));
  });
  ref.listen<PlayMode>(playModeProvider, (_, v) => repo.setPlayMode(v.name));
  ref.listen<String>(themeModeNameProvider, (_, v) => repo.setThemeMode(v));
  ref.listen<String>(themeSkinProvider, (_, v) => repo.setThemeSkin(v));
  ref.listen<bool>(eqEnabledProvider, (_, v) => repo.setEqEnabled(v));
  ref.listen<EqPreset>(eqPresetProvider, (_, v) => repo.setEqPresetId(v.id));
  ref.listen<List<double>>(eqCustomGainsProvider, (_, v) => repo.setEqGains(v));
  ref.listen<BalanceMode>(balanceModeProvider, (_, v) {
    repo.setBalanceMode(v.name);
    unawaited(ref.read(audioServiceProvider).setBalanceMode(v));
  });
  ref.listen<PerformanceMode>(performanceModeProvider, (_, v) {
    repo.setPerformanceMode(v.name);
  });
  ref.listen<FpsLimit>(fpsLimitProvider, (_, v) {
    repo.setFpsLimit('${v.value}');
    throttledFps = v.value; // 全局帧率节流即时生效
  });
  ref.listen<int>(viewDistanceChunksProvider, (_, v) {
    repo.setViewDistanceChunks(v);
  });
  // R26m：3D 画质档即时落盘
  ref.listen<GraphicsQuality>(graphicsQualityProvider, (_, q) {
    repo.setGraphicsQuality(q.index);
  });
  ref.listen<int>(lodStartChunksProvider, (_, v) {
    repo.setLodStartChunks(v);
  });
  ref.listen<int>(lodStepChunksProvider, (_, v) {
    repo.setLodStepChunks(v);
  });
  ref.listen<LodQuality>(lodQualityProvider, (_, v) {
    repo.setLodQuality(v);
  });
  ref.listen<bool>(lodFrustumCullProvider, (_, v) {
    repo.setLodFrustumCull(v);
  });
  ref.listen<EngineBackend>(engineBackendProvider, (_, v) {
    repo.setEngineBackend(v.name);
    // Windows 渲染后端重启生效：main.cpp 启动时读取（见 settings_repository 注释）
  });
  ref.listen<bool?>(noiseOverrideProvider, (_, v) => repo.setNoiseOverride(v));
  ref.listen<bool>(faceCullEnabledProvider, (_, v) => repo.setFaceCull(v));
  ref.listen<bool>(occlusionCullEnabledProvider, (_, v) => repo.setOcclusionCull(v));
  ref.listen<bool>(backFaceCullEnabledProvider, (_, v) => repo.setBackFaceCull(v));
  ref.listen<bool>(frustumCullEnabledProvider, (_, v) => repo.setFrustumCull(v));
  ref.listen<bool>(underwaterFilterEnabledProvider, (_, v) => repo.setUnderwaterFilter(v));
  ref.listen<bool>(waterFlowEnabledProvider, (_, v) => repo.setWaterFlow(v));
  ref.listen<bool>(flashlightEnabledProvider, (_, v) => repo.setFlashlight(v));
  ref.listen<bool>(lodEnabledProvider, (_, v) => repo.setLodEnabled(v));
  ref.listen<int>(lodStepBlocksProvider, (_, v) => repo.setLodStepBlocks(v));
  ref.listen<int>(lodSampleBaseProvider, (_, v) => repo.setLodSampleBase(v));
  ref.listen<int>(lodMaxChunksProvider, (_, v) => repo.setLodMaxChunks(v));
  ref.listen<bool>(shadowRenderProvider, (_, v) => repo.setShadowRender(v));
  ref.listen<bool>(aoEnabledProvider, (_, v) => repo.setAoEnabled(v));
  ref.listen<bool>(outlineEnabledProvider, (_, v) => repo.setOutlineEnabled(v));
  ref.listen<bool>(boundaryFogEnabledProvider, (_, v) => repo.setBoundaryFog(v));
  ref.listen<double>(
      renderPrecisionScaleProvider, (_, v) => repo.setRenderPrecisionScale(v));
  ref.listen<double>(renderPrecisionProvider, (_, v) => repo.setRenderPrecision(v));
  ref.listen<PicturePreset>(
      picturePresetProvider, (_, v) => repo.setPicturePreset(v.name));
  ref.listen<bool>(oobeDoneProvider, (_, v) {
    repo.setOobeDone(v);
    // F4：完成 OOBE 时记录当前构建号（升级检测：版本升级后弹询问是否重走）。
    if (v) repo.setOobeLastBuild(AppVersion.buildCount);
  });
  ref.listen<double?>(
      glassBlurOverrideProvider, (_, v) => repo.setGlassBlurOverride(v));
  ref.listen<bool?>(
      bgAnimationOverrideProvider, (_, v) => repo.setBgAnimationOverride(v));
  ref.listen<bool?>(
      liquidGlassOverrideProvider, (_, v) => repo.setLiquidGlassOverride(v));
  ref.listen<UiDensity>(uiDensityProvider, (_, v) => repo.setUiDensity(v.name));
  ref.listen<double>(uiScaleProvider, (_, v) => repo.setUiScale(v));
  ref.listen<MusicEngine>(musicEngineProvider, (_, v) {
    repo.setMusicEngine(v.name);
    // 引擎切换需重建 AudioService（provider 已 watch musicEngineProvider，
    // 状态变化自动重建并 dispose 旧服务）
  });
  ref.listen<bool>(logUploadEnabledProvider, (_, v) {
    repo.setLogUploadEnabled(v);
  });
  ref.listen<String>(logUploadEndpointProvider, (_, v) {
    repo.setLogUploadEndpoint(v);
  });
  ref.listen<bool>(logDebugEnabledProvider, (_, v) {
    LogService.debugEnabled = v;
    repo.setLogDebugEnabled(v);
  });
  ref.listen<String>(llmBaseUrlProvider, (_, v) => repo.setLlmBaseUrl(v));
  ref.listen<String>(llmModelProvider, (_, v) => repo.setLlmModel(v));
  // OOBE 选择/询问（cl75）：运行期写回。
  ref.listen<int>(audioQualityProvider, (_, v) => repo.setAudioQuality(v));
  ref.listen<bool>(
      analyticsConsentProvider, (_, v) => repo.setAnalyticsConsent(v));
  ref.listen<Set<String>>(listenSourcesProvider, (_, v) {
    repo.setListenSources(v.isEmpty ? '' : v.join(','));
  });
  ref.listen<int>(currentSceneIndexProvider, (_, idx) {
    final List<Scene> scenes = ref.read(sceneOrderProvider);
    if (idx >= 0 && idx < scenes.length) {
      repo.setCurrentSceneId(scenes[idx].id);
    }
  });
  ref.listen<Track?>(nowPlayingProvider, (_, t) {
    if (t == null) return;
    repo.setLastTrack(
      uri: t.uri,
      title: t.title,
      artist: t.artist,
    );
  });
});

/// 旧三档性能值迁移到 R21 两档：
/// power_save → performance；balanced / smooth → quality。
PerformanceMode _mapLegacyPerformance(String raw) {
  return switch (raw) {
    'performance' => PerformanceMode.performance,
    'power_save' => PerformanceMode.performance,
    'quality' || 'balanced' || 'smooth' => PerformanceMode.quality,
    _ => PerformanceMode.quality,
  };
}
