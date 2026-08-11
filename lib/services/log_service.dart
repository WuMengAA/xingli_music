import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'remote_log_uploader.dart';

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

  /// 云端日志上报器（可选）。由 Riverpod 层挂载；null = 不上报。
  RemoteLogUploader? remote;

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

  /// 调试日志（受 [debugEnabled] 控制，默认开；设置→日志上报可关）。
  void d(String tag, String message) {
    if (!debugEnabled) return;
    _log('DEBUG', tag, message);
  }

  /// 告警日志
  void w(String tag, String message) => _log('WARN', tag, message);

  /// 错误日志；可选携带堆栈（全局崩溃捕获等场景，让云端日志可定位）。
  void e(String tag, String message, [StackTrace? stack]) {
    final String full = stack == null ? message : '$message\n$stack';
    _log('ERROR', tag, full);
  }

  /// 是否记录 DEBUG 级日志（默认开；UI 层可关，持久化见 SettingsRepository）。
  static bool debugEnabled = true;

  /// 异常/告警摘要窗口大小（只保留最近 N 条，供健康快照）。
  static const int kMaxRecentIssues = 20;

  /// 最近的非正常日志（ERROR/WARN，新→旧），用于「自动识别异常」健康快照。
  final List<Map<String, String>> _recentIssues = <Map<String, String>>[];

  /// 最近非正常日志（新→旧，只读）。
  List<Map<String, String>> get recentIssues =>
      List<Map<String, String>>.unmodifiable(_recentIssues);

  /// 健康摘要（供上传器随批次附一条 `SUMMARY/health`）：错误/告警计数 + 最近 3 条。
  String get healthSummary {
    final int errors =
        _recentIssues.where((Map<String, String> e) => e['level'] == 'ERROR').length;
    final int warns = _recentIssues.length - errors;
    final List<String> top = _recentIssues
        .take(3)
        .map((Map<String, String> e) => '[${e['tag']}] ${e['msg']}')
        .toList();
    return 'errors=$errors warns=$warns | ${top.join(' || ')}';
  }

  void _log(String level, String tag, String message) {
    // P-1：写盘/打印前统一脱敏。调用方即使漏了 _redact（尤其是
    // `catch (e)` 里异常文本内嵌的完整 URL），也不会把凭据落进 app.log。
    final String ts = _ts();
    final String safe = redact(message);
    final String line = '[$ts] [$level] [$tag] $safe';

    // 自动识别非正常情况：ERROR/WARN 进摘要窗口（供云端健康快照）。
    if (level == 'ERROR' || level == 'WARN') {
      _recentIssues.insert(
        0,
        <String, String>{'level': level, 'tag': tag, 'msg': _clip(safe)},
      );
      if (_recentIssues.length > kMaxRecentIssues) {
        _recentIssues.removeRange(kMaxRecentIssues, _recentIssues.length);
      }
    }

    debugPrint(line);

    // 直接写入长生命周期缓冲流（不阻塞 UI，由定时 flush 落盘）
    if (_ready && _sink != null) {
      _sink!.write('$line\n');
    }

    // 云端上报（若已配置）：同样只发脱敏文本，与本地落盘同一来源。
    remote?.push(RemoteLogEntry(ts: ts, level: level, tag: tag, msg: safe));
  }

  /// 摘要里只留前 200 字，避免一条超长错误把快照撑爆。
  static String _clip(String s) =>
      s.length <= 200 ? s : '${s.substring(0, 200)}…';

  // ── 日志脱敏兜底层（P-1）──────────────────────────
  //
  // app.log 是明文文件、保留 7 天，任何进入这里的凭据都等同于长期泄漏。
  // 调用点的精确脱敏（如 AudioService._redact）是第一道防线，本层是
  // 第二道：对最终文本做模式扫描，覆盖异常消息等无法逐一改造的来源。

  /// URL 的 query / fragment 整体剥离（凭据几乎都在这里）。
  static final RegExp _reUrlQuery =
      RegExp(r'([a-zA-Z][a-zA-Z0-9+.-]*://[^\s?#]*)[?#]\S*');

  /// 自由文本中的 `key=value` 凭据（URL 之外的场景，如异常消息里的键值对）。
  static final RegExp _reCredKv = RegExp(
    r'\b(token|cookie|password|passwd|pwd|secret|auth|authorization|'
    r'apikey|api_key|access_token|refresh_token|session|sessionid)\s*[=:]\s*'
    r'''([^\s,;&'")\]}]+)''',
    caseSensitive: false,
  );

  /// 各平台用户主目录中的**真实用户名**。
  static final RegExp _reWinUser =
      RegExp(r'([A-Za-z]:[\\/]+Users[\\/]+)[^\\/\s]+');
  static final RegExp _reUnixUser = RegExp(r'(/(?:home|Users)/)[^/\s]+');

  /// 对任意日志文本做脱敏。永不抛异常（日志路径必须绝对安全）。
  ///
  /// 公开是为了让其它模块（非音频域）在拼接敏感字段时也能复用。
  static String redact(String s) {
    if (s.isEmpty) return s;
    try {
      return s
          .replaceAllMapped(_reUrlQuery, (m) => '${m[1]}?<redacted>')
          .replaceAllMapped(_reCredKv, (m) => '${m[1]}=<redacted>')
          .replaceAllMapped(_reWinUser, (m) => '${m[1]}<user>')
          .replaceAllMapped(_reUnixUser, (m) => '${m[1]}<user>');
    } catch (_) {
      return s;
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
