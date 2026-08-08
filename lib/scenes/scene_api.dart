/// 星璃 · 场景系统统一入口
///
/// 把散落在 models/scene.dart、providers/scene/、services/scene_order_service.dart
/// 的能力集中暴露为一份公共 API，便于：
///   - 场景编辑器 (pages/settings/scene_editor_page.dart) 调用
///   - 未来场景分享 / 导入 / 同步
///   - 测试桩注入
///
/// 注意：这里只做门面与轻量编排，不复制状态；状态仍由 Riverpod 提供。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/scene.dart';

export '../models/scene.dart';
export '../services/scene_order_service.dart';
export 'scene_deploy.dart';
export 'scene_packer.dart';

/// 场景模块对外的统一门面。
///
/// 设计原则：
///   - 静态方法为主，避免实例化，便于跨页面复用
///   - 不持有可观察状态（状态走 Riverpod）
///   - 任何"组合操作"都封在这里，让调用方只关心业务
@immutable
class Scenes {
  const Scenes._();

  /// 当前模块版本号（场景包格式升级时递增）。
  static const int packSchemaVersion = 1;

  /// 序列化为可存储/传输的稳定 JSON。
  ///
  /// 直接复用 [Scene.toJson]，仅在包层加 schema 字段。
  /// 不包含运行时派生量（颜色偏移、播放进度）。
  static String encodePack(Scene scene) => jsonEncode({
        'schema': packSchemaVersion,
        'scene': scene.toJson(),
      });

  /// JSON 字符串 → 场景。schema 不匹配抛 [FormatException]。
  static Scene decodePack(String pack) {
    final Map<String, dynamic> root = jsonDecode(pack) as Map<String, dynamic>;
    final int schema = root['schema'] as int? ?? 0;
    if (schema != packSchemaVersion) {
      throw FormatException(
        '场景包 schema=$schema 与当前 $packSchemaVersion 不兼容',
      );
    }
    final dynamic raw = root['scene'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('场景包缺少 scene 字段或格式错误');
    }
    return Scene.fromJson(raw);
  }
}