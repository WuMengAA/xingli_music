/// ════════════════════════════════════════════════════════════════════════
/// 物品 / 工具 / 硬度 / 掉落（R23w · GDD §3.2 §4.1 §5.1）
/// ════════════════════════════════════════════════════════════════════════
///
/// 这一层是纯数据 + 纯函数：不引用 Flutter widgets，可在单测里直接跑。
///
/// - [ItemStack]：一格物品（方块类型 + 数量），背包 / 合成 / 掉落物共用。
/// - [ToolKind]：工具种类与等级，决定挖掘倍率与"能否有效开采"。
/// - [blockHardness]：方块基础硬度（秒·徒手基准）。
/// - [breakSeconds]：硬度 × 工具倍率 → 实际挖掘耗时。
/// - [dropsOf]：破坏后掉什么（石头掉圆石、草方块掉泥土……）。
/// - [foodValue]：可食用物品回复的饥饿值。
library;

import 'voxel_world_types.dart';

/// 一格物品：方块类型 + 数量。
///
/// 值语义（不可变），改数量返回新实例，避免背包里两格互相串改。
class ItemStack {
  const ItemStack(this.item, [this.count = 1]);

  /// 空格（数量 0 视为空）。
  static const ItemStack empty = ItemStack(Voxel.air, 0);

  final Voxel item;
  final int count;

  bool get isEmpty => count <= 0 || item == Voxel.air;

  /// 单格最大堆叠数（食物 / 稀有物少一些，贴近 MC 手感）。
  int get maxStack => switch (item) {
        Voxel.apple ||
        Voxel.bread ||
        Voxel.beef ||
        Voxel.cookedBeef ||
        Voxel.porkchop ||
        Voxel.cookedPorkchop ||
        Voxel.carrot ||
        Voxel.potato ||
        Voxel.bakedPotato ||
        Voxel.chicken ||
        Voxel.cookedChicken ||
        Voxel.melonSlice ||
        Voxel.cookie ||
        Voxel.fish ||
        Voxel.cookedFish =>
          16,
        Voxel.diamond || Voxel.gold => 32,
        _ => 64,
      };

  ItemStack withCount(int c) =>
      c <= 0 ? ItemStack.empty : ItemStack(item, c > maxStack ? maxStack : c);

  ItemStack plus(int d) => withCount(count + d);

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'i': item.name, 'c': count};

  static ItemStack fromJson(Map<String, dynamic> j) {
    final String name = (j['i'] as String?) ?? 'air';
    final Voxel v = Voxel.values.firstWhere(
      (Voxel e) => e.name == name,
      orElse: () => Voxel.air,
    );
    return ItemStack(v, (j['c'] as num?)?.toInt() ?? 0);
  }

  @override
  bool operator ==(Object other) =>
      other is ItemStack && other.item == item && other.count == count;

  @override
  int get hashCode => Object.hash(item, count);

  @override
  String toString() => isEmpty ? 'ItemStack.empty' : '${item.name}×$count';
}

/// 工具种类（决定对哪类方块加速）。
enum ToolCategory {
  /// 徒手。
  none,

  /// 镐（石 / 矿物）。
  pickaxe,

  /// 斧（木头 / 木制品）。
  axe,

  /// 锹（土 / 沙 / 雪）。
  shovel,
}

/// 工具材质等级。
enum ToolTier {
  none(1.0, 0, '徒手', attackDamage: 1, durability: 0),
  wood(2.0, 1, '木', attackDamage: 3, durability: 60),
  stone(4.0, 2, '石', attackDamage: 4, durability: 132),
  iron(6.0, 3, '铁', attackDamage: 5, durability: 251),
  diamond(8.0, 4, '钻石', attackDamage: 7, durability: 1562);

  const ToolTier(
    this.speed,
    this.level,
    this.label, {
    this.attackDamage = 1,
    this.durability = 0,
  });

  /// 挖掘倍率（对"对口"的方块生效）。
  final double speed;

  /// 采集等级（低于方块要求时挖了也不掉落）。
  final int level;

  /// 攻击伤害（手持该等级工具对实体造成的伤害基准，数据驱动）。
  final int attackDamage;

  /// 耐久度（数据驱动属性，供后续装备系统使用）。
  final int durability;

  final String label;
}

/// 手上的工具。
class ToolKind {
  const ToolKind(this.category, this.tier);

  static const ToolKind hand = ToolKind(ToolCategory.none, ToolTier.none);

  final ToolCategory category;
  final ToolTier tier;

  String get label => category == ToolCategory.none
      ? '徒手'
      : '${tier.label}${switch (category) {
          ToolCategory.pickaxe => '镐',
          ToolCategory.axe => '斧',
          ToolCategory.shovel => '锹',
          ToolCategory.none => '',
        }}';
}

