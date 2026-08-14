/// #169 玩家皮肤图集烘焙 + UV 映射的纯逻辑回归测试。
///
/// 验证：① 带皮肤构建后 [VoxelTextureAtlas.hasSkin] 为真且图集含皮肤区域；
/// ② 各部位 6 面 [skinRectFor] 返回的矩形落在图集内、四角合法；
/// ③ 无皮肤回退时 [skinRectFor] 返回 null（实体走纯色）。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/widgets/voxel/voxel_textures.dart';

const List<String> _parts = <String>[
  'head',
  'torso',
  'armL',
  'armR',
  'legL',
  'legR',
];

Uint8List _loadSkin() {
  // flutter test 工作目录即包根，assets/player_skin.png 已声明。
  return File('assets/player_skin.png').readAsBytesSync();
}

void main() {
  test('带皮肤构建：hasSkin 为真且各面 UV 落在图集内', () async {
    final ui.Image img = (await VoxelTextureAtlas.build(skinBytes: _loadSkin()))!;
    expect(VoxelTextureAtlas.hasSkin, isTrue);
    // 图集宽 = max(8*16, 128) = 128；高 = 体素行高 + 128 皮肤区。
    expect(img.width, greaterThanOrEqualTo(128));
    final double h = img.height.toDouble();
    final double w = img.width.toDouble();

    for (final String part in _parts) {
      for (int i = 0; i < 6; i++) {
        final Float32List? rect = VoxelTextureAtlas.skinRectFor(part, i);
        expect(rect, isNotNull, reason: '$part face $i 应有皮肤矩形');
        final double rx = rect![0];
        final double ry = rect[1];
        final double rw = rect[2];
        final double rh = rect[3];
        expect(rx, greaterThanOrEqualTo(0));
        expect(ry, greaterThanOrEqualTo(0));
        expect(rx + rw, lessThanOrEqualTo(w));
        expect(ry + rh, lessThanOrEqualTo(h));
        expect(rw, greaterThan(0));
        expect(rh, greaterThan(0));
      }
    }
    img.dispose();
  });

  test('无皮肤回退：skinRectFor 返回 null，实体走纯色', () async {
    final ui.Image img = (await VoxelTextureAtlas.build())!;
    expect(VoxelTextureAtlas.hasSkin, isFalse);
    for (final String part in _parts) {
      expect(VoxelTextureAtlas.skinRectFor(part, 3), isNull);
    }
    img.dispose();
  });
}
