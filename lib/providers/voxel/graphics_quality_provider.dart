/// R26c：3D 画质档共享 Provider。
///
/// 「游戏中快捷设置」（VoxelWorld3DPage 弹层）与 3D 视图（VoxelWorldView3D）
/// 分处两层，画质档此前是视图私有 state，弹层无法改。提升为 Provider 后
/// 视图 `ref.listen` 同步 `_config`，弹层直接写，天然联动（同首页设置风格）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/voxel/voxel_world_view3d.dart';

/// 当前 3D 画质档（cl76：省电 / 流畅 / 地平线 / 自动，默认「自动」——运行时
/// 按 FPS 自动降档，10 秒窗口 ≥30fps 不降、不足逐档下调主视距区块）。
final graphicsQualityProvider = StateProvider<GraphicsQuality>(
  (ref) => GraphicsQuality.auto,
);
