/// 星璃 · 场景打包器
///
/// 把一个完整场景（含视觉 + 音景 + 情绪坐标 + 自定义粒子 / 背景覆盖）
/// 打包成单文件，便于分享、备份、未来跨设备同步。
///
/// 当前是纯数据打包；不嵌入媒体资产（封面/音频文件）—— 那部分走
/// `services/audio/`，场景包只存引用（musicSourceId / soundscapePath）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'scene_api.dart';

/// 场景包（不可变快照）。
@immutable
class ScenePack {
  /// 包 schema 版本号。
  final int schema;

  /// 主场景。
  final Scene scene;

  /// 打包时间（毫秒）。
  final int packedAtMs;

  /// 打包者标识（可选，例如设备名/匿名 ID）。
  final String? packedBy;

  const ScenePack({
    required this.schema,
    required this.scene,
    required this.packedAtMs,
    this.packedBy,
  });
}

/// 场景打包 / 解包。
@immutable
class ScenePacker {
  const ScenePacker._();

  /// 把场景打包为 [ScenePack]。
  static ScenePack pack(Scene scene, {String? packedBy}) => ScenePack(
        schema: Scenes.packSchemaVersion,
        scene: scene,
        packedAtMs: DateTime.now().millisecondsSinceEpoch,
        packedBy: packedBy,
      );

  /// [ScenePack] → 字符串（可直接写文件 / 分享）。
  ///
  /// P-2：用 [Scene.toShareJson]，不外泄本机绝对路径。
  static String encode(ScenePack pack) => jsonEncode({
        'schema': pack.schema,
        'packedAtMs': pack.packedAtMs,
        if (pack.packedBy != null) 'packedBy': pack.packedBy,
        'scene': pack.scene.toShareJson(),
      });

  /// 字符串 → [ScenePack]。
  ///
  /// P-2：与 `Scenes.decodePack` 同样按不可信输入处理 —— 重写 id、
  /// 强制自定义身份、清除外来本机路径。
  static ScenePack decode(String raw) {
    final Map<String, dynamic> root = jsonDecode(raw) as Map<String, dynamic>;
    return ScenePack(
      schema: root['schema'] as int,
      packedAtMs: root['packedAtMs'] as int,
      packedBy: root['packedBy'] as String?,
      scene: Scenes.sanitizeImported(
          Scene.fromJson(root['scene'] as Map<String, dynamic>)),
    );
  }

  /// 仅打包、返回字符串的便捷方法。
  static String encodeScene(Scene scene, {String? packedBy}) =>
      encode(pack(scene, packedBy: packedBy));
}