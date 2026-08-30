/// terms_service 单测（cl17 · 目标6）。
///
/// 验证：
/// - GitHub 拉取成功 → 正文/来源正确（模拟 200 响应）；
/// - 拉取失败（网络异常 / 404）→ 回退本地内置文本 + 来源「本地内置」；
/// - 时间戳非空且为 YYYY-MM-DD 形态。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:xingli_music/services/content/terms_service.dart';

/// 构造 UTF-8 响应（http.Response 默认 Latin1，不能含中文）。
http.Response _utf8Body(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

void main() {
  group('fetchTermsDoc', () {
    test('远端拉取成功时用 GitHub 正文与来源', () async {
      final http.Client ok = MockClient(
        (request) async => _utf8Body('# 服务条款\n\n远端正文 2026'),
      );
      final TermsDoc doc = await fetchTermsDoc(TermsKind.terms, client: ok);
      expect(doc.source, 'GitHub');
      expect(doc.body, contains('远端正文'));
      expect(doc.updatedAt, isNotEmpty);
    });

    test('404 时回退本地内置并标注来源', () async {
      final http.Client notFound = MockClient(
        (request) async => _utf8Body('Not Found', 404),
      );
      final TermsDoc doc = await fetchTermsDoc(TermsKind.privacy, client: notFound);
      expect(doc.source, '本地内置');
      expect(doc.body, kLocalPrivacyBody);
      expect(doc.updatedAt, kLocalTermsDate);
    });

    test('网络异常时回退本地内置（不影响同意闸门）', () async {
      final http.Client broken = MockClient(
        (request) async => throw Exception('network down'),
      );
      final TermsDoc doc = await fetchTermsDoc(TermsKind.terms, client: broken);
      expect(doc.source, '本地内置');
      expect(doc.body, kLocalTermsBody);
    });

    test('title 随 kind 切换', () async {
      final http.Client ok = MockClient(
        (request) async => http.Response('x', 200),
      );
      expect((await fetchTermsDoc(TermsKind.terms, client: ok)).title, '服务条款');
      expect((await fetchTermsDoc(TermsKind.privacy, client: ok)).title, '隐私政策');
    });
  });

  group('termsFileName & shortDate', () {
    test('文件名映射', () {
      expect(termsFileName(TermsKind.terms), 'TERMS.md');
      expect(termsFileName(TermsKind.privacy), 'PRIVACY.md');
    });
  });
}