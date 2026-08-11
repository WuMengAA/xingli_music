/// 云端日志上报器 —— 配套自建服务端 `tools/log_server/server.js`。
///
/// - 缓冲批量上报：攒够 [kBatchSize] 条立即发，或每 [kInterval] 自动 flush；
/// - 失败重试：网络失败把批次放回缓冲头，下轮再试；缓冲超 [kMaxBuffer] 丢最旧；
/// - 服务端拒绝（HTTP 非 200）：丢弃该批，避免无限重试同一批；
/// - 隐私：只上报 LogService **已脱敏**（[LogService.redact]）的文本；
/// - 默认关闭：开关打开且地址非空才生效（`isActive`）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 一条待上报日志（字段与服务端 JSONL 对齐）。
class RemoteLogEntry {
  const RemoteLogEntry({
    required this.ts,
    required this.level,
    required this.tag,
    required this.msg,
  });

  final String ts;
  final String level;
  final String tag;
  final String msg;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ts': ts,
        'level': level,
        'tag': tag,
        'msg': msg,
      };
}

/// 批量上报器。单例由 Riverpod 层持有（见 log_upload_providers.dart）。
class RemoteLogUploader {
  RemoteLogUploader({
    http.Client? client,
    String? endpoint,
    bool enabled = false,
    this.healthSummary,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null {
    _endpoint = _normalize(endpoint);
    _enabled = enabled;
    _sync();
  }

  /// 健康摘要回调（由 [LogService.healthSummary] 提供）：每次 flush 时
  /// 自动附一条 `SUMMARY/health`，服务端一眼可见错误/告警计数与最近异常。
  final String Function()? healthSummary;

  /// 批量阈值：攒够这么多条立即上报。
  static const int kBatchSize = 20;

  /// 缓冲上限：超出丢最旧（防止异常场景内存膨胀）。
  static const int kMaxBuffer = 200;

  /// 自动 flush 间隔。
  static const Duration kInterval = Duration(seconds: 5);

  /// 单次上报超时。
  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;
  final bool _ownsClient;

  String? _endpoint;
  String? get endpoint => _endpoint;

  bool _enabled = false;
  bool get enabled => _enabled;

  /// 开关打开且地址已配置。
  bool get isActive => _enabled && _endpoint != null && _endpoint!.isNotEmpty;

  final List<RemoteLogEntry> _buffer = <RemoteLogEntry>[];
  Timer? _timer;

  static String? _normalize(String? url) {
    final String? t =
        (url == null || url.trim().isEmpty) ? null : url.trim();
    if (t == null) return null;
    // 去掉结尾斜杠，避免拼出 //api/logs
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  /// 设置服务端地址（空 = 清除）。
  void setEndpoint(String? url) {
    _endpoint = _normalize(url);
    _sync();
  }

  /// 启用 / 停用上报。
  void setEnabled(bool on) {
    _enabled = on;
    _sync();
  }

  void _sync() {
    if (isActive) {
      _timer ??= Timer.periodic(kInterval, (_) => unawaited(flush()));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// 入队一条（调用方保证文本已脱敏）。
  void push(RemoteLogEntry entry) {
    if (!isActive) return;
    _buffer.add(entry);
    if (_buffer.length > kMaxBuffer) {
      _buffer.removeRange(0, _buffer.length - kMaxBuffer);
    }
    if (_buffer.length >= kBatchSize) {
      unawaited(flush());
    }
  }

  /// 立即上报缓冲内容。
  ///
  /// 返回成功条数；0 = 未启用/无待上报；-1 = 失败（已放回缓冲待重试，
  /// 或服务端拒绝已丢弃）。上报批次头部会自动附一条 `SUMMARY/health`
  /// 健康快照（错误/告警计数 + 最近异常），便于云端一眼定位问题。
  Future<int> flush() async {
    if (!isActive || _buffer.isEmpty) return 0;
    final List<RemoteLogEntry> batch = List<RemoteLogEntry>.from(_buffer);
    _buffer.clear();
    // 自动识别异常：批次前插健康快照（服务端查看器按 tag=health 高亮）。
    final String Function()? hs = healthSummary;
    if (hs != null) {
      final DateTime now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final String ts = '${now.year}-${two(now.month)}-${two(now.day)} '
          '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
      batch.insert(
        0,
        RemoteLogEntry(ts: ts, level: 'SUMMARY', tag: 'health', msg: hs()),
      );
    }
    try {
      final http.Response res = await _client
          .post(
            Uri.parse('$_endpoint/api/logs'),
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(batch.map((e) => e.toJson()).toList()),
          )
          .timeout(_timeout);
      if (res.statusCode == 200) return batch.length;
      return -1; // 服务端拒绝：丢弃该批
    } catch (_) {
      // 网络失败：放回缓冲头，稍后重试
      _buffer.insertAll(0, batch);
      if (_buffer.length > kMaxBuffer) {
        _buffer.removeRange(0, _buffer.length - kMaxBuffer);
      }
      return -1;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_ownsClient) _client.close();
  }
}
