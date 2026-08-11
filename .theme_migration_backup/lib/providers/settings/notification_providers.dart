import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/notification_event.dart';
import '../../services/log_service.dart';

/// 通知中心：后台播放 / 锁屏控件 / 通知栏 3 个开关（v2 M6）。
///
/// v1 中这 3 个开关是 settings_page 的私有 `StateProvider`；v2 上提为
/// 共享 provider（架构 §1 M6），供 [NotificationCenter] 与设置页共用。
final StateProvider<bool> backgroundPlayProvider =
    StateProvider<bool>((Ref ref) => true);
final StateProvider<bool> lockScreenProvider =
    StateProvider<bool>((Ref ref) => true);
final StateProvider<bool> notificationBarProvider =
    StateProvider<bool>((Ref ref) => true);

/// 最近通知事件日志（P2-M6-4 · A5 已裁决：自动记录播放 / 场景事件，
/// 不做独立持久化）。
final StateNotifierProvider<NotificationLogNotifier, List<NotificationEvent>>
    recentNotificationsProvider =
    StateNotifierProvider<NotificationLogNotifier, List<NotificationEvent>>(
  (Ref ref) => NotificationLogNotifier(),
);

class NotificationLogNotifier extends StateNotifier<List<NotificationEvent>> {
  NotificationLogNotifier() : super(const <NotificationEvent>[]);

  /// 最大保留条数。
  static const int _max = 50;
  int _seq = 0;

  /// 追加一条事件。
  void append(String title, String message) {
    final NotificationEvent event = NotificationEvent(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
      title: title,
      message: message,
      at: DateTime.now(),
    );
    final List<NotificationEvent> next = <NotificationEvent>[event, ...state];
    state = next.length > _max ? next.sublist(0, _max) : next;
    LogService.instance.i('notification', '$title: $message');
  }

  /// 清空。
  void clear() => state = const <NotificationEvent>[];
}
