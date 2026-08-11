import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scene.dart';
import '../../services/scene_order_service.dart';
import '../scene/scene_providers.dart';

/// 会话种子：每次打开应用时生成一次。
///
/// 它是整个"有秩序的随机感"的根——
/// 场景顺序、配色偏移、粒子参数都由它派生，
/// 保证「每次打开都不同，但同一会话内稳定」。
final sessionSeedProvider = Provider<int>(
  (ref) => DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
);

/// 本会话的场景顺序（每次打开不同，且满足情绪距离约束）
final sceneOrderProvider = Provider<List<Scene>>((ref) {
  final int seed = ref.watch(sessionSeedProvider);
  final List<Scene> universe = ref.watch(scenesProvider);
  return SceneOrderService.generate(universe, seed);
});
