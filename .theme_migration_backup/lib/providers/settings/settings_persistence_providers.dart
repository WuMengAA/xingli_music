import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scene.dart';
import '../../models/track.dart';
import '../../repositories/settings_repository.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/eq_engine.dart';
import '../audio/audio_providers.dart';
import '../audio/equalizer_providers.dart';
import '../scene/scene_providers.dart';
import '../session/session_providers.dart';
import '../storage/storage_providers.dart';
import '../theme/theme_providers.dart';
import 'performance_providers.dart';

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
  ref.read(soundscapeVolumeProvider.notifier).state = repo.soundscapeVolume;
  ref.read(musicMutedProvider.notifier).state = repo.musicMuted;
  ref.read(soundscapeMutedProvider.notifier).state = repo.soundscapeMuted;

  // 白噪音
  ref.read(whiteNoiseEnabledProvider.notifier).state = repo.whiteNoiseEnabled;
  ref.read(whiteNoiseVolumeProvider.notifier).state = repo.whiteNoiseVolume;

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

  // 性能模式（低端设备优化）
  final String perf = repo.performanceMode;
  ref.read(performanceModeProvider.notifier).state =
      PerformanceMode.values.firstWhere(
    (PerformanceMode m) => m.name == perf,
    orElse: () => PerformanceMode.balanced,
  );

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
  await audio.setMusicVolume(repo.musicVolume);
  await audio.setSoundscapeVolume(repo.soundscapeVolume);
  await audio.setMusicMuted(repo.musicMuted);
  await audio.setSoundscapeMuted(repo.soundscapeMuted);
  await audio.setBalanceMode(
      repo.balanceMode == 'hifi' ? BalanceMode.hifi : BalanceMode.normal);
  // 白噪音音量已映射到音景音量（setSoundscapeVolume 已恢复），
  // 这里只恢复白噪音开关（白噪音 = 当前场景音景）。
  if (repo.whiteNoiseEnabled) {
    await audio.setWhiteNoise(true);
  }
}

/// 运行期同步写回（R11）：监听关键 StateProvider 变化，即时落盘。
///
/// 由 AppShell.build 顶层 `ref.watch(settingsSyncProvider)` 保持存活。
final settingsSyncProvider = Provider<void>((ref) {
  final SettingsRepository repo = ref.watch(settingsRepositoryProvider);

  ref.listen<double>(musicVolumeProvider, (_, v) => repo.setMusicVolume(v));
  ref.listen<double>(soundscapeVolumeProvider, (_, v) => repo.setSoundscapeVolume(v));
  ref.listen<bool>(musicMutedProvider, (_, v) => repo.setMusicMuted(v));
  ref.listen<bool>(soundscapeMutedProvider, (_, v) => repo.setSoundscapeMuted(v));
  ref.listen<bool>(whiteNoiseEnabledProvider, (_, v) {
    repo.setWhiteNoiseEnabled(v);
    unawaited(ref.read(audioServiceProvider).setWhiteNoise(v));
  });
  ref.listen<double>(whiteNoiseVolumeProvider, (_, v) {
    repo.setWhiteNoiseVolume(v);
    // 白噪音音量 = 场景音景音量（R4 语义修正），同步到音景
    unawaited(ref.read(audioServiceProvider).setSoundscapeVolume(v));
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
