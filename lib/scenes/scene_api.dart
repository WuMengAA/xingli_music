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
import 'dart:math';

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
  ///
  /// v2（2026-08-10）：在分享包中**显式纳入体素世界取景快照** [VoxelSceneCapture]
  /// （seed + 相机机位），使「场景背景用体素世界实时渲染」可被分享 / 导入复现。
  /// v1 的 `toShareJson` 已包含该字段，故 v1 与 v2 的 scene JSON 形状一致，
  /// 仅包外壳版本号不同；[decodePack] 同时接受 v1 / v2 以向前兼容。
  static const int packSchemaVersion = 2;

  /// 当前模块接受的场景包 schema 集合（含历史 v1，向后兼容）。
  static const Set<int> acceptedSchemas = <int>{1, 2};

  /// 自定义场景 id 前缀（`Scene.isCustom` 以此判定；等价于 isBuiltin=false）。
  static const String customIdPrefix = 'custom_';

  /// 序列化为可传输的场景包。
  ///
  /// P-2：走 [Scene.toShareJson] 而非 `toJson` —— 分享包会进剪贴板并发给
  /// 他人，必须先剥离 `soundscapePath` 等本机绝对路径（含真实用户名）。
  /// 本机持久化仍用 `toJson`（见 scene_custom_providers），互不影响。
  /// 不包含运行时派生量（颜色偏移、播放进度）。
  static String encodePack(Scene scene) => jsonEncode({
        'schema': packSchemaVersion,
        'scene': scene.toShareJson(),
      });

  /// JSON 字符串 → 场景。schema 不在 [acceptedSchemas] 抛 [FormatException]。
  ///
  /// P-2 安全加固：场景包来自**不可信来源**（剪贴板/他人转发），因此
  ///   1. **重写 id**：分配本地唯一的 `custom_` id，原 id 仅存入
  ///      [Scene.sourceShareId] 溯源。否则恶意包只要把 id 写成内置场景 id
  ///      （如 `snow`），导入后就会经 `scenesProvider` 的 overrides 映射
  ///      **静默覆盖内置场景**（见 providers/scene/scene_providers.dart）。
  ///   2. **强制 isBuiltin=false**：新 id 带 `custom_` 前缀，`Scene.isCustom`
  ///      为 true，导入内容永远只能作为追加的自定义场景存在。
  ///   3. **清除外来本机路径**：包里若仍带 `soundscapePath` / 本地 `bgmUri`
  ///      （老版本导出或人为构造），一律丢弃 —— 既防隐私回灌，也防把
  ///      本机任意文件路径喂给音频播放器。
  ///
  /// 向前兼容：v1 与 v2 的 scene JSON 形状一致（v2 起 `voxelCapture` 为
  /// 一等公民），故无需字段迁移；若未来 v2 新增可选字段，在此补齐默认值。
  static Scene decodePack(String pack) {
    final Map<String, dynamic> root = jsonDecode(pack) as Map<String, dynamic>;
    final int schema = root['schema'] as int? ?? 0;
    if (!acceptedSchemas.contains(schema)) {
      throw FormatException(
        '场景包 schema=$schema 与当前 $packSchemaVersion 不兼容'
        '（支持 $acceptedSchemas）',
      );
    }
    final dynamic raw = root['scene'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('场景包缺少 scene 字段或格式错误');
    }
    return sanitizeImported(Scene.fromJson(raw));
  }

  /// 把「外来场景」转成可安全落地的本地自定义场景（见 [decodePack] 说明）。
  static Scene sanitizeImported(Scene incoming) => incoming.copyWith(
        id: newCustomSceneId(),
        sourceShareId: incoming.id,
        // 外来路径一律不信任
        clearSoundscapePath: true,
        clearMusicSourceId: Scene.isLocalPathLike(incoming.musicSourceId) ||
            (incoming.musicSourceId?.startsWith('dir:') ?? false),
        clearBgm: Scene.isLocalPathLike(incoming.bgmUri),
      );

  /// 生成本地唯一的自定义场景 id：`custom_<微秒时间戳>_<随机后缀>`。
  ///
  /// 加随机后缀是因为同一微秒内连续导入两个包时时间戳可能相同。
  static String newCustomSceneId() {
    final int micros = DateTime.now().microsecondsSinceEpoch;
    final String suffix =
        Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '$customIdPrefix${micros}_$suffix';
  }
}