/// 方块对口的工具类别（用对了才吃倍率）。
ToolCategory properToolFor(Voxel v) => switch (v) {
      Voxel.stone ||
      Voxel.cobble ||
      Voxel.brick ||
      Voxel.slab ||
      Voxel.stairs ||
      Voxel.furnace ||
      Voxel.gold ||
      Voxel.diamond ||
      Voxel.redstoneOre ||
      Voxel.lapisOre ||
      Voxel.emeraldOre ||
      Voxel.diamondOre =>
        ToolCategory.pickaxe,
      Voxel.wood ||
      Voxel.planks ||
      Voxel.fence ||
      Voxel.chest ||
      Voxel.campfire =>
        ToolCategory.axe,
      Voxel.dirt || Voxel.grass || Voxel.sand || Voxel.snow =>
        ToolCategory.shovel,
      _ => ToolCategory.none,
    };

/// 有效开采所需的最低工具等级（不足时可以挖掉但不掉落）。
int harvestLevelOf(Voxel v) => switch (v) {
      Voxel.diamond => 3,
      Voxel.diamondOre => 3,
      Voxel.gold => 2,
      Voxel.redstoneOre || Voxel.lapisOre || Voxel.emeraldOre => 2,
      Voxel.stone ||
          Voxel.cobble ||
          Voxel.brick ||
          Voxel.furnace ||
          Voxel.ironOre ||
          Voxel.coalOre =>
        1,
      _ => 0,
    };

/// 手持工具的攻击伤害（数据驱动：取工具等级对应的攻击力）。
int weaponDamage(ToolKind tool) => tool.tier.attackDamage;

/// ════════════════════════════════════════════════════════════════════════
/// 装备 / 护甲（数据驱动，R23w · GDD §5.2）
/// ════════════════════════════════════════════════════════════════════════

/// 护甲材质等级（决定提供的防护点数 EP）。
enum ArmorTier {
  none(0),
  leather(7),
  gold(11),
  chain(12),
  iron(15),
  diamond(20);

  const ArmorTier(this.points);

  /// 完整一套该材质提供的防护点数（满护甲 = 20 EP）。
  final int points;
}

/// 某材质护甲的防护点数。
int armorPointsOf(ArmorTier t) => t.points;

/// 按护甲点数减免伤害（MC 公式：减免 = 伤害 × min(20, EP) × 4%，上限 80%）。
int mitigateDamage(int raw, int armorPoints) {
  if (raw <= 0) return 0;
  if (armorPoints <= 0) return raw;
  final int ep = armorPoints > 20 ? 20 : armorPoints;
  final int reduction = (raw * ep * 0.04).round();
  final int dmg = raw - reduction;
  return dmg < 0 ? 0 : dmg;
}

/// 方块硬度（徒手挖掉的基准秒数；0 = 瞬破，负 = 不可破坏）。
double blockHardness(Voxel v) => switch (v) {
      Voxel.air || Voxel.water => -1,
      Voxel.torch => 0.05,
      Voxel.apple ||
          Voxel.bread ||
          Voxel.beef ||
          Voxel.cookedBeef ||
          Voxel.porkchop ||
          Voxel.cookedPorkchop ||
          Voxel.carrot ||
          Voxel.potato ||
          Voxel.bakedPotato ||
          Voxel.chicken ||
          Voxel.cookedChicken ||
          Voxel.melonSlice ||
          Voxel.cookie ||
          Voxel.fish ||
          Voxel.cookedFish =>
        0.05,
      Voxel.leaves => 0.25,
      Voxel.snow => 0.35,
      Voxel.sand => 0.6,
      Voxel.dirt => 0.75,
      Voxel.grass => 0.9,
      Voxel.glass => 0.45,
      Voxel.planks || Voxel.fence || Voxel.chest => 2.5,
      Voxel.wood => 3.0,
      Voxel.campfire => 2.0,
      Voxel.cobble || Voxel.slab || Voxel.stairs => 3.5,
      Voxel.stone => 4.0,
      Voxel.brick => 4.5,
      Voxel.furnace => 5.5,
      Voxel.gold => 6.0,
      Voxel.diamond => 7.5,
      Voxel.ironOre => 4.5,
      Voxel.coalOre => 4.0,
      Voxel.redstoneOre => 4.0,
      Voxel.lapisOre => 4.0,
      Voxel.emeraldOre => 4.0,
      Voxel.diamondOre => 7.5,
      Voxel.redstone => 0.5,
      Voxel.lapis => 0.5,
      Voxel.emerald => 0.5,
    };

/// 实际挖掘耗时（秒）。工具对口才吃倍率，不对口只给一点点加成。
///
/// 返回 <= 0 表示不可破坏；瞬破方块返回一个极小正数（渲染裂纹用）。
double breakSeconds(Voxel v, ToolKind tool) {
  final double h = blockHardness(v);
  if (h < 0) return -1;
  if (h == 0) return 0.01;
  final bool proper = tool.category != ToolCategory.none &&
      tool.category == properToolFor(v);
  final double mul = proper ? tool.tier.speed : (1 + (tool.tier.level * 0.12));
  final double t = h / mul;
  return t < 0.05 ? 0.05 : t;
}

