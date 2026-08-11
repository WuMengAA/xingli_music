/// R24d 体素世界存档序列化 · 单元测试（纯 Dart，快）。
///
/// 覆盖 [VoxelWorld.toJson] / [VoxelWorld.loadJson] 的编辑层 + 发光方块往返。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/widgets/voxel/voxel_world.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_types.dart';

void main() {
  group('VoxelWorld 存档序列化', () {
    test('edits / lights 往返一致（含越界坐标与确定性地形）', () {
      final VoxelWorld a = VoxelWorld(seed: 12345);
      a.setVoxel(5, 40, 7, Voxel.stone);
      a.setVoxel(-3, 12, 20, Voxel.glass);
      a.setVoxel(1000, 50, -200, Voxel.brick); // 出生大陆外的越界坐标
      a.setVoxel(2, 20, 3, Voxel.torch); // 发光方块 → 进入 _lights

      final Map<String, dynamic> json = a.toJson();
      expect(json['seed'], 12345);
      expect(json['edits'], isA<List<Object?>>());
      expect(json['lights'], isA<List<Object?>>());

      final VoxelWorld b = VoxelWorld(seed: 12345);
      b.loadJson(json);

      // 编辑层逐格一致
      expect(b.get(5, 40, 7), Voxel.stone);
      expect(b.get(-3, 12, 20), Voxel.glass);
      expect(b.get(1000, 50, -200), Voxel.brick);
      expect(b.get(2, 20, 3), Voxel.torch);

      // 发光方块地图一致
      expect(b.lights.containsKey(const (2, 20, 3)), isTrue);
      expect(b.lights[const (2, 20, 3)], Voxel.torch);

      // 未编辑处的确定性地形仍一致
      expect(b.get(10, 10, 10), a.get(10, 10, 10));
    });

    test('loadJson 幂等：重复加载不丢失也不重复', () {
      final VoxelWorld a = VoxelWorld(seed: 77);
      a.setVoxel(4, 30, 4, Voxel.diamond);
      final Map<String, dynamic> json = a.toJson();

      final VoxelWorld b = VoxelWorld(seed: 77);
      b.loadJson(json);
      b.loadJson(json);
      expect(b.get(4, 30, 4), Voxel.diamond);
      expect(b.lights.length, lessThanOrEqualTo(512));
    });

    test('空世界序列化不报错且可恢复', () {
      final VoxelWorld a = VoxelWorld(seed: 1);
      final Map<String, dynamic> json = a.toJson();
      final VoxelWorld b = VoxelWorld(seed: 1);
      b.loadJson(json);
      expect(b.lights.isEmpty, isTrue);
      expect(b.get(0, 0, 0), isA<Voxel>());
    });
  });
}
