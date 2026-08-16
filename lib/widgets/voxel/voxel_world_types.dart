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

  // ── R29 新增食物（可右键 / 使用进食，进食有音效）──
  /// 生牛肉。
  beef,
  /// 熟牛肉。
  cookedBeef,
  /// 生猪排。
  porkchop,
  /// 熟猪排。
  cookedPorkchop,
  /// 胡萝卜。
  carrot,
  /// 土豆。
  potato,
  /// 烤土豆。
  bakedPotato,
  /// 生鸡肉。
  chicken,
  /// 熟鸡肉。
  cookedChicken,
  /// 西瓜片。
  melonSlice,
  /// 曲奇。
  cookie,
  /// 生鱼。
  fish,
  /// 熟鱼。
  cookedFish,

  /// 金锭（金色反光）。
  gold,

  /// 钻石（青钻反光）。
  diamond,

  /// 铁矿石（棕褐 + 铁色斑，R26e 矿脉生成用）。
  ironOre,

  /// 煤矿石（深灰 + 黑斑，R26e 矿脉生成用）。
  coalOre,

  /// 红石矿石（深石 + 红点，大跃进新增）。
  redstoneOre,

  /// 青金石矿石（深石 + 蓝点，大跃进新增）。
  lapisOre,

  /// 绿宝石矿石（深石 + 绿点，大跃进新增）。
  emeraldOre,

  /// 钻石矿石（深石 + 青钻点，大跃进新增）。
  diamondOre,

  /// 红石（粉红结晶，矿石掉落物）。
  redstone,

  /// 青金石（靛蓝结晶，矿石掉落物）。
  lapis,

  /// 绿宝石（翠绿结晶，矿石掉落物）。
  emerald,
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
    required this.displayName,
    this.top,
    this.transparent = false,
    this.solid = true,
    this.pattern = VoxelPattern.none,
    this.variantCount = 1,
  });

  final Voxel id;

  /// 主体色（侧面 / 顶面默认）。
  final Color base;

  /// 物品 / 方块中文显示名（HUD / 背包 / 准星 / 提示统一来源——单一事实源）。
  ///
  /// R29：原为 `itemNameOf` 里一份独立 `switch`，新增方块极易漏改（用户
  /// 「写死 4 次」的根因）。改为随规格定义，新增 [Voxel] 时构造 [VoxelSpec]
  /// 强制填名，命名与渲染一处维护，杜绝漏改。
  final String displayName;

  /// 顶面色（草 / 雪用，比 base 更亮）。
  final Color? top;

  /// 半透明（水 / 玻璃）：内部相邻同型面剔除，但与空气相邻的面仍绘制。
  final bool transparent;

  /// 是否实心（空气 = false）。
  final bool solid;

  /// 自绘材质图案（R23k，painter 层叠加）。
  final VoxelPattern pattern;

  /// 纹理变体数（数据驱动：同一种方块在不同位置显示不同纹理，增加丰富度）。
  /// 实际采样时 clamp 到 [1, kVoxelVariantSlots]；1 = 无变体（向后兼容）。
  final int variantCount;

  bool get isAir => id == Voxel.air;
}

/// 方块规格表。
///
/// 颜色一律写满 8 位（含 alpha）：6 位写法的 alpha 会被当成 0x00（全透明），
/// 半透明由 [VoxelSpec.transparent] + 渲染层的 alpha 参数控制，不靠基色带透明度。
/// ════════════════════════════════════════════════════════════════════════
/// 纹理变体（数据驱动 · 生存模式大跃进）
/// ════════════════════════════════════════════════════════════════════════

/// 每个方块在图集预留的纹理变体槽位数（变体上限）。
///
/// 图集为每种方块预留 [kVoxelVariantSlots] 个连续瓦片；实际使用的变体数由
/// [VoxelSpec.variantCount] 决定（<= 此值）。变体 0 恒为「基准纹理」，向后兼容。
const int kVoxelVariantSlots = 4;

/// 方块实际纹理变体数（clamp 到 [1, kVoxelVariantSlots]）。
int variantCountOf(Voxel v) =>
    kVoxelSpecs[v]!.variantCount.clamp(1, kVoxelVariantSlots);

