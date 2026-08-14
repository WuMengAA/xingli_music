import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/services/audio/sources/netease/netease_api.dart'
    show NeteaseApiException;
import 'package:xingli_music/providers/sources/netease_provider.dart'
    show neteaseErrorText, neteaseIsAuthFailure;

void main() {
  group('neteaseErrorText (#279 搜索加固)', () {
    test('登录失效码(301/-460/8810) → 引导重新登录', () {
      expect(neteaseErrorText(const NeteaseApiException(301, 'x')),
          '网易云登录态已失效，请重新登录');
      expect(neteaseErrorText(const NeteaseApiException(-460, 'x')),
          '网易云登录态已失效，请重新登录');
      expect(neteaseIsAuthFailure(const NeteaseApiException(301, 'x')), isTrue);
    });

    test('风控(-462) → 操作过于频繁', () {
      expect(neteaseErrorText(const NeteaseApiException(-462, 'x')),
          '操作过于频繁，请稍候重试');
      expect(neteaseIsAuthFailure(const NeteaseApiException(-462, 'x')), isFalse);
    });

    test('限流(-405) → 请求被限制', () {
      expect(neteaseErrorText(const NeteaseApiException(-405, 'x')),
          '请求被限制，请稍后重试');
    });

    test('其他业务码 → 带码通用提示', () {
      expect(neteaseErrorText(const NeteaseApiException(500, 'boom')),
          '网易云接口异常（500）');
    });

    test('超时 → 网络超时', () {
      expect(neteaseErrorText(TimeoutException('x')), '网络超时，请检查连接后重试');
    });

    test('SocketException / 含 network → 网络异常', () {
      expect(neteaseErrorText(SocketException('fail')), '网络异常，请检查网络连接');
      expect(neteaseErrorText(Exception('Some network error')),
          '网络异常，请检查网络连接');
    });

    test('未知异常 → 通用搜索失败', () {
      expect(neteaseErrorText(Exception('weird')), '搜索失败，请稍后重试');
    });
  });
}