/// 是否能有效开采（工具等级够 → 掉落物品；不够 → 挖掉但什么都不掉）。
bool canHarvest(Voxel v, ToolKind tool) =>
    tool.tier.level >= harvestLevelOf(v);

/// ════════════════════════════════════════════════════════════════════════
/// 放置（由工具决定速度 / 权限）——#509 装备 / 工具系统（R26fx · GDD §5.1）
/// ════════════════════════════════════════════════════════════════════════

/// 放置冷却（毫秒）：工具越好放得越快；徒手沿用 #508 的 200ms 基线。
///
/// 与破坏 [breakSeconds] 对称：破坏吃「硬度 × 工具倍率」，放置吃「工具冷却」。
/// 这样手持工具不仅在挖矿上加速，放置也会更快——工具在两类操作都生效。
int placeCooldownMs(ToolKind tool) {
  if (tool.category == ToolCategory.none) return 200; // 徒手基线（保留 #508）
  return switch (tool.tier) {
    ToolTier.wood => 160,
    ToolTier.stone => 130,
    ToolTier.iron => 100,
    ToolTier.diamond => 70,
    _ => 200,
  };
}

/// 是否允许放置该方块（工具权限闸）。
///
/// 当前创造 / 生存均不限制（MC 式：任何方块徒手可放），故默认放行。
/// 预留工具权限：未来技术类方块可要求最低工具等级（参照 [canHarvest] 的
/// [harvestLevelOf] 思路），例如「红石类需铁镐以上」——此处为统一入口。
bool canPlace(Voxel v, ToolKind tool) {
  // TODO(#509): 未来在此按 v 的「放置等级」与 tool.tier.level 比较做闸。
  return true;
}

/// 破坏后的掉落（不考虑工具等级；等级由 [canHarvest] 单独判定）。
///
/// 空表示什么都不掉（如树叶大概率空、水不可破坏）。
List<ItemStack> dropsOf(Voxel v) => switch (v) {
      Voxel.air || Voxel.water => const <ItemStack>[],
      // 草方块掉泥土、石头掉圆石——MC 经典规则。
      Voxel.grass => const <ItemStack>[ItemStack(Voxel.dirt)],
      Voxel.stone => const <ItemStack>[ItemStack(Voxel.cobble)],
      // 树叶不稳定掉落，这里给"偶尔掉苹果"的确定性简化：不掉。
      Voxel.leaves => const <ItemStack>[],
      // 矿石掉对应宝石（大跃进新增矿种）。
      Voxel.diamondOre => const <ItemStack>[ItemStack(Voxel.diamond)],
      Voxel.emeraldOre => const <ItemStack>[ItemStack(Voxel.emerald)],
      Voxel.lapisOre => const <ItemStack>[ItemStack(Voxel.lapis)],
      Voxel.redstoneOre => const <ItemStack>[ItemStack(Voxel.redstone)],
      _ => <ItemStack>[ItemStack(v)],
    };

/// 食物回复的饥饿值（0 = 不可食用）。
int foodValue(Voxel v) => switch (v) {
      Voxel.apple => 4,
      Voxel.bread => 5,
      Voxel.beef => 3,
      Voxel.cookedBeef => 8,
      Voxel.porkchop => 3,
      Voxel.cookedPorkchop => 8,
      Voxel.carrot => 3,
      Voxel.potato => 1,
      Voxel.bakedPotato => 5,
      Voxel.chicken => 2,
      Voxel.cookedChicken => 6,
      Voxel.melonSlice => 2,
      Voxel.cookie => 2,
      Voxel.fish => 2,
      Voxel.cookedFish => 5,
      _ => 0,
    };

/// 破坏方块给的经验值（0 = 不给）。
int xpOnBreak(Voxel v) => switch (v) {
      Voxel.diamond => 5,
      Voxel.gold => 3,
      Voxel.stone || Voxel.cobble => 0,
      _ => 0,
    };

/// 手持物品推出的工具（方块也能当工具：拿着钻石就是钻石镐的简化模型）。
ToolKind toolFromHeld(Voxel held) => switch (held) {
      Voxel.diamond => const ToolKind(ToolCategory.pickaxe, ToolTier.diamond),
      Voxel.gold => const ToolKind(ToolCategory.pickaxe, ToolTier.iron),
      Voxel.cobble || Voxel.stone =>
        const ToolKind(ToolCategory.pickaxe, ToolTier.stone),
      Voxel.planks || Voxel.wood =>
        const ToolKind(ToolCategory.axe, ToolTier.wood),
      Voxel.slab => const ToolKind(ToolCategory.shovel, ToolTier.stone),
      _ => ToolKind.hand,
    };
