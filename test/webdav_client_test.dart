import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xingli_music/services/network/webdav_client.dart';

void main() {
  const String propfindXml = '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/music/</D:href>
    <D:propstat>
      <D:prop>
        <D:displayname>music</D:displayname>
        <D:resourcetype><D:collection/></D:resourcetype>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/music/%E6%AD%8C%E6%9B%B2.flac</D:href>
    <D:propstat>
      <D:prop>
        <D:displayname>&#x6B4C;&#x66F2;.flac</D:displayname>
        <D:getcontentlength>5242880</D:getcontentlength>
        <D:getcontenttype>audio/flac</D:getcontenttype>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>
''';

  WebDavClient clientWith(MockClient mock) => WebDavClient(
        baseUrl: 'http://192.168.1.100:5005/dav',
        username: 'user',
        password: 'pass',
        httpClient: mock,
      );

  test('list 解析目录与文件（XML 实体 + 编码），并带 Depth 与 Basic 认证头', () async {
    late http.Request captured;
    final WebDavClient client = clientWith(
      MockClient((http.Request req) async {
        captured = req;
        return http.Response(
          propfindXml,
          207,
          headers: <String, String>{'content-type': 'text/xml'},
        );
      }),
    );

    final List<WebDavEntry> entries = await client.list('music');

    expect(captured.method, 'PROPFIND');
    expect(captured.headers['Depth'], '1');
    expect(captured.headers['Authorization'], startsWith('Basic '));
    expect(captured.url.path, '/dav/music');

    expect(entries.length, 2);
    final WebDavEntry dir = entries[0];
    expect(dir.name, 'music');
    expect(dir.isDir, isTrue);

    final WebDavEntry file = entries[1];
    expect(file.name, '歌曲.flac');
    expect(file.isDir, isFalse);
    expect(file.sizeBytes, 5242880);
    expect(file.contentType, 'audio/flac');
    expect(file.isAudio, isTrue);
    expect(
      file.absoluteUrl('http://192.168.1.100:5005/dav'),
      'http://192.168.1.100:5005/dav/dav/music/%E6%AD%8C%E6%9B%B2.flac',
    );
  });

  test('401 → 认证异常（中文提示）', () async {
    final WebDavClient client = clientWith(
      MockClient((http.Request req) async => http.Response('', 401)),
    );
    await expectLater(
      client.list('/'),
      throwsA(isA<WebDavException>().having(
          (WebDavException e) => e.message, 'message', contains('认证失败'))),
    );
  });

  test('authHeaders 为 Basic(user:pass) 的 base64', () {
    final WebDavClient client = WebDavClient(
      baseUrl: 'http://x/dav',
      username: 'user',
      password: 'pass',
      httpClient: MockClient((http.Request req) async => http.Response('', 200)),
    );
    final String expectValue =
        'Basic ${base64Encode(utf8.encode('user:pass'))}';
    expect(client.authHeaders['Authorization'], expectValue);
  });
}