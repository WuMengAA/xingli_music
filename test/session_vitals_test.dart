/// 联机 vitals（生命/饥饿/经验）· 会话层单测（cl79）。
///
/// 不碰网络/引擎：用 Riverpod ProviderContainer + fake 传输缝隙（debugOnSend）
/// 断言 vitals 广播信封；接收侧用纯函数 [applyVitalsToPeers] 验证合并逻辑。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/providers/net/session_provider.dart';
import 'package:xingli_music/services/net/net_message.dart';

void main() {
  group('NetSessionNotifier.broadcastVitals（fake 传输层）', () {
    test('发送 vitals 信封：t=6 + hp/hg/xp', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final NetSessionNotifier notifier =
          container.read(netSessionProvider.notifier);

      NetMessage? captured;
      notifier.debugOnSend = (NetMessage m) => captured = m;

      notifier.broadcastVitals(10, 7, 3);
      expect(captured, isNotNull);
      expect(captured!.type, NetMsgType.vitals);
      expect(captured!.payload['hp'], 10);
      expect(captured!.payload['hg'], 7);
      expect(captured!.payload['xp'], 3);
      // 线上编码 t=6（与 relay-server 协议测试一致）。
      expect(captured!.encode(), contains('"t":6'));
    });

    test('localId 存在时 from 取本地 id', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final NetSessionNotifier notifier =
          container.read(netSessionProvider.notifier);

      NetMessage? captured;
      notifier.debugOnSend = (NetMessage m) => captured = m;
      notifier.debugSetLocalIdForTest('local-1');
      notifier.broadcastVitals(5, 5, 5);
      expect(captured!.from, 'local-1');
    });
  });

  group('applyVitalsToPeers（接收侧合并，纯函数）', () {
    test('更新目标成员 hp/hg/xp，不动其他成员', () {
      final List<PeerInfo> peers = <PeerInfo>[
        PeerInfo(id: 'a', name: 'A', health: 20, hunger: 20, xp: 0),
        PeerInfo(id: 'b', name: 'B', health: 20, hunger: 20, xp: 0),
      ];
      final List<PeerInfo> out =
          applyVitalsToPeers(peers, 'a', <String, dynamic>{
        'hp': 5,
        'hg': 3,
        'xp': 1,
      });
      expect(out[0].health, 5);
      expect(out[0].hunger, 3);
      expect(out[0].xp, 1);
      expect(out[1].health, 20); // b 未动
      // 原列表未被修改（不可变风格）。
      expect(peers[0].health, 20);
    });

    test('缺省字段保留原值', () {
      final List<PeerInfo> peers = <PeerInfo>[
        PeerInfo(id: 'b', name: 'B', health: 18, hunger: 9, xp: 4),
      ];
      final List<PeerInfo> out =
          applyVitalsToPeers(peers, 'b', <String, dynamic>{'hp': 7});
      expect(out[0].health, 7);
      expect(out[0].hunger, 9); // 缺省保留
      expect(out[0].xp, 4); // 缺省保留
    });

    test('PeerInfo vitals JSON 往返', () {
      final PeerInfo p = PeerInfo.fromJson(<String, dynamic>{
        'id': 'x',
        'name': 'X',
        'hp': 13,
        'hg': 6,
        'xp': 2,
      });
      expect(p.health, 13);
      expect(p.hunger, 6);
      expect(p.xp, 2);
      final Map<String, dynamic> j = p.toJson();
      expect(j['hp'], 13);
      expect(j['hg'], 6);
      expect(j['xp'], 2);
    });
  });
}
