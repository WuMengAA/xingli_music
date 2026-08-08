/// 星璃 · 场景部署 / 导出 / 导入
///
/// `SceneDeploy` 是场景系统的"出口"——
///   - 导出当前场景为可分享的 JSON 包
///   - 从外部 JSON 包导入场景
///
/// 本地优先原则：所有 IO 仅在调用方显式触发时发生，
/// 不做自动上传/同步（保留用户隐私控制权）。
library;

import 'package:flutter/foundation.dart';

import 'scene_api.dart';

/// 场景部署结果。
@immutable
class SceneDeployResult {
  /// 生成的场景包（JSON 字符串）。
  final String pack;

  /// 场景包大小（字节 / 字符数）。
  final int bytes;

  /// 导出时间戳（毫秒）。
  final int exportedAtMs;

  const SceneDeployResult({
    required this.pack,
    required this.bytes,
    required this.exportedAtMs,
  });
}

/// 场景部署门面。
@immutable
class SceneDeploy {
  const SceneDeploy._();

  /// 导出单个场景为 JSON 包。
  static SceneDeployResult exportScene(Scene scene) {
    final String pack = Scenes.encodePack(scene);
    return SceneDeployResult(
      pack: pack,
      bytes: pack.length,
      exportedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 从 JSON 包导入场景。失败时抛 [FormatException]。
  static Scene importScene(String pack) => Scenes.decodePack(pack);

  /// 校验 pack 是否合法（不抛错场景的快速判定）。
  static bool isValidPack(String pack) {
    try {
      Scenes.decodePack(pack);
      return true;
    } catch (_) {
      return false;
    }
  }
}