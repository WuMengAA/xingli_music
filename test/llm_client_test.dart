/// 第三方大模型客户端测试（MockClient 不联网）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:xingli_music/services/llm/llm_client.dart';

const LlmConfig _cfg = LlmConfig(
  baseUrl: 'https://api.openai.com/v1',
  apiKey: 'sk-test',
  model: 'gpt-test',
);

void main() {
  group('LlmClient（OpenAI 兼容）', () {
    test('成功：解析 choices[0].message.content', () async {
      final MockClient mock = MockClient((http.Request req) async {
        expect(req.url.toString(), 'https://api.openai.com/v1/chat/completions');
        expect(req.headers['Authorization'], 'Bearer sk-test');
        final Map<String, dynamic> body =
            jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['model'], 'gpt-test');
        expect((body['messages'] as List).length, 2);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <dynamic>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': '  你好  '},
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final LlmClient client = LlmClient(client: mock);
      addTearDown(client.dispose);

      final String reply = await client.chat(
        config: _cfg,
        messages: const <LlmMessage>[
          LlmMessage(role: 'system', content: 'sys'),
          LlmMessage(role: 'user', content: 'hi'),
        ],
      );
      expect(reply, '你好'); // 已 trim
    });

    test('baseUrl 尾斜杠被规整', () async {
      final MockClient mock = MockClient((http.Request req) async {
        expect(req.url.toString(), 'http://x/v1/chat/completions');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <dynamic>[
              <String, dynamic>{'message': <String, dynamic>{'content': 'ok'}},
            ],
          }),
          200,
        );
      });
      final LlmClient client = LlmClient(client: mock);
      addTearDown(client.dispose);
      await client.chat(
        config: const LlmConfig(
            baseUrl: 'http://x/v1/', apiKey: 'k', model: 'm'),
        messages: const <LlmMessage>[
          LlmMessage(role: 'user', content: 'hi'),
        ],
      );
    });

    test('HTTP 非 200 → LlmException', () async {
      final MockClient mock =
          MockClient((http.Request req) async => http.Response('denied', 401));
      final LlmClient client = LlmClient(client: mock);
      addTearDown(client.dispose);
      expect(
        () => client.chat(
          config: _cfg,
          messages: const <LlmMessage>[LlmMessage(role: 'user', content: 'x')],
        ),
        throwsA(isA<LlmException>()),
      );
    });

    test('choices 缺失 / 内容为空 → LlmException', () async {
      final MockClient mock = MockClient((http.Request req) async {
        return http.Response(jsonEncode(<String, dynamic>{'choices': <dynamic>[]}), 200);
      });
      final LlmClient client = LlmClient(client: mock);
      addTearDown(client.dispose);
      expect(
        () => client.chat(
          config: _cfg,
          messages: const <LlmMessage>[LlmMessage(role: 'user', content: 'x')],
        ),
        throwsA(isA<LlmException>()),
      );
    });

    test('配置不完整 → LlmException（不发请求）', () async {
      final MockClient mock =
          MockClient((http.Request req) async => http.Response('unused', 200));
      final LlmClient client = LlmClient(client: mock);
      addTearDown(client.dispose);
      expect(
        () => client.chat(
          config: const LlmConfig(baseUrl: '', apiKey: '', model: ''),
          messages: const <LlmMessage>[LlmMessage(role: 'user', content: 'x')],
        ),
        throwsA(isA<LlmException>()),
      );
    });
  });
}
