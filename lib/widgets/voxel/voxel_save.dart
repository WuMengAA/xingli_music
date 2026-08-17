/// ════════════════════════════════════════════════════════════════════════
/// 体素世界自动存档（R24d）
///
/// 定时 30s 周期落盘 + 进出世界时落盘，把"所有东西"持久化到本地 JSON：
/// 世界编辑层 / 发光方块 / 相机机位 / 视角模式 / 第一人称坐标 / 体素小人位置 /
/// 生存数值 / 背包。文件位于**应用支持目录**（getApplicationSupportDirectory，
/// 即 AppData/Roaming 等，**不再写入用户「文档」目录**）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';
import 'dart:convert' show JsonDecoder, JsonEncoder;
import 'dart:io' show Directory, File, FileSystemEntity, Platform;

import 'package:path_provider/path_provider.dart';

import 'voxel_world.dart';

const String _kVoxelSaveFile = 'voxel_world_save.json';

/// 应用私有数据目录：支持目录（不再用文档目录，避免污染「文档」）。
/// 首次调用时把旧文档目录里的存档一次性搬到此处（失败静默）。
Future<Directory> _appDataDir() async {
  final Directory dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  await _migrateFromDocuments(dir);
  return dir;
}

bool _migratedFromDocuments = false;
Future<void> _migrateFromDocuments(Directory target) async {
  if (_migratedFromDocuments) return;
  _migratedFromDocuments = true;
  try {
    final Directory old = await getApplicationDocumentsDirectory();
    if (!await old.exists()) return;
    // 自动存档 + 手动存档 + 备份：voxel_world_save.json / voxel_save_*
    await for (final FileSystemEntity e in old.list()) {
      final String n = e.path.split(Platform.pathSeparator).last;
      if (n == _kVoxelSaveFile || n.startsWith('voxel_save')) {
        try {
          final File dest =
              File('${target.path}${Platform.pathSeparator}$n');
          if (e is File && !await dest.exists()) await e.rename(dest.path);
        } catch (_) {
          // 单文件失败不影响其余
        }
      }
    }
    // 旧截图目录（若有）整体搬入支持目录
    final Directory oldCap =
        Directory('${old.path}${Platform.pathSeparator}captures');
    if (await oldCap.exists()) {
      final Directory newCap =
          Directory('${target.path}${Platform.pathSeparator}captures');
      await newCap.create(recursive: true);
      await for (final FileSystemEntity e in oldCap.list()) {
        try {
          final String n = e.path.split(Platform.pathSeparator).last;
          final File dest =
              File('${newCap.path}${Platform.pathSeparator}$n');
          if (e is File && !await dest.exists()) await e.rename(dest.path);
        } catch (_) {
          // 单文件失败不影响其余
        }
      }
    }
  } catch (_) {
    // 迁移失败静默（不影响后续游玩）
  }
}

Future<File> _voxelSavePath() async {
  final Directory dir = await _appDataDir();
  return File('${dir.path}/$_kVoxelSaveFile');
}

/// 写入完整存档（失败静默，不影响游玩）。
///
/// H3·r21e：同时向「自动备份历史」推一份滚动快照（`voxel_auto_<ts>.json`，
/// 最多 [kMaxAutoBackups]=20 份，超出裁最旧）——游戏菜单「恢复存档」可从
/// 自动/手动备份中任选恢复。
Future<void> writeVoxelSave(Map<String, dynamic> data) async {
  try {
    final File f = await _voxelSavePath();
    await f.writeAsString(const JsonEncoder().convert(data));
    await _pushAutoBackup(data);
  } catch (_) {
    // 磁盘不可写 / 权限不足等：静默放弃本次存档
  }
}

// ─────────────────────────────────────────────────────────────
// H3·r21e 自动备份历史：`voxel_auto_<ts>.json`，滚动保留最近 20 份。
// ─────────────────────────────────────────────────────────────
const String _kAutoPrefix = 'voxel_auto_';
const String _kAutoSuffix = '.json';

/// 自动备份最大保留份数。
const int kMaxAutoBackups = 20;

