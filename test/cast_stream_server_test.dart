import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/services/cast/cast_stream_server.dart';

/// T11 投屏服务 HTTP 冒烟测试：真实起服务 + 真实请求验证 Range 切片。
void main() {
  final CastStreamServer server = CastStreamServer.instance;

  setUp(() async {
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  test('Range 切片：bytes=10-19 返回 206 + Content-Range + 精确 10 字节', () async {
    final Directory dir = await Directory.systemTemp.createTemp('cast_test');
    final File f = File('${dir.path}/sample.bin');
    await f.writeAsBytes(List<int>.generate(100, (int i) => i));

    final HttpClient client = HttpClient();
    try {
      final Uri url = Uri.parse(
        'http://127.0.0.1:${server.port}/track?uri=${Uri.encodeComponent(f.path)}',
      );
      // 直接走底层请求拿状态码与头
      final HttpClientRequest req = await client.getUrl(url);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=10-19');
      final HttpClientResponse res = await req.close();
      expect(res.statusCode, 206);
      expect(res.headers.value(HttpHeaders.contentRangeHeader), 'bytes 10-19/100');
      final List<int> body = <int>[];
      await for (final List<int> chunk in res) {
        body.addAll(chunk);
      }
      expect(body, List<int>.generate(10, (int i) => i + 10));
    } finally {
      client.close(force: true);
      await dir.delete(recursive: true);
    }
  });

  test("打开网页端 '/', 返回 200 + html", () async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      final HttpClientResponse res = await req.close();
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'text/html');
      final String body =
          await res.transform(const Utf8Decoder()).join();
      expect(body, contains('星璃投屏'));
    } finally {
      client.close(force: true);
    }
  });

  test('未指定 uri 返回 400', () async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/track'),
      );
      final HttpClientResponse res = await req.close();
      expect(res.statusCode, 400);
    } finally {
      client.close(force: true);
    }
  });
}