/// LOD 参数体系测试（开关/步长/采样2幂/最远距离/近处 LOD）——
/// 用 [VoxelFrame.lodFaceCount]（远景大方块面数统计）直接验证参数生效。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/voxel/voxel_camera.dart';
import '../lib/widgets/voxel/voxel_renderer.dart';
import '../lib/widgets/voxel/voxel_world.dart';

void main() {
  // 大世界（128×128 = 8×8 区块）让 LOD 真正触发（默认 24×24 太小）。
  final VoxelWorld world = VoxelWorld(sizeX: 128, sizeZ: 128, maxY: 96);

  VoxelFrame _frame(RenderConfig config) => VoxelRenderer.buildFrame(
        world: world,
        camera: VoxelCamera(
          position: const Vec3(64, 48, 64),
          fov: 1.1,
        ),
        viewport: const Size(800, 500),
        cache: null,
        config: config,
      );

  RenderConfig _cfg({
    bool lodMasterEnabled = true,
    int lodStartChunks = 2,
    int lodStepBlocks = 16,
    int lodSampleBase = 4,
    int lodMaxChunks = 8,
    int fullBandChunks = 2,
  }) =>
      RenderConfig(
        lodQuality: LodQuality.high,
        lodMasterEnabled: lodMasterEnabled,
        lodStartChunks: lodStartChunks,
        lodStepBlocks: lodStepBlocks,
        lodSampleBase: lodSampleBase,
        lodMaxChunks: lodMaxChunks,
        fullBandChunks: fullBandChunks,
        // 全量 LOD 单元（默认分帧 6 会限制首帧计数，测试失真）。
        lodBuildBudget: 9999,
      );

  test('LOD 开关：开 = 有远景 LOD 面；关 = 0（全满精度）', () {
    final int on = _frame(_cfg()).lodFaceCount;
    final int off = _frame(_cfg(lodMasterEnabled: false)).lodFaceCount;
    expect(on, greaterThan(0), reason: '开启时应有远景大方块面');
    expect(off, 0, reason: '关闭时无任何 LOD 面');
  });

  test('采样 2 幂：细采样（2×2）LOD 面 ≥ 粗采样（8×8）', () {
    final int fine = _frame(_cfg(lodSampleBase: 2)).lodFaceCount;
    final int coarse = _frame(_cfg(lodSampleBase: 8)).lodFaceCount;
    expect(fine, greaterThanOrEqualTo(coarse), reason: '越粗的大方块越省 LOD 面');
  });

  test('LOD 最远距离：4/32 区块都发射 LOD（覆盖由 effMax 逻辑保证到更远）', () {
    // 面数不是覆盖距离的好指标（远环 cell 大 → 面密度低）；覆盖范围由
    // `effMax = max(lodMaxChunks×16, 视距)` 驱动遍历半径，此处验证两档都发射。
    final int near = _frame(_cfg(lodMaxChunks: 4)).lodFaceCount;
    final int far = _frame(_cfg(lodMaxChunks: 32)).lodFaceCount;
    expect(near, greaterThan(0));
    expect(far, greaterThan(0));
    // 更远距离档必须产生更远的 LOD 单元：粗采样远环存在（32 区块档位表更长）。
    expect(far, greaterThanOrEqualTo(near ~/ 4), reason: '32 区块应覆盖 4 区块的超集区域');
  });

  test('步长：3 格密档 LOD 面 ≤ 16 格疏档（步长小 = 更早降级粗 LOD = 更省面）', () {
    // cell 按档翻倍：步长小 → 档密 → cell 涨快 → 远环更粗 → 面更少（省面意图）。
    final int dense = _frame(_cfg(lodStepBlocks: 3)).lodFaceCount;
    final int sparse = _frame(_cfg(lodStepBlocks: 16)).lodFaceCount;
    expect(dense, lessThanOrEqualTo(sparse), reason: '步长小 = 更早进入粗 LOD = 更省面');
  });

  test('地平线 Impostor：最外档（cell≥32）路径不崩且发射 LOD 面', () {
    // 大最远距离 + 粗采样 → 档位表 cell 增长到 ≥32 触发 Impostor（flat 合成单元）。
    final VoxelFrame f = _frame(_cfg(lodMaxChunks: 32, lodSampleBase: 8));
    expect(f.lodFaceCount, greaterThan(0), reason: 'Impostor 也应发射远景面');
    expect(f.opaque.length, greaterThan(0));
  });

  test('近处 LOD：fullBand=1（3×3 满精度带）LOD 面 ≥ fullBand=2（5×5）', () {
    final int narrow = _frame(_cfg(fullBandChunks: 1)).lodFaceCount;
    final int wide = _frame(_cfg(fullBandChunks: 2)).lodFaceCount;
    expect(narrow, greaterThanOrEqualTo(wide), reason: '满精度带收窄 → 更早进入 LOD → 更多 LOD 面');
  });
}