/// 单存档备份（游戏内 / 手动）最大保留份数，超出自动裁剪最旧。
const int kMaxManualBackupsPerSave = 30;

/// 自动备份元数据（恢复选择列表展示）。
class VoxelAutoBackupMeta {
  const VoxelAutoBackupMeta({required this.ts, required this.createdAt});

  /// 文件名时间戳段（radix36 毫秒）。
  final String ts;

  final DateTime createdAt;
}

/// 推一份自动备份快照，并裁剪到最多 [kMaxAutoBackups] 份。
Future<void> _pushAutoBackup(Map<String, dynamic> data) async {
  try {
    final Directory d = await _appDataDir();
    final String ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final Map<String, dynamic> copy = Map<String, dynamic>.from(data);
    copy['_meta'] = <String, dynamic>{
      'name': '自动备份',
      'createdAt': DateTime.now().toIso8601String(),
      'kind': 'auto',
    };
    await File('${d.path}${Platform.pathSeparator}$_kAutoPrefix$ts$_kAutoSuffix')
        .writeAsString(const JsonEncoder().convert(copy));
    // 裁剪：ts 为 radix36 毫秒 → 字典序即时间序，删最旧。
    final List<File> autos = <File>[];
    await for (final FileSystemEntity e in d.list()) {
      final String n = e.path.split(Platform.pathSeparator).last;
      if (n.startsWith(_kAutoPrefix) && n.endsWith(_kAutoSuffix)) {
        autos.add(File(e.path));
      }
    }
    autos.sort((File a, File b) => a.path.compareTo(b.path));
    while (autos.length > kMaxAutoBackups) {
      await autos.removeAt(0).delete();
    }
  } catch (_) {
    // 历史失败静默，不影响主存档
  }
}

/// 列出自动备份（按时间倒序，最多 [kMaxAutoBackups] 份）；损坏跳过。
Future<List<VoxelAutoBackupMeta>> listAutoBackups() async {
  final Directory d = await _appDataDir();
  if (!await d.exists()) return <VoxelAutoBackupMeta>[];
  final List<VoxelAutoBackupMeta> metas = <VoxelAutoBackupMeta>[];
  await for (final FileSystemEntity e in d.list()) {
    final String n = e.path.split(Platform.pathSeparator).last;
    if (!n.startsWith(_kAutoPrefix) || !n.endsWith(_kAutoSuffix)) continue;
    final String ts = n.substring(
      _kAutoPrefix.length,
      n.length - _kAutoSuffix.length,
    );
    try {
      final dynamic parsed =
          const JsonDecoder().convert(await File(e.path).readAsString());
      if (parsed is! Map<String, dynamic>) continue;
      final dynamic m = parsed['_meta'];
      final DateTime createdAt =
          (m is Map && m['createdAt'] is String &&
                  DateTime.tryParse(m['createdAt'] as String) != null)
              ? DateTime.parse(m['createdAt'] as String)
              : DateTime.fromMillisecondsSinceEpoch(
                  int.tryParse(ts, radix: 36) ?? 0,
                );
      metas.add(VoxelAutoBackupMeta(ts: ts, createdAt: createdAt));
    } catch (_) {
      // 损坏跳过
    }
  }
  metas.sort((VoxelAutoBackupMeta a, VoxelAutoBackupMeta b) =>
      b.createdAt.compareTo(a.createdAt));
  return metas;
}

/// 读取指定自动备份；不存在 / 损坏返回 null。
Future<Map<String, dynamic>?> readAutoBackup(String ts) async {
  try {
    final Directory d = await _appDataDir();
    final File f = File(
      '${d.path}${Platform.pathSeparator}$_kAutoPrefix$ts$_kAutoSuffix',
    );
    if (!await f.exists()) return null;
    final dynamic parsed = const JsonDecoder().convert(await f.readAsString());
    if (parsed is Map<String, dynamic>) return parsed;
  } catch (_) {
    // 损坏忽略
  }
  return null;
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
    this.lastSavedAt,
    this.background,
    this.thumbnail,
  });

  /// 存档标识（文件名 voxel_save_<id>.json）。
  final String id;

  /// 用户命名（无命名时回退「存档 <时间>」）。
  final String name;

  final DateTime createdAt;

  /// R27：最近一次保存时间（创建 / 备份 / 游戏中保存时刷新）。null = 未知。
  final DateTime? lastSavedAt;

  /// cl29·③：存档背景图（场景截图 PNG 的绝对路径，见 captures/ 目录）。
  /// 非空时存档卡用该图作背景；null = 用默认表面色。
  final String? background;

  /// R26skel：存档缩略图（1:1 128×128 PNG 的绝对路径，见 captures/ 目录）。
  /// 非空时存档卡前置显示缩略图；null = 用图标占位。
  final String? thumbnail;
}

