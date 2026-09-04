/// G9 联机协议（cl79）· NetMessage 编解码 / 类型索引稳定性单测。
///
/// 纯 Dart，不碰网络/引擎；与 relay-server/test_relay.js 的协议语义对齐：
///   - `t` 为线上编码索引（勿重排，否则旧包不兼容）；
///   - JSON 信封 = {t, f, to?, p}；
///   - 坏包在传输层被 try/catch 忽略（这里验证解码的抛错行为）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/services/net/net_message.dart';

void main() {
  group('NetMsgType 索引稳定性（线上编码，勿重排）', () {
    test('17 种类型，索引与线上编码一致', () {
      expect(NetMsgType.values.length, 17);
      expect(NetMsgType.hello.index, 0);
      expect(NetMsgType.welcome.index, 1);
      expect(NetMsgType.peerJoin.index, 2);
      expect(NetMsgType.peerLeave.index, 3);
      expect(NetMsgType.transform.index, 4);
      expect(NetMsgType.edit.index, 5);
      expect(NetMsgType.vitals.index, 6);
      expect(NetMsgType.chat.index, 7);
      expect(NetMsgType.listenState.index, 8);
      expect(NetMsgType.requestListen.index, 9);
      expect(NetMsgType.bye.index, 10);
      expect(NetMsgType.ping.index, 11);
      expect(NetMsgType.editSnapshot.index, 12);
      expect(NetMsgType.requestEditSnapshot.index, 13);
      expect(NetMsgType.orderSubmit.index, 14);
      expect(NetMsgType.orderQueue.index, 15);
      expect(NetMsgType.orderDecision.index, 16);
    });
  });

  group('JSON 信封编解码', () {
    test('完整信封往返：t/f/to/p 一致', () {
      final NetMessage m = NetMessage(
        type: NetMsgType.edit,
        from: 'p1',
        to: 'p2',
        payload: <String, dynamic>{'x': 1, 'y': 2, 'z': 3, 'v': 5},
      );
      final String s = m.encode();
      expect(s, contains('"t":5'));
      expect(s, contains('"f":"p1"'));
      expect(s, contains('"to":"p2"'));
      expect(s, contains('"x":1'));
      final NetMessage back = NetMessage.decode(s);
      expect(back.type, NetMsgType.edit);
      expect(back.from, 'p1');
      expect(back.to, 'p2');
      expect(back.payload['x'], 1);
      expect(back.payload['v'], 5);
    });

    test('无 to 的广播信封不写 to 字段', () {
      final NetMessage m = buildVitalsMessage('p1', 10, 7, 3);
      expect(m.to, isNull);
      expect(m.encode(), isNot(contains('"to"')));
    });

    test('缺省字段容错：t/f/p 缺失回落默认值', () {
      final NetMessage m =
          NetMessage.fromJson(<String, dynamic>{'f': 'x'});
      expect(m.type, NetMsgType.hello); // t 缺省 → 0
      expect(m.from, 'x');
      expect(m.payload, isEmpty);
      expect(m.to, isNull);
    });

    test('toJson 不含 null to（不序列化 null）', () {
      final Map<String, dynamic> j = NetMessage(
        type: NetMsgType.ping,
        from: 'a',
        payload: <String, dynamic>{},
      ).toJson();
      expect(j.containsKey('to'), isFalse);
    });
  });

  group('坏包行为（传输层 try/catch 忽略的边界）', () {
    test('非 JSON 字符串解码抛 FormatException', () {
      expect(() => NetMessage.decode('not-json'), throwsFormatException);
    });

    test('t 越界（非 0..13）被 clamp 到合法范围，不再抛错（网络输入防崩）', () {
      // 修复前：values[99] 直接索引抛 RangeError 崩（恶意/损坏包）；
      // 修复后：clamp 到最后一个类型，安全解析。
      final NetMessage m =
          NetMessage.fromJson(<String, dynamic>{'t': 99, 'f': 'x'});
      expect(m.type, NetMsgType.values.last);
      final NetMessage mNeg =
          NetMessage.fromJson(<String, dynamic>{'t': -3, 'f': 'x'});
      expect(mNeg.type, NetMsgType.values.first);
    });
  });

  group('withTo（中转定向投递标记）', () {
    test('返回带 to 的副本，原消息不变', () {
      final NetMessage src = NetMessage(
        type: NetMsgType.editSnapshot,
        from: 'host',
        payload: <String, dynamic>{'edits': <dynamic>[]},
      );
      final NetMessage tagged = src.withTo('client9');
      expect(tagged.to, 'client9');
      expect(tagged.type, NetMsgType.editSnapshot);
      expect(src.to, isNull); // 原消息未被修改
    });
  });

  group('buildVitalsMessage（cl79 纯函数）', () {
    test('构造 vitals 信封：t=6 + hp/hg/xp', () {
      final NetMessage m = buildVitalsMessage('me', 10, 7, 3);
      expect(m.type, NetMsgType.vitals);
      expect(m.from, 'me');
      expect(m.payload['hp'], 10);
      expect(m.payload['hg'], 7);
      expect(m.payload['xp'], 3);
      expect(m.encode(), contains('"t":6'));
    });
  });
}
