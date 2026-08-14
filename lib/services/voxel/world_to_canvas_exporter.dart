/// ════════════════════════════════════════════════════════════════════════
/// 3D 体素世界 → 2.5D 音效画布 区域提取（Module "MusicViz-2.5D" · B）
/// ════════════════════════════════════════════════════════════════════════
///
/// 玩家在 3D 世界选中某区域 → 把它"压扁"成 2.5D 等距音效场景：
///   - 每个列的最高实心方块 → 映射到一种音效块（地形/材质 → 声音语义）；
///   - 地表相对水面的高度 → 归一化为每格 [0,1] 高度比（存进 [VoxelSoundScene.heights]），
///     供 2.5D 渲染的"高度起伏"做静态度底（音乐再在其上叠加脉冲）。
///
/// 纯数据、无 Flutter 依赖，可在 isolate / 测试直接跑。
library;

import '../../models/voxel.dart';
import '../../widgets/voxel/voxel_canvas_controller.dart';
import '../../widgets/voxel/voxel_world.dart';
import '../../widgets/voxel/voxel_world_types.dart';

/// 提取结果：场景 + 每格高度比。
typedef ExportResult = ({VoxelSoundScene scene, Map<String, double> heights});

/// 3D 体素世界选定区域 → 2.5D 音效场景 + 每格高度比。
class WorldToCanvasExporter {
  const WorldToCanvasExporter._();

  /// 以世界坐标 `(cx, cz)` 为中心、半径 [radius] 的方形区域（边长 `2*radius+1`）。
  ///
  /// 返回可直接 `voxelSoundScenesProvider.save(...)` 的 [VoxelSoundScene]，
  /// 其 [VoxelSoundScene.heights] 已按区域最高/最低地表归一化到 [0,1]。
  static ExportResult exportRegion(
    VoxelWorld world,
    int cx,
    int cz,
    int radius,
  ) {
    final int n = radius * 2 + 1;
    final Map<String, String> blocks = <String, String>{};
    final Map<String, double> heights = <String, double>{};
    final List<(int, int, double)> raw = <(int, int, double)>[];

    double minH = double.infinity;
    double maxH = double.negativeInfinity;

    for (int dz = -radius; dz <= radius; dz++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final int wx = cx + dx;
        final int wz = cz + dz;
        final int col = dx + radius;
        final int row = dz + radius;
        final int h = world.surfaceHeight(wx, wz);
        final Voxel top = world.get(wx, h, wz);
        final String typeId = _mapVoxel(top, world, wx, wz, h);
        final String key = VoxelCanvasController.keyOf(col, row);
        blocks[key] = typeId;
        // 相对水面的高度（可负：水下/坑；可正：山）。
        final double hr = (h - world.waterLevel).toDouble();
        raw.add((col, row, hr));
        if (hr < minH) minH = hr;
        if (hr > maxH) maxH = hr;
      }
    }

    // 归一化到 [0,1]；单一高度（无起伏）→ 中性中值 0.5，渲染不塌成纯地面。
    final double span = (maxH - minH).abs();
    for (final (int c, int r, double hr) in raw) {
      final String key = VoxelCanvasController.keyOf(c, r);
      heights[key] =
          span < 1e-6 ? 0.5 : ((hr - minH) / span).clamp(0.0, 1.0);
    }

    final VoxelSoundScene scene = VoxelSoundScene(
      id: _genId(),
      name: '世界提取 · ${_regionName(world, cx, cz)}',
      cols: n,
      rows: n,
      blocks: blocks,
      heights: heights,
    );
    return (scene: scene, heights: heights);
  }

  /// 体素 → 音效块类型（声音语义映射，见设计文档 §B）。
  ///
  /// - 水 / 沙（近水岸）→ `water`（水流）
  /// - 叶 / 木（树）→ `bird`（鸟鸣）
  /// - 雪 / 远高于水面的高地 → `wind`（风声）
  /// - 草 / 泥（平原）→ `cricket`（虫鸣）
  /// - 其余（石头/峭壁）→ `rain`（雨声）
  static String _mapVoxel(Voxel v, VoxelWorld world, int x, int z, int h) {
    switch (v) {
      case Voxel.water:
      case Voxel.sand:
        return 'water';
      case Voxel.leaves:
      case Voxel.wood:
        return 'bird';
      case Voxel.snow:
        return 'wind';
      case Voxel.grass:
      case Voxel.dirt:
        return 'cricket';
      default:
        // 高山（远高于水面）→ 风声；其余石头/峭壁 → 雨声。
        return (h - world.waterLevel) > 30 ? 'wind' : 'rain';
    }
  }

  /// 区域命名：取中心群系 + 坐标，便于在场景列表里区分。
  static String _regionName(VoxelWorld world, int cx, int cz) =>
      '${_biomeLabel(world.biomeAt(cx, cz))}@$cx,$cz';

  static String _biomeLabel(Biome b) {
    switch (b) {
      case Biome.plains:
        return '平原';
      case Biome.forest:
        return '森林';
      case Biome.desert:
        return '沙漠';
      case Biome.mountain:
        return '高山';
      case Biome.snowMountain:
        return '雪山';
      case Biome.river:
        return '河流';
      case Biome.ocean:
        return '海洋';
    }
  }

  /// 唯一 id（时间戳 + 坐标散列，避免重复）。
  static String _genId() {
    final int t = DateTime.now().microsecondsSinceEpoch;
    return 'world_$t';
  }
}
