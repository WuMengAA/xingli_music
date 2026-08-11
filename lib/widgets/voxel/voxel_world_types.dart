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

  /// 树叶（不透明，fast 模式：实心 + 遮挡相邻面 + 走常规 6 面 + 背面剔除）。
  leaves,

  /// 雪（山顶）。
  snow,

  // ── R23k 新增：建筑 / 功能 / 物品 / 食物（自绘材质）──

  /// 木板（浅棕 + 木纹条）。
  planks,

  /// 红砖（砖缝图案）。
  brick,

  /// 圆石（灰点图案）。
  cobble,

  /// 玻璃（半透明 + 高光）。
  glass,

  /// 半砖（石色，顶面分割线）。
  slab,

  /// 楼梯（石阶纹）。
  stairs,

  /// 栅栏（木色竖条）。
  fence,

  /// 熔炉（灰底 + 炉口）。
  furnace,

  /// 篝火（木堆 + 橙色火光）。
  campfire,

  /// 火把（发光）。
  torch,

  /// 箱子（棕色 + 箱扣）。
  chest,

  /// 苹果（红 + 高光）。
  apple,

  /// 面包（麦色）。
  bread,

  /// 金锭（金色反光）。
  gold,

  /// 钻石（青钻反光）。
  diamond,
}

/// 自绘材质图案（R23k：在纯色填充之上叠加的程序化纹理）。
enum VoxelPattern {
  /// 无图案（纯色 + 分面亮度）。
  none,

  /// 木板横条纹。
  planks,

  /// 砖缝（横线 + 交错竖线）。
  brick,

  /// 圆石点。
  cobble,

  /// 玻璃斜向高光。
  glassShine,

  /// 半砖顶面中线分割。
  slabSplit,

  /// 楼梯台阶纹。
  stairsSteps,

  /// 栅栏竖条。
  fenceBars,

  /// 熔炉炉口（顶口深色 + 侧面炉膛）。
  furnaceFace,

  /// 篝火橙光（顶面火光 + 侧面火星）。
  campfireGlow,

  /// 火把亮斑（侧面发光）。
  torchGlow,

  /// 箱子扣（正面横条 + 提手）。
  chestFace,

  /// 苹果高光点。
  appleShine,

  /// 金锭斜向反光。
  goldShine,

  /// 钻石多棱反光。
  diamondShine,

  /// 沙子细点。
  sandDots,
}

/// 方块渲染规格。
class VoxelSpec {
  const VoxelSpec({
    required this.id,
    required this.base,
    this.top,
    this.transparent = false,
    this.solid = true,
    this.pattern = VoxelPattern.none,
  });

  final Voxel id;

  /// 主体色（侧面 / 顶面默认）。
  final Color base;

  /// 顶面色（草 / 雪用，比 base 更亮）。
  final Color? top;

  /// 半透明（水 / 玻璃）：内部相邻同型面剔除，但与空气相邻的面仍绘制。
  final bool transparent;

  /// 是否实心（空气 = false）。
  final bool solid;

  /// 自绘材质图案（R23k，painter 层叠加）。
  final VoxelPattern pattern;

  bool get isAir => id == Voxel.air;
}