/// 确定性纹理变体选择：同世界坐标恒同（不闪烁、随 seed 复现）。
///
/// 用于「纹理变体」——让同一种方块在不同位置显示不同纹理，增加世界丰富度。
/// 选择由世界坐标散列决定（与地形/存档同一套确定性风格），变体数由
/// [VoxelSpec.variantCount] 控制；[variantCount]<=1 时恒返回 0。
int blockVariant(int x, int y, int z, Voxel v) {
  final int vc = variantCountOf(v);
  if (vc <= 1) return 0;
  int n = (x * 374761393) ^
      (y * 668265263) ^
      (z * 982451653) ^
      (v.index * 1274126177);
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return (n & 0x7fffffff) % vc;
}

const Map<Voxel, VoxelSpec> kVoxelSpecs = <Voxel, VoxelSpec>{
  Voxel.air: VoxelSpec(
    id: Voxel.air,
    base: Color(0x00000000),
    solid: false,
    displayName: '空',
  ),
  Voxel.grass: VoxelSpec(
    id: Voxel.grass,
    base: Color(0xFF6E8B3D),
    top: Color(0xFF7CC85A),
    displayName: '草方块',
    variantCount: 2,
  ),
  Voxel.dirt: VoxelSpec(
    id: Voxel.dirt,
    base: Color(0xFF8A6240),
    displayName: '泥土',
    variantCount: 3,
  ),
  Voxel.stone: VoxelSpec(
    id: Voxel.stone,
    base: Color(0xFF8C8C92),
    displayName: '石头',
    variantCount: 4,
  ),
  Voxel.sand: VoxelSpec(
    id: Voxel.sand,
    base: Color(0xFFE2D2A0),
    pattern: VoxelPattern.sandDots,
    displayName: '沙子',
    variantCount: 3,
  ),
  Voxel.water: VoxelSpec(
    id: Voxel.water,
    base: Color(0xFF3A78C2),
    transparent: true,
    displayName: '水',
  ),
  Voxel.wood: VoxelSpec(
    id: Voxel.wood,
    base: Color(0xFF6E4B2A),
    displayName: '原木',
    variantCount: 2,
  ),
  Voxel.leaves: VoxelSpec(
    id: Voxel.leaves,
    base: Color(0xFF4F9A3A),
    // R26r6：树叶 = 实体方块（不透明、遮挡、可站立/可破坏），不再半透明。
    // 「走平地被顶到树冠」已由 groundHeightAt 加 startY（从脚底往下扫）根治，
    // 不再需要靠透明来绕。
    displayName: '树叶',
    variantCount: 3,
  ),
  Voxel.snow: VoxelSpec(
    id: Voxel.snow,
    base: Color(0xFFF2F6FB),
    top: Color(0xFFFFFFFC),
    displayName: '雪',
    variantCount: 2,
  ),
  // ── R23k 新增（自绘材质）──────────────────────────
  Voxel.planks: VoxelSpec(
    id: Voxel.planks,
    base: Color(0xFFB08954),
    pattern: VoxelPattern.planks,
    displayName: '木板',
    variantCount: 3,
  ),
  Voxel.brick: VoxelSpec(
    id: Voxel.brick,
    base: Color(0xFF9C4F4A),
    pattern: VoxelPattern.brick,
    displayName: '红砖',
    variantCount: 3,
  ),
  Voxel.cobble: VoxelSpec(
    id: Voxel.cobble,
    base: Color(0xFF7A7E85),
    pattern: VoxelPattern.cobble,
    displayName: '圆石',
    variantCount: 4,
  ),
  Voxel.glass: VoxelSpec(
    id: Voxel.glass,
    base: Color(0xFF9EDBE8),
    transparent: true,
    pattern: VoxelPattern.glassShine,
    displayName: '玻璃',
  ),
  Voxel.slab: VoxelSpec(
    id: Voxel.slab,
    base: Color(0xFF8A8A8E),
    pattern: VoxelPattern.slabSplit,
    displayName: '半砖',
  ),
  Voxel.stairs: VoxelSpec(
    id: Voxel.stairs,
    base: Color(0xFF8A8A8E),
    pattern: VoxelPattern.stairsSteps,
    displayName: '楼梯',
  ),
  Voxel.fence: VoxelSpec(
    id: Voxel.fence,
    base: Color(0xFF7A5230),
    pattern: VoxelPattern.fenceBars,
    displayName: '栅栏',
  ),
  Voxel.furnace: VoxelSpec(
    id: Voxel.furnace,
    base: Color(0xFF6A6E75),
    pattern: VoxelPattern.furnaceFace,
    displayName: '熔炉',
  ),
  Voxel.campfire: VoxelSpec(
    id: Voxel.campfire,
    base: Color(0xFF5C4027),
    pattern: VoxelPattern.campfireGlow,
    displayName: '篝火',
  ),
  Voxel.torch: VoxelSpec(
    id: Voxel.torch,
    base: Color(0xFF8A6A3F),
    pattern: VoxelPattern.torchGlow,
    displayName: '火把',
  ),
  Voxel.chest: VoxelSpec(
    id: Voxel.chest,
    base: Color(0xFF9C6B2E),
    pattern: VoxelPattern.chestFace,
    displayName: '箱子',
  ),
  Voxel.apple: VoxelSpec(
    id: Voxel.apple,
    base: Color(0xFFD63A3A),
    pattern: VoxelPattern.appleShine,
    displayName: '苹果',
  ),
  Voxel.bread: VoxelSpec(
    id: Voxel.bread,
    base: Color(0xFFE0B46A),
    displayName: '面包',
  ),
  // ── R29 新增食物（单一事实源 displayName，背包 / 准星 / HUD 统一显示）──
  Voxel.beef: VoxelSpec(
    id: Voxel.beef,
    base: Color(0xFF9C5A3C),
    displayName: '生牛肉',
  ),
  Voxel.cookedBeef: VoxelSpec(
    id: Voxel.cookedBeef,
    base: Color(0xFF7E4326),
    displayName: '熟牛肉',
  ),
  Voxel.porkchop: VoxelSpec(
    id: Voxel.porkchop,
    base: Color(0xFFC98B6B),
    displayName: '生猪排',
  ),
  Voxel.cookedPorkchop: VoxelSpec(
    id: Voxel.cookedPorkchop,
    base: Color(0xFF9C6B45),
    displayName: '熟猪排',
  ),
  Voxel.carrot: VoxelSpec(
    id: Voxel.carrot,
    base: Color(0xFFE8832C),
    displayName: '胡萝卜',
  ),
  Voxel.potato: VoxelSpec(
    id: Voxel.potato,
    base: Color(0xFFD9C27A),
    displayName: '土豆',
  ),
  Voxel.bakedPotato: VoxelSpec(
    id: Voxel.bakedPotato,
    base: Color(0xFFB98E4A),
    displayName: '烤土豆',
  ),
  Voxel.chicken: VoxelSpec(
    id: Voxel.chicken,
    base: Color(0xFFD9B38C),
    displayName: '生鸡肉',
  ),
  Voxel.cookedChicken: VoxelSpec(
    id: Voxel.cookedChicken,
    base: Color(0xFFA9763F),
    displayName: '熟鸡肉',
  ),
  Voxel.melonSlice: VoxelSpec(
    id: Voxel.melonSlice,
    base: Color(0xFFE84D4D),
    displayName: '西瓜片',
  ),
  Voxel.cookie: VoxelSpec(
    id: Voxel.cookie,
    base: Color(0xFFB07A3C),
    displayName: '曲奇',
  ),
  Voxel.fish: VoxelSpec(
    id: Voxel.fish,
    base: Color(0xFF9FB0B0),
    displayName: '生鱼',
  ),
  Voxel.cookedFish: VoxelSpec(
    id: Voxel.cookedFish,
    base: Color(0xFFC9B27A),
    displayName: '熟鱼',
  ),
  Voxel.gold: VoxelSpec(
    id: Voxel.gold,
    base: Color(0xFFF2C94C),
    pattern: VoxelPattern.goldShine,
    displayName: '金锭',
  ),
  Voxel.diamond: VoxelSpec(
    id: Voxel.diamond,
    base: Color(0xFF5EE6D8),
    pattern: VoxelPattern.diamondShine,
    displayName: '钻石',
  ),
  Voxel.ironOre: VoxelSpec(
    id: Voxel.ironOre,
    base: Color(0xFFB08968),
    displayName: '铁矿石',
  ),
  Voxel.coalOre: VoxelSpec(
    id: Voxel.coalOre,
    base: Color(0xFF3B3B3B),
    displayName: '煤矿石',
  ),
  Voxel.redstoneOre: VoxelSpec(
    id: Voxel.redstoneOre,
    base: Color(0xFF5A5A5E),
    displayName: '红石矿石',
  ),
  Voxel.lapisOre: VoxelSpec(
    id: Voxel.lapisOre,
    base: Color(0xFF5A5A5E),
    displayName: '青金石矿石',
  ),
  Voxel.emeraldOre: VoxelSpec(
    id: Voxel.emeraldOre,
    base: Color(0xFF5A5A5E),
    displayName: '绿宝石矿石',
  ),
  Voxel.diamondOre: VoxelSpec(
    id: Voxel.diamondOre,
    base: Color(0xFF5A5A5E),
    displayName: '钻石矿石',
  ),
  Voxel.redstone: VoxelSpec(
    id: Voxel.redstone,
    base: Color(0xFFC0392B),
    displayName: '红石',
  ),
  Voxel.lapis: VoxelSpec(
    id: Voxel.lapis,
    base: Color(0xFF2E5BC4),
    displayName: '青金石',
  ),
  Voxel.emerald: VoxelSpec(
    id: Voxel.emerald,
    base: Color(0xFF2ECC71),
    displayName: '绿宝石',
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
  /// 平原：草地表、少量树、平缓起伏。
  plains,

  /// 森林：草地表、大量树、丘陵起伏。
  forest,

  /// 沙漠：沙地表、无树、沙丘。
  desert,

  /// 高山：石头、少树、落差大、仅极顶积雪。
  mountain,

  /// 雪山：石头、雪顶覆盖、最高耸。
  snowMountain,

  /// 河流：浅水通道（低于水平面，沙质河床）。
  river,

  /// 海洋：深水盆地（低于水平面，沙质海床）。
  ocean,
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
/// 基准高度整体抬到水面之上（[VoxelWorld.waterLevel]=32），低洼处自然成水。
/// G6：海平面=32、世界最高=128。陆地群系基准落在 32–43 蓄水带附近（低处概率
/// 成塘/湖）；山体从 40 起拔高到 43–64（高山流水/瀑布带）乃至雪峰。
const Map<Biome, BiomeSpec> kBiomes = <Biome, BiomeSpec>{
  Biome.plains: BiomeSpec(
    surface: Voxel.grass,
    subsurface: Voxel.dirt,
    treeDensity: 0.03,
    minTrunk: 3,
    maxTrunk: 5,
    baseHeight: 40,
    // 用户确认（地表不平整）：振幅 10 → 7，平原更平缓（保留微起伏）。
    amplitude: 12,
  ),
  Biome.forest: BiomeSpec(
    surface: Voxel.grass,
    subsurface: Voxel.dirt,
    // 用户确认（性能优化）：森林面数太多 → 树密度 0.14 → 0.09（约 -35%），
    // 保留森林观感但显著降树冠面数（树叶是面数大头）。
    treeDensity: 0.09,
    minTrunk: 4,
    maxTrunk: 7,
    baseHeight: 44,
    // 用户确认（地表不平整）：振幅 14 → 11，森林丘陵更缓。
    amplitude: 8,
  ),
  Biome.desert: BiomeSpec(
    surface: Voxel.sand,
    subsurface: Voxel.sand,
    treeDensity: 0.0,
    minTrunk: 0,
    maxTrunk: 0,
    baseHeight: 38,
    // 用户确认（地表不平整）：振幅 12 → 9，沙漠更平坦。
    amplitude: 6,
  ),
  Biome.mountain: BiomeSpec(
    surface: Voxel.stone,
    subsurface: Voxel.stone,
    treeDensity: 0.05,
    minTrunk: 3,
    maxTrunk: 5,
    baseHeight: 58,
    amplitude: 48,
    snowy: true,
    snowLine: 0.82,
  ),
  Biome.snowMountain: BiomeSpec(
    surface: Voxel.stone,
    subsurface: Voxel.stone,
    treeDensity: 0.03,
    minTrunk: 3,
    maxTrunk: 5,
    baseHeight: 68,
    amplitude: 52,
    snowy: true,
    snowLine: 0.25,
  ),
  Biome.river: BiomeSpec(
    surface: Voxel.sand,
    subsurface: Voxel.sand,
    treeDensity: 0.0,
    minTrunk: 0,
    maxTrunk: 0,
    baseHeight: 35,
    amplitude: 4,
  ),
  Biome.ocean: BiomeSpec(
    surface: Voxel.sand,
    subsurface: Voxel.sand,
    treeDensity: 0.0,
    minTrunk: 0,
    maxTrunk: 0,
    baseHeight: 24,
    amplitude: 5,
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
