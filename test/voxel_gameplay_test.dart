/// R23w 玩法层（背包 / 挖掘 / 合成 / 生存 / 生物）· 单元测试。
///
/// 全部是纯 Dart 数据层，不起 widget，跑得快：
///   1. [ItemStack] 值语义与堆叠上限；
///   2. [VoxelInventory] 增删堆叠、快捷栏、手持工具推导、存读档；
///   3. 挖掘：硬度 × 工具倍率、采集等级、掉落规则；
///   4. [Crafting] 配方匹配与工作台约束；
///   5. [PlayerVitals] 饥饿 / 回血 / 进食 / 经验升级；
///   6. [MobWorld] 掉落物重力与拾取、夜间刷怪、白天灼烧。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/widgets/voxel/voxel_camera.dart';
import 'package:xingli_music/widgets/voxel/voxel_crafting.dart';
import 'package:xingli_music/widgets/voxel/voxel_inventory.dart';
import 'package:xingli_music/widgets/voxel/voxel_items.dart';
import 'package:xingli_music/widgets/voxel/voxel_mobs.dart';
import 'package:xingli_music/widgets/voxel/voxel_survival.dart';
import 'package:xingli_music/widgets/voxel/voxel_world.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_types.dart';

void main() {
  group('ItemStack', () {
    test('数量 0 或空气都算空格', () {
      expect(const ItemStack(Voxel.stone, 0).isEmpty, isTrue);
      expect(ItemStack.empty.isEmpty, isTrue);
      expect(const ItemStack(Voxel.stone).isEmpty, isFalse);
    });

    test('堆叠上限：方块 64、食物 16、稀有 32', () {
      expect(const ItemStack(Voxel.stone).maxStack, 64);
      expect(const ItemStack(Voxel.bread).maxStack, 16);
      expect(const ItemStack(Voxel.diamond).maxStack, 32);
      expect(const ItemStack(Voxel.bread, 1).plus(99).count, 16);
    });

    test('值语义 + JSON 往返', () {
      const ItemStack a = ItemStack(Voxel.planks, 7);
      expect(a, const ItemStack(Voxel.planks, 7));
      expect(ItemStack.fromJson(a.toJson()), a);
      // 未知物品名回落成空气。
      expect(
        ItemStack.fromJson(<String, dynamic>{'i': 'nope', 'c': 3}).item,
        Voxel.air,
      );
    });
  });

  group('VoxelInventory', () {
    test('add 优先堆到同类已有格，溢出开新格', () {
      final VoxelInventory inv = VoxelInventory();
      expect(inv.add(const ItemStack(Voxel.stone, 60)), 0);
      expect(inv.add(const ItemStack(Voxel.stone, 10)), 0);
      expect(inv.countOf(Voxel.stone), 70);
      // 64 + 6 → 两格。
      final int used =
          inv.slots.where((ItemStack s) => !s.isEmpty).length;
      expect(used, 2);
    });

    test('背包塞满后 add 返回放不下的数量', () {
      final VoxelInventory inv = VoxelInventory();
      for (int i = 0; i < 36; i++) {
        inv.set(i, const ItemStack(Voxel.stone, 64));
      }
      expect(inv.add(const ItemStack(Voxel.dirt, 5)), 5);
    });

    test('consumeHeld 扣手上那格，扣空变空格', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(0, const ItemStack(Voxel.planks, 2));
      inv.selected = 0;
      expect(inv.consumeHeld(), isTrue);
      expect(inv.held.count, 1);
      expect(inv.consumeHeld(), isTrue);
      expect(inv.held.isEmpty, isTrue);
      expect(inv.consumeHeld(), isFalse);
    });

    test('take 跨格扣料，不够就不扣', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(0, const ItemStack(Voxel.cobble, 5));
      inv.set(3, const ItemStack(Voxel.cobble, 5));
      expect(inv.take(Voxel.cobble, 8), isTrue);
      expect(inv.countOf(Voxel.cobble), 2);
      expect(inv.take(Voxel.cobble, 99), isFalse);
      expect(inv.countOf(Voxel.cobble), 2);
    });

    test('手持推导工具：钻石=钻石镐、木板=木斧、空手=徒手', () {
      final VoxelInventory inv = VoxelInventory();
      inv.selected = 0;
      expect(inv.tool.tier, ToolTier.none);
      inv.set(0, const ItemStack(Voxel.diamond));
      expect(inv.tool.category, ToolCategory.pickaxe);
      expect(inv.tool.tier, ToolTier.diamond);
      inv.set(0, const ItemStack(Voxel.planks));
      expect(inv.tool.category, ToolCategory.axe);
    });

    test('存读档往返', () {
      final VoxelInventory a = VoxelInventory();
      a.set(0, const ItemStack(Voxel.torch, 8));
      a.set(11, const ItemStack(Voxel.bread, 2));
      a.selected = 3;
      final VoxelInventory b = VoxelInventory()..loadJson(a.toJson());
      expect(b.at(0), const ItemStack(Voxel.torch, 8));
      expect(b.at(11), const ItemStack(Voxel.bread, 2));
      expect(b.selected, 3);
    });
  });

  group('挖掘：硬度 / 工具 / 掉落', () {
    test('对口工具显著加速，不对口只有小加成', () {
      const ToolKind diaPick = ToolKind(ToolCategory.pickaxe, ToolTier.diamond);
      const ToolKind woodAxe = ToolKind(ToolCategory.axe, ToolTier.wood);
      final double hand = breakSeconds(Voxel.stone, ToolKind.hand);
      final double pick = breakSeconds(Voxel.stone, diaPick);
      final double axe = breakSeconds(Voxel.stone, woodAxe);
      expect(pick, lessThan(hand / 4));
      expect(axe, lessThan(hand));
      expect(axe, greaterThan(pick));
    });

    test('空气 / 水不可破坏（负数）', () {
      expect(breakSeconds(Voxel.air, ToolKind.hand), lessThan(0));
      expect(breakSeconds(Voxel.water, ToolKind.hand), lessThan(0));
    });

    test('采集等级不够 → 挖得掉但不掉落', () {
      const ToolKind woodPick = ToolKind(ToolCategory.pickaxe, ToolTier.wood);
      expect(canHarvest(Voxel.diamond, woodPick), isFalse);
      expect(canHarvest(Voxel.stone, woodPick), isTrue);
      expect(canHarvest(Voxel.dirt, ToolKind.hand), isTrue);
    });

    test('掉落规则：草→泥土、石→圆石、叶→空', () {
      expect(dropsOf(Voxel.grass).single.item, Voxel.dirt);
      expect(dropsOf(Voxel.stone).single.item, Voxel.cobble);
      expect(dropsOf(Voxel.leaves), isEmpty);
      expect(dropsOf(Voxel.planks).single.item, Voxel.planks);
    });
  });

  group('放置：工具决定冷却 / 权限 (#509)', () {
    test('徒手沿用 #508 的 200ms 基线，好工具更快', () {
      expect(placeCooldownMs(ToolKind.hand), 200);
      expect(placeCooldownMs(const ToolKind(ToolCategory.pickaxe, ToolTier.wood)), 160);
      expect(placeCooldownMs(const ToolKind(ToolCategory.pickaxe, ToolTier.stone)), 130);
      expect(placeCooldownMs(const ToolKind(ToolCategory.pickaxe, ToolTier.iron)), 100);
      expect(placeCooldownMs(const ToolKind(ToolCategory.pickaxe, ToolTier.diamond)), 70);
    });

    test('工具越好放置冷却越短（等级单调）', () {
      final int wood = placeCooldownMs(const ToolKind(ToolCategory.pickaxe, ToolTier.wood));
      final int iron = placeCooldownMs(const ToolKind(ToolCategory.pickaxe, ToolTier.iron));
      final int dia = placeCooldownMs(const ToolKind(ToolCategory.pickaxe, ToolTier.diamond));
      expect(iron, lessThan(wood));
      expect(dia, lessThan(iron));
    });

    test('放置权限闸当前默认放行（统一入口）', () {
      expect(canPlace(Voxel.stone, ToolKind.hand), isTrue);
      expect(
          canPlace(Voxel.diamond, const ToolKind(ToolCategory.pickaxe, ToolTier.wood)),
          isTrue);
    });
  });

  group('Crafting', () {
    Map<Voxel, int> bag(Map<Voxel, int> m) => m;

    test('材料够才可合成', () {
      final CraftRecipe planks = Crafting.byId('planks')!;
      expect(Crafting.canCraft(planks, bag(<Voxel, int>{Voxel.wood: 1})),
          isTrue);
      expect(Crafting.canCraft(planks, bag(<Voxel, int>{})), isFalse);
      expect(Crafting.outputOf(planks).count, 4);
    });

    test('needsTable 的配方没工作台时不可合成', () {
      final CraftRecipe furnace = Crafting.byId('furnace')!;
      final Map<Voxel, int> have = bag(<Voxel, int>{Voxel.cobble: 8});
      expect(Crafting.canCraft(furnace, have), isFalse);
      expect(Crafting.canCraft(furnace, have, hasTable: true), isTrue);
    });

    test('availableRecipes 随工作台状态变多', () {
      final Map<Voxel, int> have = bag(<Voxel, int>{
        Voxel.wood: 4,
        Voxel.planks: 8,
        Voxel.cobble: 8,
        Voxel.sand: 4,
      });
      final int without = Crafting.availableRecipes(have).length;
      final int withTable =
          Crafting.availableRecipes(have, hasTable: true).length;
      expect(withTable, greaterThan(without));
    });
  });

  group('PlayerVitals', () {
    test('移动累积疲劳 → 先扣饱和再扣饥饿', () {
      final PlayerVitals v = PlayerVitals();
      expect(v.hunger, 20);
      // 饱和 5 点，每 4.0 疲劳扣 1 点 → 走 2400 格必然扣到饥饿。
      for (int i = 0; i < 240; i++) {
        v.tick(0.1, moved: 10);
      }
      expect(v.saturation, 0);
      expect(v.hunger, lessThan(20));
    });

    test('饥饿满且掉血时会缓慢回血', () {
      final PlayerVitals v = PlayerVitals();
      v.damage(6);
      expect(v.hp, 14);
      // 每 4 秒回 1 点，跑 20 秒（不移动，饥饿保持 20）。
      for (int i = 0; i < 200; i++) {
        v.tick(0.1);
      }
      expect(v.hp, greaterThan(14));
    });

    test('进食回复饥饿，吃饱了不再浪费', () {
      final PlayerVitals v = PlayerVitals();
      expect(v.eat(Voxel.apple), isFalse); // 已经满了
      v.damage(0);
      for (int i = 0; i < 400; i++) {
        v.tick(0.1, moved: 10);
      }
      final int before = v.hunger;
      expect(before, lessThan(20));
      expect(v.eat(Voxel.bread), isTrue);
      expect(v.hunger, greaterThan(before));
      expect(v.eat(Voxel.stone), isFalse); // 石头不能吃
    });

    test('经验累积自动升级，死亡清零', () {
      final PlayerVitals v = PlayerVitals();
      expect(v.xpToNext, 7);
      v.addXp(7);
      expect(v.level, 1);
      expect(v.xpToNext, 9);
      v.addXp(100);
      expect(v.level, greaterThan(1));
      v.respawn();
      expect(v.xp, 0);
      expect(v.hp, PlayerVitals.maxHp);
    });

    test('扣血到 0 判定死亡', () {
      final PlayerVitals v = PlayerVitals();
      v.damage(999);
      expect(v.hp, 0);
      expect(v.isDead, isTrue);
    });
  });

  group('MobWorld', () {
    test('掉落物受重力下落并落在地面上', () {
      final VoxelWorld w = VoxelWorld(sizeX: 16, sizeZ: 16);
      final MobWorld m = MobWorld(world: w);
      final double g = VoxelCamera.groundHeightAt(w, 8.5, 8.5);
      m.spawnDrops(8, (g + 6).floor(), 8, const <ItemStack>[
        ItemStack(Voxel.cobble, 2),
      ]);
      expect(m.items.length, 1);
      final double y0 = m.items.first.pos.y;
      // 玩家离得很远 → 不会被立即拾走。
      for (int i = 0; i < 120; i++) {
        m.tick(
          1 / 60,
          playerPos: Vec3(200, g, 200),
          isNight: false,
          survival: true,
          onHitPlayer: (int _) {},
        );
        m.tickItemsOnly(1 / 60, Vec3(200, g, 200), (ItemStack _) => true);
      }
      expect(m.items.first.pos.y, lessThan(y0));
      expect(m.items.first.pos.y, greaterThanOrEqualTo(0));
    });

    test('玩家走近 → 掉落物被拾取', () {
      final VoxelWorld w = VoxelWorld(sizeX: 16, sizeZ: 16);
      final MobWorld m = MobWorld(world: w);
      final double g = VoxelCamera.groundHeightAt(w, 8.5, 8.5);
      m.spawnDrops(8, g.floor() + 1, 8, const <ItemStack>[
        ItemStack(Voxel.dirt, 1),
      ]);
      final List<ItemStack> got = <ItemStack>[];
      for (int i = 0; i < 300 && m.items.isNotEmpty; i++) {
        m.tick(
          1 / 60,
          playerPos: Vec3(8.5, g, 8.5),
          isNight: false,
          survival: true,
          onHitPlayer: (int _) {},
        );
        m.tickItemsOnly(
          1 / 60,
          Vec3(8.5, g, 8.5),
          (ItemStack s) {
            got.add(s);
            return true;
          },
        );
      }
      expect(m.items, isEmpty);
      expect(got.single.item, Voxel.dirt);
    });

    test('白天不刷僵尸，夜里会刷', () {
      final VoxelWorld w = VoxelWorld(sizeX: 32, sizeZ: 32);
      final MobWorld day = MobWorld(world: w);
      final double g = VoxelCamera.groundHeightAt(w, 16.5, 16.5);
      for (int i = 0; i < 600; i++) {
        day.tick(
          1 / 60,
          playerPos: Vec3(16.5, g, 16.5),
          isNight: false,
          survival: true,
          onHitPlayer: (int _) {},
        );
      }
      expect(day.zombies, isEmpty);

      final MobWorld night = MobWorld(world: w);
      for (int i = 0; i < 1800; i++) {
        night.tick(
          1 / 60,
          playerPos: Vec3(16.5, g, 16.5),
          isNight: true,
          survival: true,
          onHitPlayer: (int _) {},
        );
      }
      expect(night.zombies, isNotEmpty);
    });

    test('创造模式（survival=false）不刷怪', () {
      final VoxelWorld w = VoxelWorld(sizeX: 32, sizeZ: 32);
      final MobWorld m = MobWorld(world: w);
      final double g = VoxelCamera.groundHeightAt(w, 16.5, 16.5);
      for (int i = 0; i < 1800; i++) {
        m.tick(
          1 / 60,
          playerPos: Vec3(16.5, g, 16.5),
          isNight: true,
          survival: false,
          onHitPlayer: (int _) {},
        );
      }
      expect(m.zombies, isEmpty);
      expect(m.isEmpty, isTrue);
    });

    test('clear 清空世界里的怪与掉落物', () {
      final VoxelWorld w = VoxelWorld(sizeX: 16, sizeZ: 16);
      final MobWorld m = MobWorld(world: w);
      m.spawnDrops(8, 60, 8, const <ItemStack>[ItemStack(Voxel.sand)]);
      expect(m.isEmpty, isFalse);
      m.clear();
      expect(m.isEmpty, isTrue);
    });
  });
}
