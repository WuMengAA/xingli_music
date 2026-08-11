import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 全局自动日志工具：把应用关键事件写入本地日志文件。
///
/// - 文件：`<应用支持目录>/logs/app.log`，UTF-8 追加写入
/// - 每行：`[时间] [级别] [分类] 消息`
/// - 启动时自动清理超过 [kMaxKeepDays] 的旧日志文件
/// - 同时输出到控制台（debugPrint），方便开发调试
class LogService {
  LogService._();

  static final LogService _instance = LogService._();
  static LogService get instance => _instance;

  /// 日志保留天数
  static const int kMaxKeepDays = 7;

  File? _file;
  IOSink? _sink;
  bool _ready = false;
  Timer? _flushTimer;

  /// 初始化（App 启动时调用）：打开日志文件、清理旧日志
  Future<void> init() async {
    if (_ready) return;
    try {
      final Directory dir = await getApplicationSupportDirectory();
      final Directory logsDir = Directory('${dir.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }
      _file = File('${logsDir.path}/app.log');
      await _cleanOldLogs(logsDir);
      // 打开一个长生命周期写入流，避免每条日志都开关文件句柄 + flush（高频日志下磁盘 IO 爆炸）
      _sink = _file!.openWrite(mode: FileMode.append);
      // 定时 flush，保证异常退出时也不会丢失超过 1 秒的日志
      _flushTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_flush()),
      );
      _ready = true;
      i('log', '日志系统已初始化：${_file?.path}');
    } catch (e) {
      // 日志初始化失败不阻塞应用（降级为纯控制台）
      debugPrint('[log] 日志初始化失败: $e');
      _ready = false;
    }
  }

  /// 释放资源：取消定时 flush，flush 剩余缓冲并关闭写入流
  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {
      // 忽略
    }
    _sink = null;
  }

  /// 清理超过保留天数的旧日志文件
  Future<void> _cleanOldLogs(Directory dir) async {
    try {
      await for (final FileSystemEntity e in dir.list()) {
        if (e is! File) continue;
        final String name = e.uri.pathSegments.last;
        if (!name.endsWith('.log')) continue;
        // 支持 app.log 和 app.YYYYMMDD.log 这类滚动文件
        final DateTime? t = _fileDate(name);
        if (t != null &&
            DateTime.now().difference(t) >
                const Duration(days: kMaxKeepDays)) {
          await e.delete();
        }
      }
    } catch (_) {
      // 清理失败忽略
    }
  }

  DateTime? _fileDate(String name) {
    final RegExp re = RegExp(r'app\.(\d{8})\.log');
    final Match? m = re.firstMatch(name);
    if (m == null) return null;
    try {
      return DateTime.parse(m.group(1)!);
    } catch (_) {
      return null;
    }
  }

  /// 信息日志
  void i(String tag, String message) => _log('INFO', tag, message);

  /// 告警日志
  void w(String tag, String message) => _log('WARN', tag, message);

  /// 错误日志
  void e(String tag, String message) => _log('ERROR', tag, message);

  void _log(String level, String tag, String message) {
    final String line =
        '[${_ts()}] [$level] [$tag] $message';

    debugPrint(line);

    // 直接写入长生命周期缓冲流（不阻塞 UI，由定时 flush 落盘）
    if (_ready && _sink != null) {
      _sink!.write('$line\n');
    }
  }

  /// 将缓冲流中的日志刷入磁盘（周期性调用，异常退出时最多丢 1 秒）
  Future<void> _flush() async {
    try {
      await _sink?.flush();
    } catch (_) {
      // flush 失败忽略
    }
  }

  String _ts() {
    final DateTime n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} '
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }
}
