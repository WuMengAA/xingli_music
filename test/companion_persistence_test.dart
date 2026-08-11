/// AI 陪伴聊天历史持久化测试（序列化往返 / 截断 / 损坏回退）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/models/companion_models.dart';

void main() {
  group('CompanionSession 持久化', () {
    test('toJson/fromJson 往返保留消息、状态、破冰标志与时间戳', () {
      final DateTime ts = DateTime(2026, 8, 10, 22, 30);
      final CompanionSession s = CompanionSession(
        messages: <CompanionMessage>[
          CompanionMessage.user('你好', ts: ts),
          CompanionMessage.companion('嗯', ts: ts.add(const Duration(seconds: 1))),
          CompanionMessage.companion(
            '风有点凉',
            ts: ts.add(const Duration(seconds: 2)),
            proactive: true,
          ),
        ],
        state: CompanionState.acquaintance,
        firstContactMade: true,
        lastInteractionAt: ts.add(const Duration(seconds: 2)),
        lastProactiveAt: ts.add(const Duration(seconds: 2)),
      );

      final CompanionSession r = CompanionSession.fromJson(s.toJson());

      expect(r.messages.length, 3);
      expect(r.messages[0].role, CompanionRole.user);
      expect(r.messages[0].text, '你好');
      expect(r.messages[0].ts, ts);
      expect(r.messages[2].proactive, isTrue);
      expect(r.state, CompanionState.acquaintance);
      expect(r.firstContactMade, isTrue);
      expect(r.lastInteractionAt, ts.add(const Duration(seconds: 2)));
      expect(r.lastProactiveAt, ts.add(const Duration(seconds: 2)));
      // 动作队列是一次性的，不持久化
      expect(r.pendingActions, isEmpty);
    });

    test('超过上限只保留最近 kMaxPersistedMessages 条', () {
      final List<CompanionMessage> many = List<CompanionMessage>.generate(
        CompanionSession.kMaxPersistedMessages + 50,
        (int i) => CompanionMessage.user('m$i'),
      );
      final CompanionSession s = CompanionSession(
        messages: many,
        state: CompanionState.acquaintance,
        firstContactMade: true,
      );
      final CompanionSession r = CompanionSession.fromJson(s.toJson());
      expect(r.messages.length, CompanionSession.kMaxPersistedMessages);
      expect(r.messages.first.text, 'm${50}'); // 丢最旧 50 条
      expect(r.messages.last.text, 'm${CompanionSession.kMaxPersistedMessages + 49}');
    });

    test('未知状态名回退 stranger，损坏结构回退 initial', () {
      final CompanionSession r = CompanionSession.fromJson(<String, dynamic>{
        'messages': <dynamic>[
          <String, dynamic>{'role': 'user', 'text': 'hi', 'ts': 1},
        ],
        'state': 'not_a_state',
        'firstContactMade': true,
      });
      expect(r.state, CompanionState.stranger);

      final CompanionSession empty =
          CompanionSession.fromJson(const <String, dynamic>{});
      expect(empty.messages, isEmpty);
      expect(empty.firstContactMade, isFalse);
    });
  });
}
