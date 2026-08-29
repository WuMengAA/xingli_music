/// ════════════════════════════════════════════════════════════════════════
/// 应用私有数据根目录
/// ════════════════════════════════════════════════════════════════════════
///
/// 取代散落的 `getApplicationDocumentsDirectory()`：
/// Windows 上 path_provider 的 `getApplicationDocumentsDirectory()` 直接返回
/// `C:\Users\<user>\Documents`（无应用子目录），会把数据库/封面/歌词/音效写进
/// 用户"文档"，卸载也不清理，且易触发杀软/同步盘扫描。
///
/// 规则（0.26.8.29 修复「文件塞进用户文档」）：
/// - Windows：优先 `<安装目录>/data`（setup 默认 `C:\Program Files\星璃音乐\data`，
///   inno 已用 `Permissions: users-modify` 放行写权限）；若不可写则降级
///   `AppData\Roaming\com.stelarith\xingli_music`（应用私有，随卸载清理）。
/// - Android / 其它：应用私有 support 目录（不进"文档"，随卸载清理）。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 进程内缓存，避免每次都探测写权限。
Directory? _cachedAppDataDir;

/// 返回应用私有数据根目录（缓存，进程内只算一次）。
Future<Directory> appDataDir() async {
  final Directory? cached = _cachedAppDataDir;
  if (cached != null) return cached;

  Directory dir;
  if (Platform.isWindows) {
    // 安装目录 = 当前可执行文件所在目录（setup 的 {app}）。
    final String installDir = p.dirname(Platform.resolvedExecutable);
    final Directory candidate = Directory(p.join(installDir, 'data'));
    dir = await _isWritable(candidate) ? candidate : await getApplicationSupportDirectory();
  } else {
    dir = await getApplicationSupportDirectory();
  }

  _cachedAppDataDir = dir;
  return dir;
}

/// 探测目录是否可写：不存在则尝试创建，再写探针文件验证。
Future<bool> _isWritable(Directory dir) async {
  try {
    if (!await dir.exists()) await dir.create(recursive: true);
    final File probe = File(p.join(dir.path, '.xingli_write_test'));
    await probe.writeAsString('1');
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  } catch (_) {
    return false;
  }
}
