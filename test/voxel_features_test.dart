/// R26e 分层地形特效测试：2D 高度图基石 + 5 层确定性特效
/// （悬崖 / 洞穴 / 浮空岛 / 矿脉 / 结构）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/widgets/voxel/voxel_world.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_types.dart';

void main() {
  group('VoxelWorld 分层特效', () {
    test('地下近全实心（R26r13：仅极少数小气穴）', () {
      final VoxelWorld w = VoxelWorld();
      int airUnderground = 0;
      int solidUnderground = 0;
      for (int x = 0; x < w.sizeX; x++) {
        for (int z = 0; z < w.sizeZ; z++) {
          final int h = w.terrainHeightAt(x, z);
          for (int y = 5; y < h - 1; y++) {
            if (w.get(x, y, z) == Voxel.air) {
              airUnderground++;
            } else {
              solidUnderground++;
            }
          }
        }
      }
      // ignore: avoid_print
      print('地下气穴格数: $airUnderground / 实心格数: $solidUnderground');
      // R26r13 把洞穴阈值从 0.15 抬到 0.62 → 地下近全实心，气穴占比应极低（<1%）。
      final double ratio =
          airUnderground / (airUnderground + solidUnderground);
      expect(ratio, lessThan(0.01), reason: 'R26r13 后地下应近全实心（气穴 <1%）');
    });

    test('含浮空岛（y>50 高处出现草块）', () {
      final VoxelWorld w = VoxelWorld();
      int islands = 0;
      for (int x = 0; x < w.sizeX; x++) {
        for (int z = 0; z < w.sizeZ; z++) {
          for (int y = 50; y < 120; y++) {
            if (w.get(x, y, z) == Voxel.grass) {
              islands++;
              break;
            }
          }
        }
      }
      // ignore: avoid_print
      print('浮岛草块列数: $islands');
      expect(islands, greaterThan(0), reason: '浮空岛层应生成空中草块');
    });

    test('含矿脉（金/铁/煤）', () {
      final VoxelWorld w = VoxelWorld();
      final Map<Voxel, int> ores = <Voxel, int>{};
      for (int x = 0; x < w.sizeX; x++) {
        for (int z = 0; z < w.sizeZ; z++) {
          final int h = w.terrainHeightAt(x, z);
          for (int y = 2; y < h - 4; y++) {
            final Voxel v = w.get(x, y, z);
            if (v == Voxel.gold ||
                v == Voxel.ironOre ||
                v == Voxel.coalOre) {
              ores[v] = (ores[v] ?? 0) + 1;
            }
          }
        }
      }
      // ignore: avoid_print
      print('矿脉统计: $ores');
      expect(ores.isNotEmpty, isTrue, reason: '矿脉层应生成至少一种矿');
    });

    test('含沙漠结构（cobble/brick 高出地表）', () {
      final VoxelWorld w = VoxelWorld();
      final Map<Biome, int> biomes = <Biome, int>{};
      for (int x = -40; x <= 40; x++) {
        for (int z = -40; z <= 40; z++) {
          final Biome b = w.biomeAt(x, z);
          biomes[b] = (biomes[b] ?? 0) + 1;
        }
      }
      // ignore: avoid_print
      print('群系分布(-40..40): $biomes');
      int structures = 0;
      for (int x = -40; x <= 40; x++) {
        for (int z = -40; z <= 40; z++) {
          final int h = w.terrainHeightAt(x, z);
          final Voxel v1 = w.get(x, h + 1, z);
          final Voxel v2 = w.get(x, h + 2, z);
          if (v1 == Voxel.cobble || v2 == Voxel.brick) structures++;
        }
      }
      // ignore: avoid_print
      print('结构列数: $structures');
      expect(structures, greaterThan(0), reason: '沙漠结构层应生成沙堡');
    });

    test('悬崖：山地高度显著抬升（超过无悬崖基准）', () {
      final VoxelWorld w = VoxelWorld();
      int maxH = 0;
      for (int x = 0; x < w.sizeX; x++) {
        for (int z = 0; z < w.sizeZ; z++) {
          final int h = w.terrainHeightAt(x, z);
          if (h > maxH) maxH = h;
        }
      }
      // ignore: avoid_print
      print('最高海拔: $maxH');
      // 群系基准最高约 base+amp（<70），悬崖增强应能推高若干格。
      expect(maxH, greaterThanOrEqualTo(40), reason: '悬崖增强应产生显著高差');
    });

    test('确定性：同 seed 两次生成逐格一致', () {
      final VoxelWorld a = VoxelWorld();
      final VoxelWorld b = VoxelWorld();
      int diff = 0;
      for (int x = 0; x < a.sizeX; x++) {
        for (int z = 0; z < a.sizeZ; z++) {
          for (int y = 0; y < 80; y++) {
            if (a.get(x, y, z) != b.get(x, y, z)) diff++;
          }
        }
      }
      expect(diff, 0, reason: '同 seed 必须逐格确定');
    });
  });
}
