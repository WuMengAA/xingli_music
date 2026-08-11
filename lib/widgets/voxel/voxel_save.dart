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
import 'dart:io' show Directory, File, FileSystemEntity, Platform;

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

// ─────────────────────────────────────────────────────────────
// R26d 手动存档（多存档 · 可命名）：每个存档一个独立文件
//   `voxel_save_<id>.json`，数据内嵌 `_meta{name,createdAt}` 元数据。
// 自动存档（voxel_world_save.json）继续按 30s 周期运行，两者互不干扰。
// ─────────────────────────────────────────────────────────────
const String _kManualPrefix = 'voxel_save_';
const String _kManualSuffix = '.json';

/// 手动存档元数据（存档菜单列表展示）。
class VoxelManualSaveMeta {
  const VoxelManualSaveMeta({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  /// 存档标识（文件名 voxel_save_<id>.json）。
  final String id;

  /// 用户命名（无命名时回退「存档 <时间>」）。
  final String name;

  final DateTime createdAt;
}

Future<Directory> _voxelDir() async => getApplicationDocumentsDirectory();

Future<String> _manualPath(String id) async {
  final Directory d = await _voxelDir();
  return '${d.path}${Platform.pathSeparator}$_kManualPrefix$id$_kManualSuffix';
}

/// 新建手动存档：把 [name] 写入 `_meta` 元数据，返回存档 id。
Future<String> writeManualSave(Map<String, dynamic> data, String name) async {
  final String id =
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
          '_${(DateTime.now().microsecondsSinceEpoch & 0xffff).toRadixString(16)}';
  data['_meta'] = <String, dynamic>{
    'name': name,
    'createdAt': DateTime.now().toIso8601String(),
  };
  final File f = File(await _manualPath(id));
  await f.writeAsString(const JsonEncoder().convert(data));
  return id;
}

/// 列出全部手动存档（按创建时间倒序）；损坏文件跳过。
Future<List<VoxelManualSaveMeta>> listManualSaves() async {
  final Directory d = await _voxelDir();
  if (!await d.exists()) return <VoxelManualSaveMeta>[];
  final List<VoxelManualSaveMeta> metas = <VoxelManualSaveMeta>[];
  await for (final FileSystemEntity e in d.list()) {
    final String n = e.path.split(Platform.pathSeparator).last;
    if (!n.startsWith(_kManualPrefix) || !n.endsWith(_kManualSuffix)) continue;
    final String id = n.substring(
      _kManualPrefix.length,
      n.length - _kManualSuffix.length,
    );
    try {
      final String raw = await File(e.path).readAsString();
      final dynamic parsed = const JsonDecoder().convert(raw);
      if (parsed is! Map<String, dynamic>) continue;
      final dynamic m = parsed['_meta'];
      final String name = (m is Map && m['name'] is String)
          ? m['name'] as String
          : '存档 ${DateTime.fromMillisecondsSinceEpoch(int.parse(id.split('_').first, radix: 36)).toString().substring(5, 16)}';
      final DateTime createdAt =
          (m is Map && m['createdAt'] is String &&
                  DateTime.tryParse(m['createdAt'] as String) != null)
              ? DateTime.parse(m['createdAt'] as String)
              : DateTime.fromMillisecondsSinceEpoch(
                  int.parse(id.split('_').first, radix: 36),
                );
      metas.add(VoxelManualSaveMeta(
        id: id,
        name: name,
        createdAt: createdAt,
      ));
    } catch (_) {
      // 损坏存档跳过
    }
  }
  metas.sort((VoxelManualSaveMeta a, VoxelManualSaveMeta b) =>
      b.createdAt.compareTo(a.createdAt));
  return metas;
}

/// 读取指定手动存档；不存在 / 损坏返回 null。
Future<Map<String, dynamic>?> readManualSave(String id) async {
  try {
    final File f = File(await _manualPath(id));
    if (!await f.exists()) return null;
    final dynamic parsed = const JsonDecoder().convert(await f.readAsString());
    if (parsed is Map<String, dynamic>) return parsed;
  } catch (_) {
    // 损坏忽略
  }
  return null;
}

/// 删除指定手动存档。
Future<void> deleteManualSave(String id) async {
  try {
    final File f = File(await _manualPath(id));
    if (await f.exists()) await f.delete();
  } catch (_) {
    // 忽略
  }
}

/// 重命名指定手动存档（改 `_meta.name` 写回）。
Future<void> renameManualSave(String id, String name) async {
  try {
    final File f = File(await _manualPath(id));
    if (!await f.exists()) return;
    final dynamic parsed = const JsonDecoder().convert(await f.readAsString());
    if (parsed is! Map<String, dynamic>) return;
    final dynamic m = parsed['_meta'];
    if (m is Map<String, dynamic>) {
      m['name'] = name;
    } else {
      parsed['_meta'] = <String, dynamic>{'name': name};
    }
    await f.writeAsString(const JsonEncoder().convert(parsed));
  } catch (_) {
    // 忽略
  }
}
