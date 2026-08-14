import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../services/audio/audio_service.dart';
import '../../services/audio/eq_engine.dart';
import '../../services/audio/media_kit_backend.dart';
import '../audio/audio_providers.dart';

/// 当前 EQ 引擎：
/// - Android：真 EQ（`AndroidEqualizer`）；
/// - Windows + media_kit：mpv `af=equalizer` 滤镜真 DSP（I 批）；
/// - 其余：模拟层（仅状态 + UI）。
final Provider<EqEngine> eqEngineProvider = Provider<EqEngine>((Ref ref) {
  final AndroidEqualizer? eq = ref.watch(androidEqualizerProvider);
  if (eq != null) return AndroidEqEngine(eq);
  if (Platform.isWindows) {
    final AudioService svc = ref.watch(audioServiceProvider);
    final dynamic backend = svc.backend;
    if (backend is MediaKitBackend) return BackendEqEngine(backend);
  }
  return SimulatedEqEngine();
});

/// 当前 EQ 预设（默认平坦；持久化到 prefs）。
final StateProvider<EqPreset> eqPresetProvider =
    StateProvider<EqPreset>((Ref ref) => kEqPresets.first);

/// EQ 是否启用（总开关，默认关）。
final StateProvider<bool> eqEnabledProvider =
    StateProvider<bool>((Ref ref) => false);

/// 自定义增益（10 段，用户手动拖动后保存）。
final StateProvider<List<double>> eqCustomGainsProvider =
    StateProvider<List<double>>(
  (Ref ref) => List<double>.filled(kEqFrequencies.length, 0),
);

/// 播放开始时补应用 EQ（R-04：Android 需要播放中才能访问音频会话）。
///
/// 监听 `isPlayingProvider`：当变为播放中且 EQ 启用时，把当前预设
/// 应用到真实引擎（模拟层忽略，仅维护状态）。
final Provider<void> eqReapplyOnPlayProvider = Provider<void>((Ref ref) {
  ref.listen<bool>(
    isPlayingProvider.select((AsyncValue<bool> v) => v.valueOrNull ?? false),
    (bool? prev, bool next) {
      if (!next) return;
      if (!ref.read(eqEnabledProvider)) return;
      final EqPreset preset = ref.read(eqPresetProvider);
      final EqEngine engine = ref.read(eqEngineProvider);
      if (engine.supported) {
        engine.apply(preset);
      }
    },
  );
  return;
});

/// 便捷：应用一组预设（供 EQ 实验页调用）。
///
/// - 真实引擎（Android）：`engine.apply(preset)`；
/// - 模拟层：`engine.applySimulation(preset)` + 可选音乐增益微调
///   （把 `preset` 均值映射为整体音量微调，不做 DSP）。
Future<void> applyEqPreset(WidgetRef ref, EqPreset preset) async {
  ref.read(eqPresetProvider.notifier).state = preset;
  final EqEngine engine = ref.read(eqEngineProvider);
  if (engine.supported) {
    await engine.apply(preset);
  } else {
    engine.applySimulation(preset);
    // 可选整体增益微调：十档均值偏移 → 音量微调（轻量、非 DSP）
    final double avg = preset.gains.isEmpty
        ? 0
        : preset.gains.reduce((a, b) => a + b) / preset.gains.length;
    final double base = ref.read(musicVolumeProvider);
    final double target = (base + avg * 0.01).clamp(0.0, 1.0);
    ref.read(musicVolumeProvider.notifier).state = target;
    await ref.read(audioServiceProvider).setMusicVolume(target);
  }
}