/// 方块规格表。
///
/// 颜色一律写满 8 位（含 alpha）：6 位写法的 alpha 会被当成 0x00（全透明），
/// 半透明由 [VoxelSpec.transparent] + 渲染层的 alpha 参数控制，不靠基色带透明度。
const Map<Voxel, VoxelSpec> kVoxelSpecs = <Voxel, VoxelSpec>{
  Voxel.air: VoxelSpec(id: Voxel.air, base: Color(0x00000000), solid: false),
  Voxel.grass: VoxelSpec(
    id: Voxel.grass,
    base: Color(0xFF6E8B3D),
    top: Color(0xFF7CC85A),
  ),
  Voxel.dirt: VoxelSpec(id: Voxel.dirt, base: Color(0xFF8A6240)),
  Voxel.stone: VoxelSpec(id: Voxel.stone, base: Color(0xFF8C8C92)),
  Voxel.sand: VoxelSpec(
    id: Voxel.sand,
    base: Color(0xFFE2D2A0),
    pattern: VoxelPattern.sandDots,
  ),
  Voxel.water: VoxelSpec(
    id: Voxel.water,
    base: Color(0xFF3A78C2),
    transparent: true,
  ),
  Voxel.wood: VoxelSpec(id: Voxel.wood, base: Color(0xFF6E4B2A)),
  Voxel.leaves: VoxelSpec(
    id: Voxel.leaves,
    base: Color(0xFF4F9A3A),
  ),
  Voxel.snow: VoxelSpec(
    id: Voxel.snow,
    base: Color(0xFFF2F6FB),
    top: Color(0xFFFFFFFC),
  ),
  // ── R23k 新增（自绘材质）──────────────────────────
  Voxel.planks: VoxelSpec(
    id: Voxel.planks,
    base: Color(0xFFB08954),
    pattern: VoxelPattern.planks,
  ),
  Voxel.brick: VoxelSpec(
    id: Voxel.brick,
    base: Color(0xFF9C4F4A),
    pattern: VoxelPattern.brick,
  ),
  Voxel.cobble: VoxelSpec(
    id: Voxel.cobble,
    base: Color(0xFF7A7E85),
    pattern: VoxelPattern.cobble,
  ),
  Voxel.glass: VoxelSpec(
    id: Voxel.glass,
    base: Color(0xFF9EDBE8),
    transparent: true,
    pattern: VoxelPattern.glassShine,
  ),
  Voxel.slab: VoxelSpec(
    id: Voxel.slab,
    base: Color(0xFF8A8A8E),
    pattern: VoxelPattern.slabSplit,
  ),
  Voxel.stairs: VoxelSpec(
    id: Voxel.stairs,
    base: Color(0xFF8A8A8E),
    pattern: VoxelPattern.stairsSteps,
  ),
  Voxel.fence: VoxelSpec(
    id: Voxel.fence,
    base: Color(0xFF7A5230),
    pattern: VoxelPattern.fenceBars,
  ),
  Voxel.furnace: VoxelSpec(
    id: Voxel.furnace,
    base: Color(0xFF6A6E75),
    pattern: VoxelPattern.furnaceFace,
  ),
  Voxel.campfire: VoxelSpec(
    id: Voxel.campfire,
    base: Color(0xFF5C4027),
    pattern: VoxelPattern.campfireGlow,
  ),
  Voxel.torch: VoxelSpec(
    id: Voxel.torch,
    base: Color(0xFF8A6A3F),
    pattern: VoxelPattern.torchGlow,
  ),
  Voxel.chest: VoxelSpec(
    id: Voxel.chest,
    base: Color(0xFF9C6B2E),
    pattern: VoxelPattern.chestFace,
  ),
  Voxel.apple: VoxelSpec(
    id: Voxel.apple,
    base: Color(0xFFD63A3A),
    pattern: VoxelPattern.appleShine,
  ),
  Voxel.bread: VoxelSpec(
    id: Voxel.bread,
    base: Color(0xFFE0B46A),
  ),
  Voxel.gold: VoxelSpec(
    id: Voxel.gold,
    base: Color(0xFFF2C94C),
    pattern: VoxelPattern.goldShine,
  ),
  Voxel.diamond: VoxelSpec(
    id: Voxel.diamond,
    base: Color(0xFF5EE6D8),
    pattern: VoxelPattern.diamondShine,
  ),
};

/// 规格派生判定。
extension VoxelSpecX on VoxelSpec {
  /// **遮挡**：实心且不透明，才会挡住相邻面 / 阻挡相机。
  ///
  /// ⚠️ 不要用 [solid] 代替：水的 `solid == true`（只有空气 false），
  /// 用 solid 做面剔除会把水下地形面误删（水里露空洞），
  /// 用 solid 做碰撞则水面变成墙。
  bool get occludes => solid && !transparent;
}

