/// WorldToCanvasExporter 单元测试（Module "MusicViz-2.5D" · B）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/models/voxel.dart';
import 'package:xingli_music/services/voxel/world_to_canvas_exporter.dart';
import 'package:xingli_music/widgets/voxel/voxel_world.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_types.dart';

void main() {
  test('exportRegion 生成 (2r+1)² 格，heights 归一化到 [0,1]', () {
    final VoxelWorld world = VoxelWorld(seed: 1, sizeX: 24, sizeZ: 24);
    const int r = 2;
    final ExportResult res =
        WorldToCanvasExporter.exportRegion(world, 12, 12, r);

    expect(res.scene.cols, 2 * r + 1);
    expect(res.scene.rows, 2 * r + 1);
    expect(res.scene.blocks.length, (2 * r + 1) * (2 * r + 1));
    expect(res.heights.length, (2 * r + 1) * (2 * r + 1));

    for (final double v in res.heights.values) {
      expect(v, greaterThanOrEqualTo(0.0));
      expect(v, lessThanOrEqualTo(1.0));
    }
    // 所有块都是合法音效块类型 id。
    for (final String id in res.scene.blocks.values) {
      expect(kVoxelBlockTypes.any((VoxelBlockType t) => t.id == id), isTrue);
    }
  });

  test('单高度区域 → 所有格归一化为中性 0.5（无起伏不塌地面）', () {
    final VoxelWorld world = VoxelWorld(seed: 9, sizeX: 8, sizeZ: 8);
    // 把区域内每一列都放一块到同一高度（y=60，高于任何地形/树）。
    const int r = 1;
    for (int dz = -r; dz <= r; dz++) {
      for (int dx = -r; dx <= r; dx++) {
        world.setVoxel(4 + dx, 60, 4 + dz, Voxel.stone);
      }
    }
    final ExportResult res =
        WorldToCanvasExporter.exportRegion(world, 4, 4, r);
    expect(res.heights.length, (2 * r + 1) * (2 * r + 1));
    for (final double v in res.heights.values) {
      expect(v, closeTo(0.5, 1e-9));
    }
  });

  test('体素→音效块映射正确（水/沙→water，草→cricket，叶→bird，雪→wind，石→rain）',
      () {
    final VoxelWorld world = VoxelWorld(seed: 5, sizeX: 8, sizeZ: 8);
    // 在每列高处放目标方块，使其成为 surfaceHeight 顶面（上方全空气）。
    world.setVoxel(4, 60, 4, Voxel.water); // 中心 → water
    world.setVoxel(3, 60, 4, Voxel.sand); // → water
    world.setVoxel(5, 60, 4, Voxel.grass); // → cricket
    world.setVoxel(4, 60, 3, Voxel.leaves); // → bird
    world.setVoxel(4, 60, 5, Voxel.snow); // → wind
    world.setVoxel(3, 60, 3, Voxel.stone); // → rain

    const int r = 1;
    final ExportResult res =
        WorldToCanvasExporter.exportRegion(world, 4, 4, r);
    // 坐标：col = dx + r, row = dz + r；中心 (4,4) → "1,1"。
    expect(res.scene.blocks['1,1'], 'water'); // 水
    expect(res.scene.blocks['0,1'], 'water'); // 沙
    expect(res.scene.blocks['2,1'], 'cricket'); // 草
    expect(res.scene.blocks['1,0'], 'bird'); // 叶
    expect(res.scene.blocks['1,2'], 'wind'); // 雪
    expect(res.scene.blocks['0,0'], 'rain'); // 石
  });
}
