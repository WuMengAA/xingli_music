import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio/visualizer_providers.dart';
import 'scene_particles.dart';

/// 音乐反应粒子：独立订阅 [visualizerLevelProvider]，
/// 仅自身随音乐能量重建，避免拖累整个画布页的高频重建。
class ReactiveParticles extends ConsumerWidget {
  const ReactiveParticles({
    super.key,
    required this.color,
    this.motion = ParticleMotion.floatUp,
    this.seed = 1,
  });
  final Color color;
  final ParticleMotion motion;
  final int seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double? level = ref.watch(visualizerLevelProvider).valueOrNull;
    return SceneParticles(
      color: color,
      motion: motion,
      seed: seed,
      level: level,
    );
  }
}
