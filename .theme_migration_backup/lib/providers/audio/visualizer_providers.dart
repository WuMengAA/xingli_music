import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/audio/audio_service.dart';
import '../../services/audio/visualizer_service.dart';
import 'audio_providers.dart';

/// Module 3：音乐反应层 Provider
///
/// 单一 [VisualizerService] 实例驱动 [level] / [bands] 两个流，
/// 仅在画布页（及其粒子）被观察时启动，离开时自动释放。
final visualizerServiceProvider = Provider<VisualizerService>((ref) {
  final AudioService audio = ref.watch(audioServiceProvider);
  final vs = VisualizerService(audio);
  vs.start();
  ref.onDispose(vs.dispose);
  return vs;
});

/// 整体能量包络（0~1）：驱动粒子亮度 / 呼吸
final visualizerLevelProvider = StreamProvider<double>((ref) =>
    ref.watch(visualizerServiceProvider).level);

/// 多频段能量（length == resolution）
final visualizerBandsProvider = StreamProvider<List<double>>((ref) =>
    ref.watch(visualizerServiceProvider).bands);
