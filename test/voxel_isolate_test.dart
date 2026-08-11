import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/widgets/voxel/voxel_world.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_types.dart';

/// R26f：Isolate 地形预热一致性测试。
/// 锁死 `precomputeTerrain`（static 纯函数版，compute 后台用）与实例采样
/// （`terrainHeightAt` / 树）完全一致——若将来改生成算法忘改纯函数版，
/// 这里立刻红掉，杜绝双实现漂移。
void main() {
  group('Isolate 预热一致性', () {
    test('precompute 高度 == 实例 terrainHeightAt（同 seed 多坐标）', () {
      const int seed = VoxelWorld.defaultSeed;
      const int cx = 10, cz = 10, radius = 6;
      final Int32List data =
          VoxelWorld.precomputeTerrain(seed, cx, cz, radius, true);
      final VoxelWorld w = VoxelWorld(seed: seed);
      final int n = data.length ~/ 4;
      expect(n, greaterThan(0));
      for (int i = 0; i < n; i++) {
        final int x = data[i * 4];
        final int z = data[i * 4 + 1];
        final int h = data[i * 4 + 2];
        final int top = data[i * 4 + 3];
        expect(h, w.terrainHeightAt(x, z),
            reason: '高度不一致 ($x,$z): pure=$h inst=${w.terrainHeightAt(x, z)}');
        // 树顶一致性：pure 报有树 → 实例该列地表上方应出现 wood；
        // pure 报无树 → 实例地表上方 1 格应为空气/草（非 wood 树干）。
        if (top > h) {
          expect(w.get(x, h + 1, z), Voxel.wood,
              reason: 'pure 说有树但实例 ($x,$z) 无树干');
          expect(w.get(x, top, z), isNot(Voxel.air),
              reason: '树顶 ($x,$z) 不应是空气');
        } else {
          expect(w.get(x, h + 1, z), isNot(Voxel.wood),
              reason: 'pure 说无树但实例 ($x,$z) 有树干');
        }
      }
    });

    test('非默认 seed 也一致', () {
      const int seed = 987654321;
      const int cx = -8, cz = 3, radius = 4;
      final Int32List data =
          VoxelWorld.precomputeTerrain(seed, cx, cz, radius, true);
      final VoxelWorld w = VoxelWorld(seed: seed);
      final int n = data.length ~/ 4;
      for (int i = 0; i < n; i++) {
        final int x = data[i * 4];
        final int z = data[i * 4 + 1];
        expect(data[i * 4 + 2], w.terrainHeightAt(x, z),
            reason: '非默认 seed 高度不一致 ($x,$z)');
      }
    });

    test('injectTerrainPrecache 回填后命中（换 seed 丢弃）', () {
      final VoxelWorld w = VoxelWorld(seed: VoxelWorld.defaultSeed);
      final Int32List data =
          VoxelWorld.precomputeTerrain(VoxelWorld.defaultSeed, 0, 0, 3, true);
      w.injectTerrainPrecache(data, VoxelWorld.defaultSeed);
      // 回填后直接读高度，应与纯函数值一致（且不抛错）。
      for (int i = 0; i < data.length ~/ 4; i++) {
        final int x = data[i * 4];
        final int z = data[i * 4 + 1];
        expect(w.terrainHeightAt(x, z), data[i * 4 + 2]);
      }
      // 换 seed 的数据应被丢弃（不污染）。
      final Int32List wrong =
          VoxelWorld.precomputeTerrain(123, 0, 0, 3, true);
      w.injectTerrainPrecache(wrong, 123);
      // 不抛错即可；数值不受污染。
      expect(w.terrainHeightAt(0, 0), data[2]);
    });
  });
}
