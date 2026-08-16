import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/services/net/net_node.dart';

void main() {
  group('friendlyRelayError 错误翻译', () {
    test('wss 协议填错（HandshakeException/WRONG_VERSION_NUMBER）→ ws:// 提示', () {
      const Object e = HandshakeException(
        'Handshake error in client (OS Error: '
        'WRONG_VERSION_NUMBER(../../../flutter/third_party/boringssl/src/ssl/tls_record.cc:127))',
      );
      final String msg = friendlyRelayError(e);
      expect(msg, contains('协议填错了'));
      expect(msg, contains('ws://'));
      expect(msg, contains('wss://'));
    });

    test('明文连接被拒（非 ws 服务器）→ 不是中转服务器提示', () {
      const Object e = WebSocketException(
        "Connection to 'http://127.0.0.1:8765/' was not upgraded to websocket",
      );
      expect(friendlyRelayError(e), contains('不是中转服务器'));
    });

    test('连接被拒（服务器未启动）→ 无法连接提示', () {
      const Object e = SocketException('Connection refused (OS Error: '
          'Connection refused, errno = 111, address = 192.168.1.248, port = 8765)');
      expect(friendlyRelayError(e), contains('无法连接到中转服务器'));
    });

    test('域名解析失败 → 无法解析提示', () {
      const Object e = SocketException(
          'Failed host lookup: relay.xingli.app (OS Error: No address associated with hostname)');
      expect(friendlyRelayError(e), contains('无法解析'));
    });

    test('连接超时 → 超时提示', () {
      final Object e = TimeoutException(
        'Future not completed',
        Duration(seconds: 6),
      );
      expect(friendlyRelayError(e), contains('超时'));
    });

    test('未知错误保留原文（便于排查）', () {
      final Object e = StateError('Some weird internal error');
      expect(friendlyRelayError(e), contains('Some weird internal error'));
    });
  });

  group('kDefaultRelayUrl 默认地址', () {
    test('默认地址必须是 ws:// 明文协议（与自建中转服务器一致）', () {
      expect(kDefaultRelayUrl, startsWith('ws://'));
      expect(kDefaultRelayUrl, isNot(startsWith('wss://')));
      expect(kDefaultRelayUrl, endsWith('/ws'));
    });
  });
}
