/// R23v 昼夜循环 + 方块光照 · 单元测试。
///
/// 锁定四件事：
///   1. 时相推进与环绕（10 分钟一昼夜、超过 1 回卷）；
///   2. 锁定档位不推进、切回流动不跳时间；
///   3. 时钟串 / 昼夜判定 / 太阳方向与权重；
///   4. 方块光源登记（放置即亮、破坏即灭）与就近查询。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/widgets/voxel/voxel_daynight.dart';
import 'package:xingli_music/widgets/voxel/voxel_world.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_types.dart';

void main() {
  group('DayNightCycle 时相推进', () {
    test('按 dayLength 线性推进', () {
      final DayNightCycle c = DayNightCycle(phase: 0, dayLength: 100);
      expect(c.advance(25), isTrue);
      expect(c.phase, closeTo(0.25, 1e-9));
      c.advance(25);
      expect(c.phase, closeTo(0.5, 1e-9));
    });

    test('越过一整天会回卷到 [0,1)', () {
      final DayNightCycle c = DayNightCycle(phase: 0.9, dayLength: 100);
      c.advance(20); // +0.2 → 1.1 → 0.1
      expect(c.phase, closeTo(0.1, 1e-9));
      expect(c.phase, inInclusiveRange(0.0, 1.0));
    });

    test('构造时传入越界时相也会归一', () {
      expect(DayNightCycle(phase: 1.25).phase, closeTo(0.25, 1e-9));
      expect(DayNightCycle(phase: -0.25).phase, closeTo(0.75, 1e-9));
    });

    test('dt <= 0 不推进也不算变化', () {
      final DayNightCycle c = DayNightCycle(phase: 0.3, dayLength: 100);
      expect(c.advance(0), isFalse);
      expect(c.phase, closeTo(0.3, 1e-9));
    });
  });

  group('DayNightCycle 锁定档位', () {
    test('锁定后 advance 无效，时相取档位固定值', () {
      final DayNightCycle c = DayNightCycle(phase: 0.1, dayLength: 100);
      c.mode = DayNightMode.fixedNight;
      expect(c.advance(50), isFalse);
      expect(c.phase, 0.75);
    });

    test('锁定切回流动：从当前显示时相接着走，不跳时间', () {
      final DayNightCycle c = DayNightCycle(phase: 0.1, dayLength: 100);
      c.mode = DayNightMode.fixedDusk; // 0.5
      c.mode = DayNightMode.flowing;
      expect(c.phase, closeTo(0.5, 1e-9));
      c.advance(10);
      expect(c.phase, closeTo(0.6, 1e-9));
    });

    test('next 在四档之间循环', () {
      DayNightMode m = DayNightMode.flowing;
      m = m.next;
      expect(m, DayNightMode.fixedDay);
      m = m.next.next.next; // dusk → night → flowing
      expect(m, DayNightMode.flowing);
    });
  });

  group('时钟 / 昼夜 / 太阳', () {
    test('时相 0 = 06:00，0.25 = 12:00，0.75 = 00:00', () {
      expect(DayNightCycle(phase: 0).clock, '06:00');
      expect(DayNightCycle(phase: 0.25).clock, '12:00');
      expect(DayNightCycle(phase: 0.75).clock, '00:00');
    });

    test('正午不是夜、午夜是夜', () {
      expect(DayNightCycle(phase: 0.25).isNight, isFalse);
      expect(DayNightCycle(phase: 0.75).isNight, isTrue);
      expect(DayNightCycle(phase: 0.0).isNight, isFalse); // 黎明
    });

    test('正午太阳在头顶（y 最大），午夜在地平线下', () {
      expect(DayNightCycle(phase: 0.25).sunDir.y, greaterThan(0.9));
      expect(DayNightCycle(phase: 0.75).sunDir.y, lessThan(-0.9));
    });

    test('方向光权重：白天有、夜里为 0', () {
      expect(DayNightCycle(phase: 0.25).sunWeight, greaterThan(0.5));
      expect(DayNightCycle(phase: 0.75).sunWeight, 0.0);
      expect(DayNightCycle(phase: 0.25).sunWeight, lessThanOrEqualTo(0.9));
    });
  });

  group('PointLight 衰减', () {
    const PointLight l = PointLight(
      x: 0,
      y: 0,
      z: 0,
      strength: 1.0,
      range: 10,
      tint: 0xFFFFFFFF,
    );

    test('中心最强、边缘为 0、半径外为 0', () {
      expect(l.intensityAt(0, 0, 0), closeTo(1.0, 1e-9));
      expect(l.intensityAt(10, 0, 0), 0);
      expect(l.intensityAt(99, 0, 0), 0);
    });

    test('距离越远越暗（单调递减）', () {
      double prev = l.intensityAt(0, 0, 0);
      for (double d = 1; d < 10; d += 1) {
        final double cur = l.intensityAt(d, 0, 0);
        expect(cur, lessThan(prev));
        prev = cur;
      }
    });
  });

  group('世界光源登记', () {
    test('放置火把即登记、换成空气即注销', () {
      final VoxelWorld w = VoxelWorld(sizeX: 16, sizeZ: 16);
      expect(w.lights, isEmpty);
      w.setVoxel(4, 8, 4, Voxel.torch);
      expect(w.lights.length, 1);
      w.setVoxel(4, 8, 4, Voxel.air);
      expect(w.lights, isEmpty);
    });

    test('普通方块不产生光源', () {
      final VoxelWorld w = VoxelWorld(sizeX: 16, sizeZ: 16);
      w.setVoxel(2, 8, 2, Voxel.stone);
      expect(w.lights, isEmpty);
    });

    test('lightsNear 只取半径内的、且数量受 limit 限制', () {
      final VoxelWorld w = VoxelWorld(sizeX: 64, sizeZ: 64);
      for (int i = 0; i < 20; i++) {
        w.setVoxel(i, 8, 0, Voxel.torch);
      }
      final List<PointLight> near =
          w.lightsNear(0, 0, radius: 10, limit: 5);
      expect(near.length, 5);
      for (final PointLight p in near) {
        expect(p.strength, kBlockLights[Voxel.torch]!.strength);
      }
      // 半径足够小 → 一个都取不到。
      expect(w.lightsNear(500, 500, radius: 8), isEmpty);
    });

    test('自发光：火把最亮、石头不发光', () {
      expect(selfEmissionOf(Voxel.torch), greaterThan(1.0));
      expect(selfEmissionOf(Voxel.campfire), greaterThan(1.0));
      expect(selfEmissionOf(Voxel.stone), 0.0);
    });
  });
}
