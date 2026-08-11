/// ════════════════════════════════════════════════════════════════════════
/// 体素方块类型与规格（类我的世界 · 3D 世界）
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:ui';

/// 方块类型。
enum Voxel {
  /// 空气（空）。
  air,

  /// 草方块（顶面草绿、侧面泥土 + 顶部草带）。
  grass,

  /// 泥土。
  dirt,

  /// 石头。
  stone,

  /// 沙子（近水/岸边）。
  sand,

  /// 水（半透明，不遮挡相邻面）。
  water,

  /// 树干（原木）。
  wood,

  /// 树叶（半透明）。
  leaves,

  /// 雪（山顶）。
  snow,
}

/// 方块渲染规格。
class VoxelSpec {
  const VoxelSpec({
    required this.id,
    required this.base,
    this.top,
    this.transparent = false,
    this.solid = true,
  });

  final Voxel id;

  /// 主体色（侧面 / 顶面默认）。
  final Color base;

  /// 顶面色（草 / 雪用，比 base 更亮）。
  final Color? top;

  /// 半透明（水 / 叶）：内部相邻同型面剔除，但与空气相邻的面仍绘制。
  final bool transparent;

  /// 是否实心（空气 = false）。
  final bool solid;

  bool get isAir => id == Voxel.air;
}

/// 方块规格表。
const Map<Voxel, VoxelSpec> kVoxelSpecs = <Voxel, VoxelSpec>{
  Voxel.air: VoxelSpec(id: Voxel.air, base: Color(0x00000000), solid: false),
  Voxel.grass: VoxelSpec(
    id: Voxel.grass,
    base: Color(0x6E8B3D),
    top: Color(0x7CC85A),
  ),
  Voxel.dirt: VoxelSpec(id: Voxel.dirt, base: Color(0x8A6240)),
  Voxel.stone: VoxelSpec(id: Voxel.stone, base: Color(0x8C8C92)),
  Voxel.sand: VoxelSpec(id: Voxel.sand, base: Color(0xE2D2A0)),
  Voxel.water: VoxelSpec(
    id: Voxel.water,
    base: Color(0x3A78C2),
    transparent: true,
  ),
  Voxel.wood: VoxelSpec(id: Voxel.wood, base: Color(0x6E4B2A)),
  Voxel.leaves: VoxelSpec(
    id: Voxel.leaves,
    base: Color(0x4F9A3A),
    transparent: true,
  ),
  Voxel.snow: VoxelSpec(
    id: Voxel.snow,
    base: Color(0xF2F6FB),
    top: Color(0xFFFFFFFC),
  ),
};

/// 按分面基础亮度（受光方向）缩放后的颜色。
Color shade(Color base, double brightness, {double alpha = 1}) {
  final int r = (base.red * brightness).round().clamp(0, 255);
  final int g = (base.green * brightness).round().clamp(0, 255);
  final int b = (base.blue * brightness).round().clamp(0, 255);
  return Color.fromARGB(
    (alpha * 255).round().clamp(0, 255),
    r,
    g,
    b,
  );
}
