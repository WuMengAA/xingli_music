/// 云端日志上报器单测（纯逻辑，MockClient 不联网）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:xingli_music/services/remote_log_uploader.dart';

const RemoteLogEntry _entry = RemoteLogEntry(
  ts: '2026-08-10 22:00:00',
  level: 'INFO',
  tag: 'test',
  msg: 'hello',
);

void main() {
  group('RemoteLogUploader', () {
    test('未启用 → 不上报（flush 返回 0）', () async {
      final RemoteLogUploader u =
          RemoteLogUploader(endpoint: 'http://x', enabled: false);
      addTearDown(u.dispose);
      u.push(_entry);
      expect(await u.flush(), 0);
    });

    test('地址为空 → 不上报', () async {
      final RemoteLogUploader u =
          RemoteLogUploader(endpoint: '', enabled: true);
      addTearDown(u.dispose);
      expect(u.isActive, isFalse);
      u.push(_entry);
      expect(await u.flush(), 0);
    });

    test('成功上报返回条数并清空缓冲', () async {
      final MockClient mock = MockClient((http.Request req) async {
        expect(req.url.toString(), 'http://logs.example.com/api/logs');
        expect(req.headers['Content-Type'], contains('application/json'));
        final List<dynamic> body = jsonDecode(req.body) as List<dynamic>;
        expect(body.length, 2);
        return http.Response('{"ok":true,"received":2}', 200);
      });
      final RemoteLogUploader u = RemoteLogUploader(
        client: mock,
        endpoint: 'http://logs.example.com',
        enabled: true,
      );
      addTearDown(u.dispose);
      u.push(_entry);
      u.push(_entry);
      expect(await u.flush(), 2);
      expect(await u.flush(), 0); // 缓冲已清空
    });

    test('网络失败 → 放回缓冲，可重试成功', () async {
      int calls = 0;
      final MockClient mock = MockClient((http.Request req) async {
        calls++;
        if (calls == 1) throw Exception('network down');
        return http.Response('{"ok":true,"received":1}', 200);
      });
      final RemoteLogUploader u = RemoteLogUploader(
        client: mock,
        endpoint: 'http://x',
        enabled: true,
      );
      addTearDown(u.dispose);
      u.push(_entry);
      expect(await u.flush(), -1);
      expect(await u.flush(), 1); // 重试成功
      expect(calls, 2);
    });

    test('服务端拒绝 → 丢弃该批（不无限重试）', () async {
      int calls = 0;
      final MockClient mock = MockClient((http.Request req) async {
        calls++;
        return http.Response('internal error', 500);
      });
      final RemoteLogUploader u = RemoteLogUploader(
        client: mock,
        endpoint: 'http://x',
        enabled: true,
      );
      addTearDown(u.dispose);
      u.push(_entry);
      expect(await u.flush(), -1);
      expect(await u.flush(), 0); // 已丢弃，不再重试
      expect(calls, 1);
    });

    test('endpoint 尾斜杠被规整，仍拼出 /api/logs', () async {
      final MockClient mock = MockClient((http.Request req) async {
        expect(req.url.toString(), 'http://x/api/logs');
        return http.Response('{"ok":true,"received":1}', 200);
      });
      final RemoteLogUploader u = RemoteLogUploader(
        client: mock,
        endpoint: 'http://x/',
        enabled: true,
      );
      addTearDown(u.dispose);
      u.push(_entry);
      expect(await u.flush(), 1);
    });

    test('开关从关到开：setEnabled(true) 后生效', () async {
      final MockClient mock = MockClient((http.Request req) async {
        return http.Response('{"ok":true,"received":1}', 200);
      });
      final RemoteLogUploader u = RemoteLogUploader(
        client: mock,
        endpoint: 'http://x',
        enabled: false,
      );
      addTearDown(u.dispose);
      u.push(_entry);
      expect(await u.flush(), 0); // 关闭时不发
      u.setEnabled(true);
      u.push(_entry);
      expect(await u.flush(), 1); // 打开后发送
    });

    test('flush 自动附带 SUMMARY/health 健康快照（自动识别异常）', () async {
      final MockClient mock = MockClient((http.Request req) async {
        final List<dynamic> body = jsonDecode(req.body) as List<dynamic>;
        // 第一条是健康快照，其后是真实日志
        expect((body.first as Map<String, dynamic>)['level'], 'SUMMARY');
        expect((body.first as Map<String, dynamic>)['tag'], 'health');
        expect((body.first as Map<String, dynamic>)['msg'], contains('errors='));
        expect(body.length, 3);
        return http.Response('{"ok":true,"received":3}', 200);
      });
      final RemoteLogUploader u = RemoteLogUploader(
        client: mock,
        endpoint: 'http://x',
        enabled: true,
        healthSummary: () => 'errors=1 warns=2 | [audio] 加载失败',
      );
      addTearDown(u.dispose);
      u.push(_entry);
      u.push(_entry);
      expect(await u.flush(), 3); // 2 条日志 + 1 条健康快照
    });
  });
}
