/// scene_api v2 · voxelCapture 兼容与向前兼容测试。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/models/scene.dart';
import 'package:xingli_music/scenes/scene_api.dart';
import 'package:xingli_music/widgets/voxel/voxel_capture_models.dart';

Scene mk({String id = 'snow', VoxelSceneCapture? voxelCapture}) => Scene(
      id: id,
      name: '雪',
      mood: 'calm',
      desc: 'd',
      track: 't',
      artist: 'a',
      soundscape: 's',
      icon: 'star',
      visual: const SceneVisual(
        gradientColors: <Color>[],
        stops: <double>[],
        accent: Color(0xFF000000),
        glyph: '*',
      ),
      visualWeight: 0.8,
      valence: 0.5,
      energy: 0.5,
      voxelCapture: voxelCapture,
    );

void main() {
  group('scene_api v2 · voxelCapture 兼容', () {
    final VoxelSceneCapture cap = VoxelSceneCapture(
      seed: 20260810,
      cameraX: 12,
      cameraY: 8,
      cameraZ: 4,
      yaw: 0.5,
      pitch: -0.3,
      fov: 1.0,
      timePhase: 0.25,
    );

    test('encodePack 写入 schema=2', () {
      final Map<String, dynamic> root =
          jsonDecode(Scenes.encodePack(mk(voxelCapture: cap)))
              as Map<String, dynamic>;
      expect(root['schema'], Scenes.packSchemaVersion);
      expect(root['schema'], 2);
    });

    test('voxelCapture 经 encode→decode 完整往返', () {
      final Scene src = mk(id: 'ocean', voxelCapture: cap);
      final Scene imported = Scenes.decodePack(Scenes.encodePack(src));
      expect(imported.voxelCapture, isNotNull);
      expect(imported.voxelCapture!.seed, cap.seed);
      expect(imported.voxelCapture!.yaw, cap.yaw);
      expect(imported.voxelCapture!.cameraX, cap.cameraX);
      // 隐私约束不变：id 重写、原 id 留作溯源。
      expect(imported.id, isNot('ocean'));
      expect(imported.id, startsWith('custom_'));
      expect(imported.sourceShareId, 'ocean');
    });

    test('无 voxelCapture 的场景也能正常往返', () {
      final Scene imported = Scenes.decodePack(Scenes.encodePack(mk(id: 'snow')));
      expect(imported.voxelCapture, isNull);
      expect(imported.id, startsWith('custom_'));
    });

    test('旧 v1 包仍可导入（向前兼容）', () {
      final String oldV1 = jsonEncode(<String, dynamic>{
        'schema': 1,
        'scene': mk(id: 'snow', voxelCapture: cap).toJson(),
      });
      final Scene imported = Scenes.decodePack(oldV1);
      expect(imported.voxelCapture!.seed, cap.seed);
      expect(imported.id, startsWith('custom_'));
    });

    test('未知 schema 拒绝', () {
      final String bad = jsonEncode(<String, dynamic>{
        'schema': 99,
        'scene': mk().toJson(),
      });
      expect(() => Scenes.decodePack(bad), throwsA(isA<FormatException>()));
    });
  });
}
