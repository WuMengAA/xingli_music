/// R23u 生物群系 + 垂直世界（GDD §2.1/§2.3）：验证 4 群系地表、水域、256 垂直高度。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../lib/widgets/voxel/voxel_world.dart';
import '../lib/widgets/voxel/voxel_world_types.dart';

void main() {
  test('R23u 垂直世界 maxY=256 且地形在合理范围', () {
    final VoxelWorld world = VoxelWorld();
    expect(world.maxY, 256);
    int minH = 9999;
    int maxH = 0;
    for (int x = -100; x <= 100; x += 5) {
      for (int z = -100; z <= 100; z += 5) {
        final int h = world.terrainHeightAt(x, z);
        if (h < minH) minH = h;
        if (h > maxH) maxH = h;
      }
    }
    expect(minH, greaterThanOrEqualTo(8));
    expect(maxH, lessThanOrEqualTo(world.maxY - 6));
    expect(maxH - minH, greaterThan(10)); // 有起伏（非平板）
  });

  test('R23u 生物群系：大范围内出现多种地表与水域', () {
    final VoxelWorld world = VoxelWorld();
    bool sawGrass = false;
    bool sawSand = false;
    bool sawStone = false;
    bool sawWater = false;
    for (int x = -300; x <= 300; x += 4) {
      for (int z = -300; z <= 300; z += 4) {
        final int h = world.terrainHeightAt(x, z);
        if (h < world.waterLevel) {
          for (int y = h + 1; y <= world.waterLevel; y++) {
            if (world.get(x, y, z) == Voxel.water) sawWater = true;
          }
        }
        final Voxel top = world.get(x, h, z);
        if (top == Voxel.grass)
          sawGrass = true;
        else if (top == Voxel.sand)
          sawSand = true;
        else if (top == Voxel.stone) sawStone = true;
      }
    }
    // 草地表（平原/森林）+ 沙地表（沙漠）+ 石/雪山（山地）三类群系齐备。
    expect(sawGrass, isTrue);
    expect(sawSand, isTrue); // 沙漠
    expect(sawStone, isTrue); // 山地
    // 低洼自然成水（GDD 水体）。
    expect(sawWater, isTrue);
  });

  test('R23u 同 seed 世界确定性：两次生成地表一致', () {
    final VoxelWorld a = VoxelWorld(seed: 20260811);
    final VoxelWorld b = VoxelWorld(seed: 20260811);
    int diff = 0;
    for (int x = -50; x <= 50; x += 10) {
      for (int z = -50; z <= 50; z += 10) {
        if (a.get(x, a.terrainHeightAt(x, z), z) !=
            b.get(x, b.terrainHeightAt(x, z), z)) diff++;
      }
    }
    expect(diff, 0);
  });
}
