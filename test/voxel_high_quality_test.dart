// cl24：3D 世界打磨（贴图高清档恢复 + HUD 缩放）。
// 覆盖：GraphicsQuality.high 启用贴图；图集几何映射正确；HUD 缩放读写与夹紧。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/providers/voxel/hud_layout_provider.dart'
    show readHudScale, kHudScaleMin, kHudScaleMax;
import 'package:xingli_music/widgets/voxel/voxel_textures.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_view3d.dart'
    show GraphicsQuality;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GraphicsQuality tiers keep textures off (low-quality-only policy)', () {
    // cl76 收纳折叠：只留四档预设（powerSave/smooth/horizon/auto），全部
    // texture:false（低画质纯色平铺，最高档也靠 LOD 远景，不再堆贴图复杂度）。
    for (final GraphicsQuality q in GraphicsQuality.values) {
      expect(q.texture, isFalse, reason: q.label);
    }
  });

  test('VoxelTextureAtlas.tileUV maps each voxel to a 16x16 atlas tile', () {
    // 图集几何校验（不触发 GPU 解码，避免测试环境回调不触发导致的挂起）。
    // 第 0 格应在图集左上角 (0,0)-(16,16)；第 1 格右移一列。
    final Float32List uv0 = VoxelTextureAtlas.tileUV(0);
    expect(uv0, Float32List.fromList(<double>[0, 0, 16, 0, 16, 16, 0, 16]));
    final Float32List uv1 = VoxelTextureAtlas.tileUV(1);
    expect(uv1, Float32List.fromList(<double>[16, 0, 32, 0, 32, 16, 16, 16]));
    // 顶点序对齐 _fillCorners（minX,minZ / maxX,minZ / maxX,maxZ / minX,maxZ）。
    expect(uv0.length, 8);
  });

  test('readHudScale defaults to 1.0 and clamps to [min,max]', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(readHudScale(await SharedPreferences.getInstance()), 1.0);

    SharedPreferences.setMockInitialValues(
        <String, Object>{'voxel_hud_scale': 5.0});
    expect(
        readHudScale(await SharedPreferences.getInstance()), kHudScaleMax);

    SharedPreferences.setMockInitialValues(
        <String, Object>{'voxel_hud_scale': 0.1});
    expect(
        readHudScale(await SharedPreferences.getInstance()), kHudScaleMin);
  });
}
