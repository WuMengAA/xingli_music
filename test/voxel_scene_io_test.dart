/// 2.5D 场景导出 / 导入 IO 测试（Phase 2）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/models/voxel.dart';
import 'package:xingli_music/services/voxel/voxel_scene_io.dart';

void main() {
  const VoxelSoundScene scene = VoxelSoundScene(
    id: 's1',
    name: '测试场景',
    cols: 8,
    rows: 8,
    blocks: <String, String>{'0,0': 'rain', '1,1': 'wind'},
    heights: <String, double>{'0,0': 0.5},
  );

  test('encode → decode 往返一致（含 heights）', () {
    final String file = encodeSceneFile(scene);
    final VoxelSoundScene back = decodeSceneFile(file);
    expect(back.id, scene.id);
    expect(back.name, scene.name);
    expect(back.cols, scene.cols);
    expect(back.blocks, scene.blocks);
    expect(back.heights, scene.heights);
  });

  test('heights 为空时仍可往返（向后兼容）', () {
    const VoxelSoundScene noHeights = VoxelSoundScene(
      id: 's2',
      name: '无高',
      cols: 4,
      rows: 4,
      blocks: <String, String>{'0,0': 'fire'},
    );
    final VoxelSoundScene back = decodeSceneFile(encodeSceneFile(noHeights));
    expect(back.heights, isEmpty);
  });

  test('格式不符 → 抛 SceneFileFormatException', () {
    expect(
      () => decodeSceneFile('{"foo":"bar"}'),
      throwsA(isA<SceneFileFormatException>()),
    );
  });

  test('copyWith 覆盖 id/name，其余保留', () {
    final VoxelSoundScene c = scene.copyWith(id: 'new', name: '改名');
    expect(c.id, 'new');
    expect(c.name, '改名');
    expect(c.blocks, scene.blocks);
    expect(c.heights, scene.heights);
  });
}
