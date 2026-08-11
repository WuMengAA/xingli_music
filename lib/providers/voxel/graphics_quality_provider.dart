/// R26c：3D 画质档共享 Provider。
///
/// 「游戏中快捷设置」（VoxelWorld3DPage 弹层）与 3D 视图（VoxelWorldView3D）
/// 分处两层，画质档此前是视图私有 state，弹层无法改。提升为 Provider 后
/// 视图 `ref.listen` 同步 `_config`，弹层直接写，天然联动（同首页设置风格）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/voxel/voxel_world_view3d.dart';

/// 当前 3D 画质档（流畅 / 标准 / 高清）。
final graphicsQualityProvider = StateProvider<GraphicsQuality>(
  (ref) => GraphicsQuality.standard,
);
