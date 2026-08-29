/// 存储占用统计（cl54-G6）：扫描应用各目录占用空间，供设置-关于-存储展示。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import '../core/paths.dart';

/// 单个目录/文件占用。
class StorageUsageEntry {
  const StorageUsageEntry({required this.label, required this.bytes});

  final String label;
  final int bytes;

  /// 可读体积（B/KB/MB/GB）。
  String get human => _human(bytes);
}

/// 应用存储占用汇总。
class StorageUsage {
  const StorageUsage({required this.entries, required this.totalBytes});

  final List<StorageUsageEntry> entries;
  final int totalBytes;

  String get totalHuman => _human(totalBytes);
}

String _human(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final double kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final double mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

/// 递归统计目录大小（含子目录与文件）。
Future<int> _dirSize(Directory dir) async {
  int total = 0;
  try {
    await for (final FileSystemEntity e in dir.list(recursive: true)) {
      try {
        if (e is File) total += await e.length();
      } catch (_) {}
    }
  } catch (_) {}
  return total;
}

/// 统计应用占用空间。
///
/// - 文档目录：数据库 / 场景包 / 封面缓存等
/// - 支持目录：日志 / 音频分析缓存等
/// - 临时目录：临时文件
Future<StorageUsage> collectStorageUsage() async {
  final Directory docs = await appDataDir();
  final Directory support = await getApplicationSupportDirectory();
  final Directory temp = await getTemporaryDirectory();

  final List<StorageUsageEntry> entries = <StorageUsageEntry>[];
  int total = 0;

  Future<void> add(String label, Directory dir) async {
    final int bytes = await _dirSize(dir);
    entries.add(StorageUsageEntry(label: label, bytes: bytes));
    total += bytes;
  }

  await add('应用数据（数据库 / 场景 / 缓存）', docs);
  await add('日志 / 分析缓存', support);
  await add('临时文件', temp);

  return StorageUsage(entries: entries, totalBytes: total);
}
