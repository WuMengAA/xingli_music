import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/services/net/net_node.dart';

void main() {
  group('friendlyRelayError 错误翻译', () {
    test('wss 协议填错（HandshakeException/WRONG_VERSION_NUMBER）→ 协议异常提示', () {
      const Object e = HandshakeException(
        'Handshake error in client (OS Error: '
        'WRONG_VERSION_NUMBER(../../../flutter/third_party/boringssl/src/ssl/tls_record.cc:127))',
      );
      final String msg = friendlyRelayError(e);
      expect(msg, contains('协议异常'));
    });

    test('明文连接被拒（非 ws 服务器）→ 不是乐厅服务提示', () {
      const Object e = WebSocketException(
        "Connection to 'http://127.0.0.1:8765/' was not upgraded to websocket",
      );
      expect(friendlyRelayError(e), contains('不是乐厅服务'));
    });

    test('连接被拒（服务器未启动）→ 无法连接提示', () {
      const Object e = SocketException('Connection refused (OS Error: '
          'Connection refused, errno = 111, address = 192.168.1.248, port = 8765)');
      expect(friendlyRelayError(e), contains('无法连接到乐厅'));
    });

    test('域名解析失败 → 无法连接提示', () {
      const Object e = SocketException(
          'Failed host lookup: relay.xingli.app (OS Error: No address associated with hostname)');
      expect(friendlyRelayError(e), contains('无法连接到乐厅'));
    });

    test('连接超时 → 超时提示', () {
      final Object e = TimeoutException(
        'Future not completed',
        Duration(seconds: 6),
      );
      expect(friendlyRelayError(e), contains('超时'));
    });

    test('未知错误 → 中文兜底（不再透传英文原文）', () {
      final Object e = StateError('Some weird internal error');
      expect(friendlyRelayError(e), contains('连接出错'));
    });

    test('房间已满 → 房间已满提示', () {
      expect(friendlyRelayError(Exception('room full')), contains('房间已满'));
    });

    test('房间号被占用 → 换房号提示', () {
      expect(friendlyRelayError(Exception('room exists')), contains('已被占用'));
    });

    test('密码错误 → 密码错误提示', () {
      expect(friendlyRelayError(Exception('wrong password')), contains('密码错误'));
    });

    test('房间不存在 → 确认房间号提示', () {
      expect(friendlyRelayError(Exception('room not found')), contains('房间不存在'));
    });
  });

  group('kDefaultRelayUrl 默认地址', () {
    test('默认地址为官方中转（wss:// + /ws）', () {
      expect(kDefaultRelayUrl, startsWith('wss://'));
      expect(kDefaultRelayUrl, endsWith('/ws'));
    });
  });
}
