/// 最小 OpenAI 兼容 Chat Completions 客户端（用户自配第三方大模型）。
///
/// 支持任何 OpenAI 兼容端点（OpenAI / DeepSeek / 各类中转 / 本地 vLLM 等）：
/// 只需 baseUrl + apiKey + model。API Key 不在本类落盘，由上层经
/// [SecureBox] 加密保存，仅运行时持有。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 一条对话消息。
class LlmMessage {
  const LlmMessage({required this.role, required this.content});

  /// `system` / `user` / `assistant`。
  final String role;
  final String content;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role,
        'content': content,
      };
}

/// 大模型连接配置（全部来自用户自配）。
class LlmConfig {
  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  bool get valid => baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;
}

/// 调用失败（消息可直接展示给用户）。
class LlmException implements Exception {
  const LlmException(this.message);

  final String message;

  @override
  String toString() => 'LlmException: $message';
}

/// 聊天补全客户端。
class LlmClient {
  LlmClient({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const Duration _timeout = Duration(seconds: 30);

  /// 一次 chat 补全，返回助手回复文本。
  ///
  /// 失败一律抛 [LlmException]（中文可展示消息）；调用方决定回退模板。
  Future<String> chat({
    required LlmConfig config,
    required List<LlmMessage> messages,
    double temperature = 0.7,
    int maxTokens = 600,
  }) async {
    if (!config.valid) {
      throw const LlmException('大模型配置不完整（地址 / API Key / 模型名）');
    }
    final String base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final Uri uri = Uri.parse('$base/chat/completions');

    final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer ${config.apiKey.trim()}',
            },
            body: jsonEncode(<String, dynamic>{
              'model': config.model.trim(),
              'messages': messages.map((LlmMessage m) => m.toJson()).toList(),
              'temperature': temperature,
              'max_tokens': maxTokens,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const LlmException('请求超时，请检查网络或服务商');
    } catch (_) {
      throw const LlmException('网络请求失败，请检查地址与网络');
    }

    if (res.statusCode != 200) {
      throw LlmException('接口返回 HTTP ${res.statusCode}（检查 Key / 模型名 / 地址）');
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const LlmException('接口返回了非 JSON 内容');
    }
    final List<dynamic>? choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const LlmException('接口未返回任何结果');
    }
    final dynamic first = choices.first;
    final String? content = (first is Map<String, dynamic>)
        ? ((first['message'] as Map<String, dynamic>?)?['content'] as String?)
        : null;
    if (content == null || content.trim().isEmpty) {
      throw const LlmException('模型返回为空');
    }
    return content.trim();
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
