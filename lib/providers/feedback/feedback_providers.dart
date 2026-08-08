import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_providers.dart';

/// 有温度的模糊 · 一次切换的反馈参数
///
/// 每次切换场景，反馈强度不同：
///  - 弹力（bounce）时大时小
///  - 星点数量 / 速度 / 方向每次都不一样
/// 这种"不精确"不是 bug，是让空间感觉"它是活的"。
class SwitchPulse {
  /// 本次切换浮现的星点数量
  final int particleCount;

  /// 星点漂移速度系数（慢，几乎不被注意）
  final double particleSpeed;

  /// 星点方向散开幅度（弧度）
  final double particleSpread;

  /// 弹力反馈强度（0.55 ~ 1.0，越大切换越"弹"）
  final double bounce;

  const SwitchPulse({
    required this.particleCount,
    required this.particleSpeed,
    required this.particleSpread,
    required this.bounce,
  });
}

/// 当前场景索引的切换脉冲（由会话种子 + 场景索引派生）
final switchPulseProvider = Provider.family<SwitchPulse, int>((ref, index) {
  final int seed = ref.watch(sessionSeedProvider);
  // 混合场景索引，让相邻场景的脉冲也不同
  final Random rng = Random(seed ^ (index * 2654435761));

  return SwitchPulse(
    // 10 ~ 23 颗
    particleCount: 10 + rng.nextInt(14),
    // 0.25 ~ 0.65 速度系数
    particleSpeed: 0.25 + rng.nextDouble() * 0.4,
    // 0 ~ 0.6 弧度散开
    particleSpread: rng.nextDouble() * 0.6,
    // 0.55 ~ 1.0 弹力
    bounce: 0.55 + rng.nextDouble() * 0.45,
  );
});