/// 方块派生判定（渲染 / 碰撞公用）。
extension VoxelX on Voxel {
  VoxelSpec get spec => kVoxelSpecs[this]!;

  /// 是否遮挡相邻面（见 [VoxelSpecX.occludes]）。
  bool get occludes => spec.occludes;

  /// 是否半透明（水 / 叶）。
  bool get isTransparent => spec.transparent;

  bool get isEmpty => this == Voxel.air;
}

/// ════════════════════════════════════════════════════════════════════════
/// 生物群系（R23u：GDD §2.3 四项群系 + 垂直世界 maxY 256）
/// ════════════════════════════════════════════════════════════════════════

/// 生物群系类型（GDD §2.3）。
enum Biome {
  /// 平原：草地表、少量树、平坦开阔。
  plains,

  /// 森林：草地表、大量树、起伏较小。
  forest,

  /// 沙漠：沙地表、无树、平坦有沙丘。
  desert,

  /// 山地：石头/雪顶、少量松树、高度落差大。
  mountain,
}

/// 生物群系规格（地形/植被参数）。
class BiomeSpec {
  const BiomeSpec({
    required this.surface,
    required this.subsurface,
    required this.treeDensity,
    required this.minTrunk,
    required this.maxTrunk,
    required this.baseHeight,
    required this.amplitude,
    this.snowy = false,
    this.snowLine = 0.5,
  });

  /// 地表方块。
  final Voxel surface;

  /// 地表下方 2 格的填充方块。
  final Voxel subsurface;

  /// 树的生成概率（0~1，每列独立抽签）。
  final double treeDensity;

  /// 树干高度下限（含）。
  final int minTrunk;

  /// 树干高度上限（含）。
  final int maxTrunk;

  /// 地形基准高度（fbm 异常为 0 时的高度）。
  final double baseHeight;

  /// 地形起伏振幅（fbm 异常 ±1 对应 ±amplitude）。
  final double amplitude;

  /// 是否为雪原群系（高于 [snowLine] 比例处地表转雪）。
  final bool snowy;

  /// 雪线（相对 [amplitude] 的比例：实际高度 > baseHeight + amplitude*snowLine 时落雪）。
  final double snowLine;
}

/// 生物群系规格表（GDD §2.3 参数）。
///
/// 基准高度整体抬到水面之上（[VoxelWorld.waterLevel]=30），低洼处自然成水。
const Map<Biome, BiomeSpec> kBiomes = <Biome, BiomeSpec>{
  Biome.plains: BiomeSpec(
    surface: Voxel.grass,
    subsurface: Voxel.dirt,
    treeDensity: 0.02,
    minTrunk: 3,
    maxTrunk: 4,
    baseHeight: 44,
    amplitude: 5,
  ),
  Biome.forest: BiomeSpec(
    surface: Voxel.grass,
    subsurface: Voxel.dirt,
    treeDensity: 0.12,
    minTrunk: 4,
    maxTrunk: 6,
    baseHeight: 48,
    amplitude: 10,
  ),
  Biome.desert: BiomeSpec(
    surface: Voxel.sand,
    subsurface: Voxel.sand,
    treeDensity: 0.0,
    minTrunk: 0,
    maxTrunk: 0,
    baseHeight: 42,
    amplitude: 8,
  ),
  Biome.mountain: BiomeSpec(
    surface: Voxel.stone,
    subsurface: Voxel.stone,
    treeDensity: 0.04,
    minTrunk: 3,
    maxTrunk: 5,
    baseHeight: 72,
    amplitude: 60,
    snowy: true,
    snowLine: 0.35,
  ),
};

/// 按分面基础亮度（受光方向）缩放后的颜色。
Color shade(Color base, double brightness, {double alpha = 1}) {
  final int r = (base.r * 255.0 * brightness).round().clamp(0, 255);
  final int g = (base.g * 255.0 * brightness).round().clamp(0, 255);
  final int b = (base.b * 255.0 * brightness).round().clamp(0, 255);
  return Color.fromARGB(
    (alpha * 255).round().clamp(0, 255),
    r,
    g,
    b,
  );
}
