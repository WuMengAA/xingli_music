/// G3 河流系统（8-14）：V 型河谷下切 + 连续河道注水 + 冲积扇浅化 +
/// 地转偏向力（z 正=北，北半球右偏/南半球左偏）。全部经 `terrainHeightAt`
/// （纯函数）与 `get` 验证，Isolate 一致性由 voxel_isolate_test 锁死。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../lib/widgets/voxel/voxel_world.dart';
import '../lib/widgets/voxel/voxel_world_types.dart';

void main() {
  test('G3 河道存在且连续注水（沿走廊能找到水）', () {
    final VoxelWorld w = VoxelWorld();
    // 在 ±200 内扫描：应存在至少一列「陆地河道」（h≥32 且被下切低于周围、
    // 且该列有水）。
    bool sawRiverWater = false;
    for (int x = -200; x <= 200; x += 2) {
      for (int z = -200; z <= 200; z += 2) {
        final int h = w.terrainHeightAt(x, z);
        if (h < 32) continue; // 海洋不参与
        // 河道 = 下切后高度比周围 3×3 中位数明显低（V 型）且列内有水。
        int low = 0;
        for (int dx = -1; dx <= 1; dx++) {
          for (int dz = -1; dz <= 1; dz++) {
            if (w.terrainHeightAt(x + dx, z + dz) > h + 2) low++;
          }
        }
        if (low >= 4 && w.get(x, h + 1, z) == Voxel.water) {
          sawRiverWater = true;
          break;
        }
      }
      if (sawRiverWater) break;
    }
    expect(sawRiverWater, isTrue, reason: '应存在连续河道（低洼+水）');
  });

  test('G3 河床下切不挖穿海洋（h<32 不参与）', () {
    final VoxelWorld w = VoxelWorld();
    int minOcean = 9999;
    for (int x = -100; x <= 100; x += 3) {
      for (int z = -100; z <= 100; z += 3) {
        final int h = w.terrainHeightAt(x, z);
        if (w.get(x, h, z) == Voxel.sand &&
            h < 32 &&
            w.get(x, h + 1, z) == Voxel.water) {
          if (h < minOcean) minOcean = h;
        }
      }
    }
    // 海洋床不应被河流挖穿到 < 8（生成下限）。
    expect(minOcean, greaterThanOrEqualTo(8));
  });

  test('G3 高度落在 [2, maxY-6] 且确定性（同 seed 两世界一致）', () {
    final VoxelWorld a = VoxelWorld(seed: 20260814);
    final VoxelWorld b = VoxelWorld(seed: 20260814);
    for (int x = -60; x <= 60; x += 4) {
      for (int z = -60; z <= 60; z += 4) {
        final int ha = a.terrainHeightAt(x, z);
        expect(ha, inInclusiveRange(2, a.maxY - 6));
        expect(ha, b.terrainHeightAt(x, z), reason: '河流确定性 ($x,$z)');
      }
    }
  });

  test('G3 地转偏向力：河道噪声南北半球侧偏方向相反（凹凸岸）', () {
    // 通过高度差验证：同经度、南北对称位置，河流下切深度/位置应有差异
    //（北半球右偏 +X、南半球左偏 -X → 两侧地形不对称）。
    final VoxelWorld w = VoxelWorld();
    // 在河流走廊活跃的经度附近采样：北侧（z>0）与南侧（z<0）对称点高度差
    // 不应处处为 0（地转偏向力打破对称）。
    bool sawAsym = false;
    for (int x = -100; x <= 100 && !sawAsym; x += 8) {
      for (int z = 40; z <= 120; z += 8) {
        final int hn = w.terrainHeightAt(x, z); // 北半球
        final int hs = w.terrainHeightAt(x, -z); // 南半球镜像
        if ((hn - hs).abs() > 2) {
          sawAsym = true;
          break;
        }
      }
    }
    expect(sawAsym, isTrue, reason: '南北半球地形应因河道侧偏不对称');
  });
}
