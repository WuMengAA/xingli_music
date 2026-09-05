/// 用户反馈上报器（配套官方 relay `/api/feedback` → GitHub issue 自动同步）。
///
/// - 结构化反馈：类型 + 快速预设 + 自由文本 + 版本/渠道/系统 + 可选附带日志；
/// - 隐私：仅发送用户主动填写的内容与最近错误/告警摘要（[LogService] 已脱敏）；
/// - 端点：默认官方 relay `kDefaultContentBaseUrl`，也可由调用方覆盖（与日志上报同源）。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../providers/content/content_providers.dart';

/// 一条用户反馈。
class FeedbackPayload {
  const FeedbackPayload({
    required this.type,
    required this.text,
    this.preset = '',
    this.version = '',
    this.channel = '',
    this.os = '',
    this.attachLogs = false,
    this.logs,
  });

  /// 类型：bug | suggestion | performance | ui | other
  final String type;

  /// 快速预设标签（一键选择，可选）。
  final String preset;

  /// 自由文本（必填）。
  final String text;

  /// 客户端版本号（如 0.26.9.5_alpha_cl01）。
  final String version;

  /// 渠道（alpha/beta/...）。
  final String channel;

  /// 操作系统（android/windows/...）。
  final String os;

  /// 是否附带最近错误/告警日志。
  final bool attachLogs;

  /// 附带日志（[LogService.recentIssues] 同构：level/tag/msg）。
  final List<Map<String, String>>? logs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'preset': preset,
        'text': text,
        'version': version,
        'channel': channel,
        'os': os,
        'attachLogs': attachLogs,
        if (logs != null) 'logs': logs,
      };
}

/// 反馈提交结果。
class FeedbackResult {
  const FeedbackResult({required this.ok, this.synced = false, this.error});
  final bool ok;
  final bool synced;
  final String? error;
}

/// 把反馈 POST 到 relay `/api/feedback`。
class FeedbackService {
  FeedbackService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<FeedbackResult> submit(FeedbackPayload p, String endpoint) async {
    final String base =
        endpoint.trim().isEmpty ? kDefaultContentBaseUrl : endpoint.trim();
    try {
      final http.Response res = await _client
          .post(
            Uri.parse('$base/api/feedback'),
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(p.toJson()),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return FeedbackResult(ok: true, synced: true);
      return FeedbackResult(ok: false, error: '服务端返回 ${res.statusCode}');
    } catch (e) {
      return FeedbackResult(ok: false, error: e.toString());
    }
  }

  void dispose() => _client.close();
}
