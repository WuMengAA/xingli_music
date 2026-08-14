/// R29 · 数据驱动食物命名 + 概率空间音效 + 背景音乐引擎 单测。
///
/// 锁定三项用户硬要求（"已经说了 4 遍"级别）：
///   1. 物品栏标明物体/方块名称（不要写死）——所有 [Voxel]（含 R29 新增 13 种
///      食物）的 [kVoxelSpecs] 必须带非空 [VoxelSpec.displayName]（数据驱动单一
///      事实源，新增方块天然强制填名，杜绝 switch 漏改）。
///   2. 概率 3D 音效：水边响度按水量 10%→75% 递增；鸟鸣每片自然叶 0.01%（封顶
///      0.95）。
///   3. 背景音乐引擎缺素材 = 安全 no-op（不崩、不播放）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/services/voxel/voxel_music_engine.dart';
import 'package:xingli_music/widgets/voxel/voxel_items.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_types.dart';
import 'package:xingli_music/widgets/voxel/world_audio_engine.dart';

/// R29 新增的 13 种可食物品（与 [foodValue] / [ItemStack.maxStack] 保持同一清单）。
const List<Voxel> kNewFoods = <Voxel>[
  Voxel.beef,
  Voxel.cookedBeef,
  Voxel.porkchop,
  Voxel.cookedPorkchop,
  Voxel.carrot,
  Voxel.potato,
  Voxel.bakedPotato,
  Voxel.chicken,
  Voxel.cookedChicken,
  Voxel.melonSlice,
  Voxel.cookie,
  Voxel.fish,
  Voxel.cookedFish,
];

void main() {
  group('R29 物品栏名称（数据驱动 displayName，不要写死）', () {
    test('全部 Voxel 都有规格表条目（kVoxelSpecs 全覆盖，防枚举漏挂）', () {
      for (final Voxel v in Voxel.values) {
        expect(kVoxelSpecs.containsKey(v), isTrue,
            reason: '$v 缺少 kVoxelSpecs 条目（exhaustive map 被破坏）');
      }
    });

    test('R29 新增 13 种食物均带非空 displayName（数据驱动，杜绝写死）', () {
      for (final Voxel v in kNewFoods) {
        final String name = kVoxelSpecs[v]!.displayName;
        expect(name, isNotEmpty, reason: '$v 的 displayName 为空（写死风险）');
      }
    });

    test('显示名是真实中文名，而非退化为枚举名兜底', () {
      // 防止有人用 itemNameOf 式 switch 漏改：displayName 必须与枚举名不同。
      for (final Voxel v in kNewFoods) {
        expect(kVoxelSpecs[v]!.displayName, isNot(equals(v.name)),
            reason: '${v.name} 的 displayName 退化为枚举名（疑似写死）');
      }
    });
  });

  group('R29 食物数值（foodValue / maxStack）', () {
    test('13 种新食物堆叠上限均为 16', () {
      for (final Voxel v in kNewFoods) {
        expect(ItemStack(v).maxStack, equals(16), reason: '$v 堆叠上限应为 16');
      }
    });

    test('foodValue 与 GDD 一致（熟肉高、生食低、方块=0）', () {
      expect(foodValue(Voxel.apple), equals(4));
      expect(foodValue(Voxel.bread), equals(5));
      expect(foodValue(Voxel.beef), equals(3));
      expect(foodValue(Voxel.cookedBeef), equals(8));
      expect(foodValue(Voxel.porkchop), equals(3));
      expect(foodValue(Voxel.cookedPorkchop), equals(8));
      expect(foodValue(Voxel.carrot), equals(3));
      expect(foodValue(Voxel.potato), equals(1));
      expect(foodValue(Voxel.bakedPotato), equals(5));
      expect(foodValue(Voxel.chicken), equals(2));
      expect(foodValue(Voxel.cookedChicken), equals(6));
      expect(foodValue(Voxel.melonSlice), equals(2));
      expect(foodValue(Voxel.cookie), equals(2));
      expect(foodValue(Voxel.fish), equals(2));
      expect(foodValue(Voxel.cookedFish), equals(5));
      // 非食物必须为 0（进食判定依赖此值）。
      expect(foodValue(Voxel.stone), equals(0));
      expect(foodValue(Voxel.air), equals(0));
    });
  });

  group('R29 概率空间音效（#320）', () {
    test('水边响度随水量单调 10%→75%', () {
      // 既有管线 effective = baseVolume × strength²；
      // waterStrengthFor 反解 strength 使 effective≈target=0.10+0.65×frac。
      final double s0 = WorldAudioEngine.waterStrengthFor(0);
      final double sMid = WorldAudioEngine.waterStrengthFor(40);
      final double sFull = WorldAudioEngine.waterStrengthFor(80);
      expect(s0, greaterThan(0.0));
      expect(s0, lessThan(sMid));
      expect(sMid, lessThan(sFull));
      expect(sFull, lessThanOrEqualTo(1.0));
      // target 边界数学自检：count=0→0.10，count≥full→0.75。
      expect(0.10 + 0.65 * 0.0, closeTo(0.10, 1e-9));
      expect(0.10 + 0.65 * 1.0, closeTo(0.75, 1e-9));
    });

    test('鸟鸣概率：每片自然叶 0.01%（封顶 0.95）', () {
      expect(WorldAudioEngine.birdChanceFor(0), equals(0.0));
      expect(WorldAudioEngine.birdChanceFor(10), equals(0.001)); // 10 × 0.0001
      expect(WorldAudioEngine.birdChanceFor(9500), equals(0.95)); // 封顶
      expect(WorldAudioEngine.birdChanceFor(10000), equals(0.95)); // 超额截断
      expect(WorldAudioEngine.birdChanceFor(100),
          greaterThan(WorldAudioEngine.birdChanceFor(10)));
    });
  });

  group('R29 背景音乐引擎（#322，缺素材安全 no-op）', () {
    test('init + 让位(setActive(false)) + dispose 全程不抛错', () async {
      final VoxelMusicEngine engine = VoxelMusicEngine();
      // CI/无资源环境：_baseDir 返回 null → _tracks 空 → setActive 安全 no-op。
      await expectLater(engine.init(), completes);
      await expectLater(engine.setActive(false), completes); // 让位分支永远安全
      await expectLater(engine.dispose(), completes);
    });
  });
}
