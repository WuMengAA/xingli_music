import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voxel_survival.dart';

/// cl38 P1（开放世界）：玩家生存状态单一真相源。
///
/// 原为 `VoxelWorldView3D` State 内 `final _vitals = PlayerVitals()` 直接 new，
/// 现由 Riverpod `Provider` 管理生命周期、跨组件共享同一 `PlayerVitals` 实例，
/// 供开放世界多系统（天气 / NPC / 任务 / 载具）统一读取玩家生命/饥饿/经验，
/// 不再各自持有副本。
///
/// 背包 `_inv` 与玩家位置 `_playerPos` 因与渲染 / 交互深度耦合，暂留 View
/// （后续 P1.2 再抽离为 PlayerController 的组成部分）。
final playerVitalsProvider = Provider<PlayerVitals>((ref) {
  final PlayerVitals v = PlayerVitals();
  ref.onDispose(v.dispose);
  return v;
});
