/// ════════════════════════════════════════════════════════════════════════
/// 合成系统（R23w · GDD §4.3 / Phase 4）
/// ════════════════════════════════════════════════════════════════════════
///
/// 采用**无序配方**（shapeless）模型：只看"投入了哪些材料、各多少个"，
/// 不看摆放形状。理由：本作用触屏为主，让玩家在 3×3 里精确摆形状体验很差；
/// 无序配方保留了"收集 → 组合 → 产出"的核心乐趣，操作成本低得多。
///
/// 纯数据 + 纯函数，可单测。
library;

import 'voxel_items.dart';
import 'voxel_world_types.dart';

/// 一条合成配方。
class CraftRecipe {
  const CraftRecipe({
    required this.id,
    required this.inputs,
    required this.output,
    required this.outputCount,
    this.needsTable = false,
  });

  /// 配方标识（UI 列表 key）。
  final String id;

  /// 材料 → 需要的数量。
  final Map<Voxel, int> inputs;

  /// 产物。
  final Voxel output;
  final int outputCount;

  /// 是否需要工作台（2×2 手搓装不下的配方）。
  final bool needsTable;

  /// 材料格子总数（>4 就必须上工作台）。
  int get slotCost => inputs.values.fold(0, (int a, int b) => a + b);

  String get label => '$output';
}

/// 配方表。
///
/// 命名一律用现有方块，不额外造新方块类型——这样产物马上就能放置 / 展示，
/// 不用先补一整套材质与渲染。
const List<CraftRecipe> kRecipes = <CraftRecipe>[
  // ── 基础加工 ──────────────────────────────────
  CraftRecipe(
    id: 'planks',
    inputs: <Voxel, int>{Voxel.wood: 1},
    output: Voxel.planks,
    outputCount: 4,
  ),
  CraftRecipe(
    id: 'cobble_from_stone',
    inputs: <Voxel, int>{Voxel.stone: 1},
    output: Voxel.cobble,
    outputCount: 1,
  ),
  CraftRecipe(
    id: 'torch',
    inputs: <Voxel, int>{Voxel.planks: 1, Voxel.wood: 1},
    output: Voxel.torch,
    outputCount: 4,
  ),
  CraftRecipe(
    id: 'fence',
    inputs: <Voxel, int>{Voxel.planks: 4},
    output: Voxel.fence,
    outputCount: 3,
  ),
  CraftRecipe(
    id: 'slab',
    inputs: <Voxel, int>{Voxel.cobble: 3},
    output: Voxel.slab,
    outputCount: 6,
  ),
  // ── 需要工作台 ────────────────────────────────
  CraftRecipe(
    id: 'chest',
    inputs: <Voxel, int>{Voxel.planks: 8},
    output: Voxel.chest,
    outputCount: 1,
    needsTable: true,
  ),
  CraftRecipe(
    id: 'furnace',
    inputs: <Voxel, int>{Voxel.cobble: 8},
    output: Voxel.furnace,
    outputCount: 1,
    needsTable: true,
  ),
  CraftRecipe(
    id: 'stairs',
    inputs: <Voxel, int>{Voxel.cobble: 6},
    output: Voxel.stairs,
    outputCount: 4,
    needsTable: true,
  ),
  CraftRecipe(
    id: 'brick',
    inputs: <Voxel, int>{Voxel.cobble: 4, Voxel.sand: 2},
    output: Voxel.brick,
    outputCount: 4,
    needsTable: true,
  ),
  CraftRecipe(
    id: 'glass',
    inputs: <Voxel, int>{Voxel.sand: 4},
    output: Voxel.glass,
    outputCount: 4,
    needsTable: true,
  ),
  CraftRecipe(
    id: 'campfire',
    inputs: <Voxel, int>{Voxel.wood: 3, Voxel.planks: 3},
    output: Voxel.campfire,
    outputCount: 1,
    needsTable: true,
  ),
  CraftRecipe(
    id: 'bread',
    inputs: <Voxel, int>{Voxel.grass: 3},
    output: Voxel.bread,
    outputCount: 1,
    needsTable: true,
  ),
];

/// 用「材料清单」匹配配方。
abstract final class Crafting {
  /// 在 [available] 材料（物品→数量）下，返回所有可合成的配方。
  ///
  /// [hasTable] 为 false 时过滤掉需要工作台的配方。
  static List<CraftRecipe> availableRecipes(
    Map<Voxel, int> available, {
    bool hasTable = false,
  }) {
    final List<CraftRecipe> out = <CraftRecipe>[];
    for (final CraftRecipe r in kRecipes) {
      if (r.needsTable && !hasTable) continue;
      bool ok = true;
      for (final MapEntry<Voxel, int> need in r.inputs.entries) {
        if ((available[need.key] ?? 0) < need.value) {
          ok = false;
          break;
        }
      }
      if (ok) out.add(r);
    }
    return out;
  }

  /// 配方是否可合成。
  static bool canCraft(
    CraftRecipe r,
    Map<Voxel, int> available, {
    bool hasTable = false,
  }) {
    if (r.needsTable && !hasTable) return false;
    for (final MapEntry<Voxel, int> need in r.inputs.entries) {
      if ((available[need.key] ?? 0) < need.value) return false;
    }
    return true;
  }

  /// 产物物品堆。
  static ItemStack outputOf(CraftRecipe r) =>
      ItemStack(r.output, r.outputCount);

  /// 按 id 找配方。
  static CraftRecipe? byId(String id) {
    for (final CraftRecipe r in kRecipes) {
      if (r.id == id) return r;
    }
    return null;
  }
}