Future<Directory> _voxelDir() async => _appDataDir();

Future<String> _manualPath(String id) async {
  final Directory d = await _voxelDir();
  return '${d.path}${Platform.pathSeparator}$_kManualPrefix$id$_kManualSuffix';
}

/// 新建手动存档：把 [name] 写入 `_meta` 元数据，返回存档 id。
Future<String> writeManualSave(Map<String, dynamic> data, String name) async {
  final String id =
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
          '_${(DateTime.now().microsecondsSinceEpoch & 0xffff).toRadixString(16)}';
  final String nowIso = DateTime.now().toIso8601String();
  data['_meta'] = <String, dynamic>{
    'id': id,
    'name': name,
    'createdAt': nowIso,
    'lastSavedAt': nowIso,
  };
  final File f = File(await _manualPath(id));
  await f.writeAsString(const JsonEncoder().convert(data));
  return id;
}

/// R27：刷新某手动存档的「最近保存时间」（游戏中保存时调用，使存档列表显示最新时间）。
///
/// 直接读取该存档文件、仅更新 `_meta.lastSavedAt` 后回写，不动世界数据本身。
Future<void> touchManualSaveLastSaved(String id) async {
  try {
    final File f = File(await _manualPath(id));
    if (!await f.exists()) return;
    final String raw = await f.readAsString();
    final dynamic parsed = const JsonDecoder().convert(raw);
    if (parsed is! Map<String, dynamic>) return;
    final dynamic m = parsed['_meta'];
    if (m is Map) {
      m['lastSavedAt'] = DateTime.now().toIso8601String();
    } else {
      parsed['_meta'] = <String, dynamic>{
        'lastSavedAt': DateTime.now().toIso8601String(),
      };
    }
    await f.writeAsString(const JsonEncoder().convert(parsed));
  } catch (_) {
    // 忽略：刷新失败不影响存档主体
  }
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
      final String? background =
          (m is Map && m['background'] is String) ? m['background'] as String : null;
      final String? thumbnail =
          (m is Map && m['thumbnail'] is String) ? m['thumbnail'] as String : null;
      final DateTime? lastSavedAt =
          (m is Map && m['lastSavedAt'] is String &&
                  DateTime.tryParse(m['lastSavedAt'] as String) != null)
              ? DateTime.parse(m['lastSavedAt'] as String)
              : null;
      metas.add(VoxelManualSaveMeta(
        id: id,
        name: name,
        createdAt: createdAt,
        lastSavedAt: lastSavedAt,
        background: background,
        thumbnail: thumbnail,
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

/// cl29·③：设置 / 清除某存档的背景图路径（写入 `_meta.background` 并回写）。
/// [path] 为 null 时清除背景。
Future<void> setSaveBackground(String id, String? path) async {
  try {
    final File f = File(await _manualPath(id));
    if (!await f.exists()) return;
    final dynamic parsed = const JsonDecoder().convert(await f.readAsString());
    if (parsed is! Map<String, dynamic>) return;
    final dynamic m = parsed['_meta'];
    final Map<String, dynamic> meta = m is Map<String, dynamic>
        ? Map<String, dynamic>.from(m)
        : <String, dynamic>{};
    if (path == null) {
      meta.remove('background');
    } else {
      meta['background'] = path;
    }
    parsed['_meta'] = meta;
    await f.writeAsString(const JsonEncoder().convert(parsed));
  } catch (_) {
    // 忽略
  }
}

/// R26skel：设置 / 清除某存档的缩略图路径（写入 `_meta.thumbnail` 并回写）。
/// [path] 为 null 时清除缩略图。缩略图为 1:1 128×128 PNG 的绝对路径。
Future<void> setSaveThumbnail(String id, String? path) async {
  try {
    final File f = File(await _manualPath(id));
    if (!await f.exists()) return;
    final dynamic parsed = const JsonDecoder().convert(await f.readAsString());
    if (parsed is! Map<String, dynamic>) return;
    final dynamic m = parsed['_meta'];
    final Map<String, dynamic> meta = m is Map<String, dynamic>
        ? Map<String, dynamic>.from(m)
        : <String, dynamic>{};
    if (path == null) {
      meta.remove('thumbnail');
    } else {
      meta['thumbnail'] = path;
    }
    parsed['_meta'] = meta;
    await f.writeAsString(const JsonEncoder().convert(parsed));
  } catch (_) {
    // 忽略
  }
}

// ─────────────────────────────────────────────────────────────
// R26p 存档增强：同一存档「多个自动备份」+ 导出分享 + 导入 + 新建空白世界。
// 备份文件命名：`voxel_save_<id>_bak_<ts>.json`，元数据 parent=id、ts=时间戳，
// 列表时按创建时间倒序；恢复时与手动存档走完全相同的 _applySaveData 路径。
// ─────────────────────────────────────────────────────────────

/// 备份文件路径（同一存档的多个时间戳快照）。
Future<String> _bakPath(String id, String ts) async {
  final Directory d = await _voxelDir();
  return '${d.path}${Platform.pathSeparator}voxel_save_${id}_bak_${ts}.json';
}

/// 列出某存档的全部备份（按创建时间倒序）；损坏文件跳过。
Future<List<VoxelManualSaveMeta>> listBackups(String id) async {
  final Directory d = await _voxelDir();
  if (!await d.exists()) return <VoxelManualSaveMeta>[];
  final String pre = '${_kManualPrefix}${id}_bak';
  final List<VoxelManualSaveMeta> metas = <VoxelManualSaveMeta>[];
  await for (final FileSystemEntity e in d.list()) {
    final String n = e.path.split(Platform.pathSeparator).last;
    if (!n.startsWith(pre) || !n.endsWith(_kManualSuffix)) continue;
    final String ts = n.substring(pre.length, n.length - _kManualSuffix.length);
    try {
      final String raw = await File(e.path).readAsString();
      final dynamic parsed = const JsonDecoder().convert(raw);
      if (parsed is! Map<String, dynamic>) continue;
      final dynamic m = parsed['_meta'];
      final String name = (m is Map && m['name'] is String)
          ? m['name'] as String
          : '备份';
      final DateTime createdAt =
          (m is Map && m['createdAt'] is String &&
                  DateTime.tryParse(m['createdAt'] as String) != null)
              ? DateTime.parse(m['createdAt'] as String)
              : DateTime.fromMillisecondsSinceEpoch(
                  int.tryParse(ts, radix: 36) ?? 0,
                );
      // meta.id 编码为 "<存档id>|<时间戳>"，便于管理器拆分定位。
      metas.add(VoxelManualSaveMeta(
        id: '$id|$ts',
        name: name,
        createdAt: createdAt,
      ));
    } catch (_) {
      // 损坏备份跳过
    }
  }
  metas.sort((VoxelManualSaveMeta a, VoxelManualSaveMeta b) =>
      b.createdAt.compareTo(a.createdAt));
  return metas;
}

/// 把「当前正在游玩的世界」（自动存档）快照为一个备份，挂到 [id] 存档下。
/// 自动存档为空时回退用该存档自身数据；两者皆空则不产生备份。
Future<String?> createBackup(String id) async {
  final Map<String, dynamic>? current = await readVoxelSave();
  final Map<String, dynamic> data =
      current ?? await readManualSave(id) ?? <String, dynamic>{};
  if (data.isEmpty) return null;
  final Map<String, dynamic>? main = await readManualSave(id);
  final String baseName =
      (main?['_meta'] is Map && main!['_meta']['name'] is String)
          ? main['_meta']['name'] as String
          : '存档';
  final String ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  data['_meta'] = <String, dynamic>{
    'name': '$baseName · 备份',
    'createdAt': DateTime.now().toIso8601String(),
    'parent': id,
    'ts': ts,
  };
  final File f = File(await _bakPath(id, ts));
  await f.writeAsString(const JsonEncoder().convert(data));
  await _trimBackups(id);
  return ts;
}

/// 单存档备份超出 [kMaxManualBackupsPerSave] 时裁剪最旧（列表倒序，尾部最旧）。
Future<void> _trimBackups(String id) async {
  try {
    final List<VoxelManualSaveMeta> baks = await listBackups(id);
    if (baks.length <= kMaxManualBackupsPerSave) return;
    final List<VoxelManualSaveMeta> old =
        baks.sublist(kMaxManualBackupsPerSave);
    for (final VoxelManualSaveMeta b in old) {
      final List<String> p = b.id.split('|');
      if (p.length == 2) await deleteBackup(p[0], p[1]);
    }
  } catch (_) {
    // 裁剪失败静默，不影响主备份
  }
}

/// 读取指定备份；不存在 / 损坏返回 null。
Future<Map<String, dynamic>?> readBackup(String id, String ts) async {
  try {
    final File f = File(await _bakPath(id, ts));
    if (!await f.exists()) return null;
    final dynamic parsed = const JsonDecoder().convert(await f.readAsString());
    if (parsed is Map<String, dynamic>) return parsed;
  } catch (_) {
    // 损坏忽略
  }
  return null;
}

/// 删除指定备份。
Future<void> deleteBackup(String id, String ts) async {
  try {
    final File f = File(await _bakPath(id, ts));
    if (await f.exists()) await f.delete();
  } catch (_) {
    // 忽略
  }
}

/// 删除存档及其全部备份（一键清理）。
Future<void> deleteSaveWithBackups(String id) async {
  await deleteManualSave(id);
  final List<VoxelManualSaveMeta> baks = await listBackups(id);
  for (final VoxelManualSaveMeta b in baks) {
    final List<String> parts = b.id.split('|');
    if (parts.length == 2) await deleteBackup(parts[0], parts[1]);
  }
}

/// 导出用：返回存档文件（供分享 / 复制）。
Future<File> manualSaveFile(String id) async => File(await _manualPath(id));

/// 导出用：返回备份文件。
Future<File> backupFile(String id, String ts) async =>
    File(await _bakPath(id, ts));

/// 从外部文件导入为新的手动存档（保留源命名；文件损坏返回 null）。
Future<String?> importSave(File source) async {
  final String raw;
  try {
    raw = await source.readAsString();
  } catch (_) {
    return null;
  }
  dynamic parsed;
  try {
    parsed = const JsonDecoder().convert(raw);
  } catch (_) {
    parsed = null;
  }
  if (parsed is! Map<String, dynamic>) return null;
  final Map<String, dynamic> data = Map<String, dynamic>.from(parsed);
  final dynamic m = data['_meta'];
  final String name = (m is Map && m['name'] is String)
      ? m['name'] as String
      : '导入的存档';
  data['_meta'] = <String, dynamic>{
    'name': name,
    'createdAt': DateTime.now().toIso8601String(),
  };
  final String id =
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
          '_${(DateTime.now().microsecondsSinceEpoch & 0xffff).toRadixString(16)}';
  final File f = File(await _manualPath(id));
  await f.writeAsString(const JsonEncoder().convert(data));
  return id;
}

/// 生成一份全新的空白世界存档数据（仅含种子化地形，生存/背包/机位走默认值）。
/// 用于「新建空白世界」：管理器无活动世界实例，直接由模型构造最小合法存档。
/// [options] 为 cl29 新增的「新建世界选项」（作弊 / 结构 / 浮空岛等）。
Map<String, dynamic> freshWorldSave(int seed, [WorldOptions? options]) {
  final VoxelWorld w = VoxelWorld(seed: seed, options: options ?? const WorldOptions());
  return <String, dynamic>{
    'v': 1,
    'savedAt': DateTime.now().millisecondsSinceEpoch,
    'world': w.toJson(),
  };
}
