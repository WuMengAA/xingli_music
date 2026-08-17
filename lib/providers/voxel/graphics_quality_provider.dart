/// R26c：3D 画质档共享 Provider。
///
/// 「游戏中快捷设置」（VoxelWorld3DPage 弹层）与 3D 视图（VoxelWorldView3D）
/// 分处两层，画质档此前是视图私有 state，弹层无法改。提升为 Provider 后
/// 视图 `ref.listen` 同步 `_config`，弹层直接写，天然联动（同首页设置风格）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings/performance_providers.dart';
import '../../providers/voxel/cloud_view_distance_provider.dart';
import '../../widgets/voxel/voxel_world_view3d.dart';

/// 当前 3D 画质档（cl76：省电 / 流畅 / 地平线 / 自动，默认「自动」——运行时
/// 按 FPS 自动降档，10 秒窗口 ≥30fps 不降、不足逐档下调主视距区块）。
final graphicsQualityProvider = StateProvider<GraphicsQuality>(
  (ref) => GraphicsQuality.auto,
);

/// R26p2：把 [GraphicsQuality] 的基准参数同步到所有画面相关 Provider。
///
/// 用于「画质档」选择后让高级设置立刻对号入座；用户仍可在高级页手动微调。
void applyGraphicsQuality(WidgetRef ref, GraphicsQuality q) {
  ref.read(graphicsQualityProvider.notifier).state = q;
  ref.read(viewDistanceChunksProvider.notifier).state = q.viewDistanceChunks;
  ref.read(cloudViewDistanceProvider.notifier).state =
      q.cloudViewDistanceChunks;
  ref.read(lodStartChunksProvider.notifier).state = q.lodStartChunks;
  ref.read(lodStepChunksProvider.notifier).state = q.lodStepChunks;
  ref.read(lodMaxChunksProvider.notifier).state = q.lodMaxChunks;
  ref.read(lodStepBlocksProvider.notifier).state = 16;
  ref.read(lodSampleBaseProvider.notifier).state = 4;
  ref.read(lodEnabledProvider.notifier).state = true;
  ref.read(fpsLimitProvider.notifier).state =
      q.fpsCap <= 24 ? FpsLimit.fps24 : FpsLimit.fps60;
}
