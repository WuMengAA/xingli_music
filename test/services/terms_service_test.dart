import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xingli_music/services/content/terms_service.dart';

void main() {
  group('TermsService 条款拉取', () {
    test('GitHub 200 → 返回远程正文，来源 GitHub', () async {
      final http.Client ok = MockClient((http.Request req) async {
        expect(req.url.path, contains('docs/TERMS.md'));
        return http.Response(utf8.encode('远程最新条款正文').toString(), 200,
            headers: {'content-type': 'text/plain; charset=utf-8'});
      });
      final TermsDoc doc = await fetchTermsDoc(TermsKind.terms, client: ok);
      expect(doc.source, 'GitHub');
      expect(doc.title, '服务条款');
      expect(doc.body, isNot(contains('本地内置')));
      expect(doc.updatedAt, isNotEmpty);
    });

    test('404 → 回退本地内置，来源标注', () async {
      final http.Client notFound = MockClient(
        (http.Request req) async => http.Response('Not Found', 404),
      );
      final TermsDoc doc =
          await fetchTermsDoc(TermsKind.terms, client: notFound);
      expect(doc.source, '本地内置');
      expect(doc.body, kLocalTermsBody);
      expect(doc.updatedAt, kLocalTermsDate);
    });

    test('网络异常 → 回退本地（不冒泡）', () async {
      final http.Client boom = MockClient(
        (http.Request req) async => throw Exception('network down'),
      );
      final TermsDoc doc =
          await fetchTermsDoc(TermsKind.terms, client: boom);
      expect(doc.source, '本地内置');
      expect(doc.body, kLocalTermsBody);
    });

    test('200 但空正文 → 回退本地', () async {
      final http.Client blank = MockClient(
        (http.Request req) async => http.Response('   ', 200),
      );
      final TermsDoc doc =
          await fetchTermsDoc(TermsKind.privacy, client: blank);
      expect(doc.source, '本地内置');
      expect(doc.body, kLocalPrivacyBody);
    });

    test('隐私政策拉取隐私文件并携带标题', () async {
      final http.Client ok = MockClient((http.Request req) async {
        expect(req.url.path, contains('docs/PRIVACY.md'));
        return http.Response(utf8.encode('远程隐私正文').toString(), 200);
      });
      final TermsDoc doc =
          await fetchTermsDoc(TermsKind.privacy, client: ok);
      expect(doc.title, '隐私政策');
      expect(doc.source, 'GitHub');
    });
  });
}