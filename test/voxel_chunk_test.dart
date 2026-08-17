import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/widgets/voxel/voxel_world.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_types.dart';

/// P0（开放世界）chunk 坐标系统验证。
///
/// 验证 cl38 将编辑层从线性打包 `_editKey=x*65536+z*256+y`（z 锁 0-255、
/// x±32767）改为 chunk 分桶 `(cx,cz)` + 局部编码后：任意坐标（含负坐标 /
/// 远超旧上限的大范围坐标）的 get/set 往返一致、不同 chunk 编辑独立、
/// schema:2 存档往返、seed 确定性复现。
void main() {
  group('P0 开放世界 chunk 坐标系统', () {
    test('setVoxel/get 任意坐标（负坐标/大范围）往返一致', () {
      final VoxelWorld w = VoxelWorld(seed: 123);
      // 负坐标
      w.setVoxel(-3, 12, -7, Voxel.glass);
      expect(w.get(-3, 12, -7), Voxel.glass);
      // z 远超旧 0-255 上限（旧 _editKey 会进位碰撞 x 位）
      w.setVoxel(5, 40, 300, Voxel.stone);
      expect(w.get(5, 40, 300), Voxel.stone);
      // 大范围负坐标
      w.setVoxel(-50000, 50, -40000, Voxel.brick);
      expect(w.get(-50000, 50, -40000), Voxel.brick);
      // 大范围正坐标
      w.setVoxel(100000, 60, 99999, Voxel.diamond);
      expect(w.get(100000, 60, 99999), Voxel.diamond);
    });

    test('不同 chunk 的编辑互相独立', () {
      final VoxelWorld w = VoxelWorld(seed: 1);
      w.setVoxel(0, 20, 0, Voxel.gold);
      w.setVoxel(16, 20, 0, Voxel.ironOre); // cx=1（下一列 chunk）
      w.setVoxel(0, 20, 16, Voxel.coalOre); // cz=1（下一行 chunk）
      expect(w.get(0, 20, 0), Voxel.gold);
      expect(w.get(16, 20, 0), Voxel.ironOre);
      expect(w.get(0, 20, 16), Voxel.coalOre);
    });

    test('toJson(schema:2)/loadJson 往返保留编辑（含大坐标）', () {
      final VoxelWorld a = VoxelWorld(seed: 42);
      a.setVoxel(5, 40, 7, Voxel.stone);
      a.setVoxel(-3, 12, 300, Voxel.glass);
      a.setVoxel(1000, 50, -200, Voxel.brick);
      a.setVoxel(2, 20, 3, Voxel.torch); // 发光方块 → 进入 _lights
      final Map<String, dynamic> json = a.toJson();
      expect(json['schema'], 2);
      expect(json['edits'], isA<List<Object?>>());
      final VoxelWorld b = VoxelWorld(seed: 42)..loadJson(json);
      expect(b.get(5, 40, 7), Voxel.stone);
      expect(b.get(-3, 12, 300), Voxel.glass);
      expect(b.get(1000, 50, -200), Voxel.brick);
      expect(b.get(2, 20, 3), Voxel.torch);
    });

    test('seed 复现：同 seed 同地形', () {
      final VoxelWorld a = VoxelWorld(seed: 777);
      final VoxelWorld b = VoxelWorld(seed: 777);
      for (int x = 0; x < 20; x++) {
        for (int z = 0; z < 20; z++) {
          expect(
            a.get(x, a.surfaceHeight(x, z), z),
            b.get(x, b.surfaceHeight(x, z), z),
          );
        }
      }
    });
  });

  group('P4 分块存档（按存档 ID 分目录）', () {
    test('有分块存储时 toJson 省略 edits，磁盘 chunk 文件保全编辑', () async {
      final Directory tmp = await Directory.systemTemp.createTemp('vox_p4_');
      try {
        final VoxelWorld w = VoxelWorld(seed: 9);
        await w.initChunkStore(tmp, w.seed, 'saveA');
        w.setVoxel(5, 40, 7, Voxel.stone);
        w.setVoxel(20, 12, 7, Voxel.glass); // 下一列 chunk（cx=1）
        w.setVoxel(-3, 50, 7, Voxel.brick); // 负坐标 chunk（cx=-1）
        // 模拟退出前落盘（toJson 不再内嵌编辑）
        await w.persistLoadedChunks();
        final Map<String, dynamic> json = w.toJson();
        // P4：主文件不再内嵌编辑
        expect(json['edits'], <List<int>>[]);
        // 磁盘确有独立目录与 chunk 文件
        final Directory chunkDir =
            Directory('${tmp.path}/voxel_chunks/saveA');
        expect(await chunkDir.exists(), isTrue);
        // 重新从同目录的零世界加载，流式应恢复编辑
        final VoxelWorld w2 = VoxelWorld(seed: 9);
        await w2.initChunkStore(tmp, w2.seed, 'saveA');
        await w2.streamAround(0, 0); // 覆盖 (cx,cz) ∈ [-8,8]，含 -1/0/1
        expect(w2.get(5, 40, 7), Voxel.stone);
        expect(w2.get(20, 12, 7), Voxel.glass);
        expect(w2.get(-3, 50, 7), Voxel.brick);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('多存档编辑互不串档（saveA / saveB 独立目录）', () async {
      final Directory tmp = await Directory.systemTemp.createTemp('vox_p4_');
      try {
        final VoxelWorld a = VoxelWorld(seed: 1);
        await a.initChunkStore(tmp, a.seed, 'A');
        a.setVoxel(5, 40, 7, Voxel.stone);
        await a.persistLoadedChunks();

        final VoxelWorld b = VoxelWorld(seed: 1);
        await b.initChunkStore(tmp, b.seed, 'B');
        b.setVoxel(5, 40, 7, Voxel.glass); // 同坐标不同方块
        await b.persistLoadedChunks();

        // 重新分别指向 A / B，应各自读到自己的编辑
        final VoxelWorld ra = VoxelWorld(seed: 1);
        await ra.initChunkStore(tmp, ra.seed, 'A');
        await ra.streamAround(0, 0);
        expect(ra.get(5, 40, 7), Voxel.stone);

        final VoxelWorld rb = VoxelWorld(seed: 1);
        await rb.initChunkStore(tmp, rb.seed, 'B');
        await rb.streamAround(0, 0);
        expect(rb.get(5, 40, 7), Voxel.glass);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('无分块存储（store==null）仍内嵌全量编辑，往返一致', () {
      final VoxelWorld a = VoxelWorld(seed: 42);
      a.setVoxel(5, 40, 7, Voxel.stone);
      a.setVoxel(-3, 12, 300, Voxel.glass);
      final Map<String, dynamic> json = a.toJson();
      expect(json['edits'], isA<List<Object?>>()); // 仍内嵌保全
      final VoxelWorld b = VoxelWorld(seed: 42)..loadJson(json);
      expect(b.get(5, 40, 7), Voxel.stone);
      expect(b.get(-3, 12, 300), Voxel.glass);
    });
  });
}
