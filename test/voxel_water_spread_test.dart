/// G4 水流动（8-14）：MC 式扩散，1s=20tick 驱动，四周 9 格范围。
/// 验证：单 tick 扩散一步、水平限 9 格、向下流、遇实心方块停止、队列耗尽自然结束。
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/voxel/voxel_world.dart';
import '../lib/widgets/voxel/voxel_world_types.dart';

void main() {
  VoxelWorld makeWorld() => VoxelWorld(seed: 99);

  test('G4 放置水源后逐 tick 扩散（20tps 语义：一步/tick）', () {
    final VoxelWorld w = makeWorld();
    // 在开阔平地（取一列高度，找到地表之上的空气层）。
    int x = 5, z = 5;
    final int ground = w.terrainHeightAt(x, z);
    final int y = ground + 1;
    // 手动清空扩散邻域（4 邻 + 下方），排除地形起伏干扰。
    for (final (int dx, int dy, int dz) in <(int, int, int)>[
      (1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, -1, 0),
    ]) {
      w.setVoxel(x + dx, y + dy, z + dz, Voxel.air);
    }
    expect(w.get(x, y, z), Voxel.air);
    w.setVoxel(x, y, z, Voxel.water);
    w.addWaterSource(x, y, z);
    // tick 1：扩散到 4 邻 + 下。
    final List<(int, int, int)> step1 = w.spreadWater();
    expect(step1, isNotEmpty);
    expect(w.get(x + 1, y, z), Voxel.water);
    expect(w.get(x, y + 1, z), Voxel.air); // 不向上
    // 继续扩散直到队列耗尽。
    int ticks = 1;
    while (w.spreadWater().isNotEmpty && ticks < 60) {
      ticks++;
    }
    expect(ticks, lessThan(60), reason: '扩散应在有限 tick 内自然结束');
  });

  test('G4 水平扩散最多 9 格（kWaterSpread）', () {
    final VoxelWorld w = makeWorld();
    int x = 0, z = 0;
    // 找一个平坦开阔区（周围 12 格内都是空气地表）。
    bool found = false;
    for (int tx = -80; tx <= 80 && !found; tx += 4) {
      for (int tz = -80; tz <= 80 && !found; tz += 4) {
        final int g = w.terrainHeightAt(tx, tz);
        bool open = true;
        for (int dx = -10; dx <= 10; dx++) {
          for (int dz = -10; dz <= 10; dz++) {
            if (w.terrainHeightAt(tx + dx, tz + dz) > g + 1) {
              open = false;
              break;
            }
          }
          if (!open) break;
        }
        if (open && g >= 40) {
          x = tx;
          z = tz;
          found = true;
        }
      }
    }
    expect(found, isTrue, reason: '应找到开阔平地');
    final int y = w.terrainHeightAt(x, z) + 1;
    w.setVoxel(x, y, z, Voxel.water);
    w.addWaterSource(x, y, z);
    int ticks = 0;
    while (w.spreadWater().isNotEmpty && ticks < 200) {
      ticks++;
    }
    // 测量 +X 方向最远水格距离（不应超过 9）。
    int maxDist = 0;
    for (int dx = -14; dx <= 14; dx++) {
      for (int dz = -14; dz <= 14; dz++) {
        if (w.get(x + dx, y, z + dz) == Voxel.water) {
          final int d = dx.abs() + dz.abs();
          if (d > maxDist) maxDist = d;
        }
      }
    }
    expect(maxDist, lessThanOrEqualTo(VoxelWorld.kWaterSpread));
    expect(maxDist, greaterThanOrEqualTo(2), reason: '应至少扩散几格');
  });

  test('G4 遇实心方块边界停止（不穿透）', () {
    final VoxelWorld w = makeWorld();
    int x = 10, z = 10;
    final int g = w.terrainHeightAt(x, z);
    final int y = g + 1;
    // 在 +X 方向 3 格处放一堵石墙。
    for (int yy = y - 1; yy <= y + 3; yy++) {
      w.setVoxel(x + 3, yy, z, Voxel.stone);
    }
    w.setVoxel(x, y, z, Voxel.water);
    w.addWaterSource(x, y, z);
    int ticks = 0;
    while (w.spreadWater().isNotEmpty && ticks < 200) {
      ticks++;
    }
    // 墙另一侧不应有水（墙挡住）。
    expect(w.get(x + 4, y, z), isNot(Voxel.water));
  });

  test('G4 向下流动：水源下方是空气则水下落', () {
    final VoxelWorld w = makeWorld();
    int x = 20, z = 20;
    final int g = w.terrainHeightAt(x, z);
    // 挖一个 3 格深坑。
    for (int yy = g; yy <= g + 2; yy++) {
      w.setVoxel(x, yy, z, Voxel.air);
    }
    w.setVoxel(x, g + 2, z, Voxel.water);
    w.addWaterSource(x, g + 2, z);
    int ticks = 0;
    while (w.spreadWater().isNotEmpty && ticks < 60) {
      ticks++;
    }
    // 水应流到坑底（g 位置）。
    expect(w.get(x, g, z), Voxel.water);
  });
}
