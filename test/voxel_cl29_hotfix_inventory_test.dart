/// Cl29_hotfix · 背包点选交互（MC 式光标拾取）单测。
///
/// 锁定用户硬要求的交互契约：
///   1. 未手持时点选 = 整堆拾取；右键/长按 = 取一半（1 个则整堆）。
///   2. 手持时点选空格 = 整堆放；同类 = 填满；不同类 = 交换。
///   3. 手持时右键/长按 = 向该格放 1 个、光标数量减 1。
///   4. 数字键 1-9（cursorToHotbar）= 把光标物品迁移到对应快捷栏格。
///   5. 关闭面板 returnCursor = 光标物品归还背包，不悬空。
///   6. 光标随存档 toJson/loadJson 往返一致。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_types.dart';
import 'package:xingli_music/widgets/voxel/voxel_inventory.dart';
import 'package:xingli_music/widgets/voxel/voxel_items.dart';

void main() {
  group('Cl29_hotfix 背包点选交互', () {
    test('未手持点选 = 整堆拾取到光标，原格清空', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(10, const ItemStack(Voxel.stone, 64));
      inv.clickSlot(10);
      expect(inv.carrying, isTrue);
      expect(inv.cursor, const ItemStack(Voxel.stone, 64));
      expect(inv.at(10).isEmpty, isTrue);
    });

    test('未手持右键/长按 = 取一半（偶数）', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(10, const ItemStack(Voxel.stone, 10));
      inv.rightSlot(10);
      expect(inv.cursor, const ItemStack(Voxel.stone, 5));
      expect(inv.at(10), const ItemStack(Voxel.stone, 5));
    });

    test('未手持右键 = 仅 1 个时整堆拾取', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(10, const ItemStack(Voxel.apple, 1));
      inv.rightSlot(10);
      expect(inv.cursor, const ItemStack(Voxel.apple, 1));
      expect(inv.at(10).isEmpty, isTrue);
    });

    test('手持点选空格 = 整堆落位', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(10, const ItemStack(Voxel.stone, 64));
      inv.clickSlot(10); // 拾取
      inv.clickSlot(20); // 放到空格
      expect(inv.at(20), const ItemStack(Voxel.stone, 64));
      expect(inv.carrying, isFalse);
    });

    test('手持点选同类 = 填满余量、光标留余数', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(10, const ItemStack(Voxel.stone, 64));
      inv.clickSlot(10); // 光标 64
      inv.set(20, const ItemStack(Voxel.stone, 10)); // 目标同类 10
      inv.clickSlot(20); // 填满到 64，光标剩 10
      expect(inv.at(20), const ItemStack(Voxel.stone, 64));
      expect(inv.cursor, const ItemStack(Voxel.stone, 10));
    });

    test('手持点选不同类 = 交换', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(10, const ItemStack(Voxel.stone, 64));
      inv.clickSlot(10); // 光标 = 石头
      inv.set(20, const ItemStack(Voxel.apple, 5));
      inv.clickSlot(20); // 交换：20 变石头、光标变苹果
      expect(inv.at(20), const ItemStack(Voxel.stone, 64));
      expect(inv.cursor, const ItemStack(Voxel.apple, 5));
    });

    test('手持右键/长按 = 向该格放 1 个、光标减 1', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(10, const ItemStack(Voxel.stone, 64));
      inv.clickSlot(10); // 光标 64
      inv.rightSlot(20); // 空格放 1
      expect(inv.at(20), const ItemStack(Voxel.stone, 1));
      expect(inv.cursor, const ItemStack(Voxel.stone, 63));
    });

    test('手持右键不同类目标 = 不操作', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(10, const ItemStack(Voxel.stone, 64));
      inv.clickSlot(10);
      inv.set(20, const ItemStack(Voxel.apple, 5));
      inv.rightSlot(20); // 不同类不放
      expect(inv.at(20), const ItemStack(Voxel.apple, 5));
      expect(inv.cursor, const ItemStack(Voxel.stone, 64));
    });

    test('数字键 1-9（cursorToHotbar）= 迁移到对应快捷栏格', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(10, const ItemStack(Voxel.apple, 5));
      inv.clickSlot(10); // 光标 = 苹果
      inv.cursorToHotbar(3); // 移到快捷栏下标 2
      expect(inv.at(2), const ItemStack(Voxel.apple, 5));
      expect(inv.carrying, isFalse);
    });

    test('returnCursor = 光标物品归还背包', () {
      final VoxelInventory inv = VoxelInventory();
      inv.set(10, const ItemStack(Voxel.stone, 64));
      inv.clickSlot(10); // 光标 64、10 清空
      expect(inv.at(10).isEmpty, isTrue);
      inv.returnCursor();
      // 物品必须回到某个格子、光标清空。
      expect(inv.carrying, isFalse);
      int total = 0;
      for (int i = 0; i < inv.size; i++) {
        total += inv.at(i).count;
      }
      expect(total, 64);
    });

    test('光标随存档 toJson/loadJson 往返一致', () {
      final VoxelInventory a = VoxelInventory();
      a.set(10, const ItemStack(Voxel.stone, 64));
      a.clickSlot(10); // 光标 = 石头 64
      final Map<String, dynamic> json = a.toJson();

      final VoxelInventory b = VoxelInventory();
      b.loadJson(json);
      expect(b.carrying, isTrue);
      expect(b.cursor, const ItemStack(Voxel.stone, 64));
    });
  });
}
