/// ════════════════════════════════════════════════════════════════════════
/// 体素世界自动存档（R24d）
///
/// 定时 30s 周期落盘 + 进出世界时落盘，把"所有东西"持久化到本地 JSON：
/// 世界编辑层 / 发光方块 / 相机机位 / 视角模式 / 第一人称坐标 / 体素小人位置 /
/// 生存数值 / 背包。文件位于应用文档目录 `voxel_world_save.json`。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';
import 'dart:convert' show JsonDecoder, JsonEncoder;
import 'dart:io' show Directory, File;

import 'package:path_provider/path_provider.dart';

const String _kVoxelSaveFile = 'voxel_world_save.json';

Future<File> _voxelSavePath() async {
  final Directory dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/$_kVoxelSaveFile');
}

/// 写入完整存档（失败静默，不影响游玩）。
Future<void> writeVoxelSave(Map<String, dynamic> data) async {
  try {
    final File f = await _voxelSavePath();
    await f.writeAsString(const JsonEncoder().convert(data));
  } catch (_) {
    // 磁盘不可写 / 权限不足等：静默放弃本次存档
  }
}

/// 读取完整存档；无存档或文件损坏返回 null。
Future<Map<String, dynamic>?> readVoxelSave() async {
  try {
    final File f = await _voxelSavePath();
    if (!await f.exists()) return null;
    final String raw = await f.readAsString();
    final dynamic parsed = const JsonDecoder().convert(raw);
    if (parsed is Map<String, dynamic>) return parsed;
  } catch (_) {
    // 损坏存档：忽略，下次存档覆盖
  }
  return null;
}

/// 清除存档（可选：重开新世界时调用）。
Future<void> deleteVoxelSave() async {
  try {
    final File f = await _voxelSavePath();
    if (await f.exists()) await f.delete();
  } catch (_) {
    // 忽略
  }
}
