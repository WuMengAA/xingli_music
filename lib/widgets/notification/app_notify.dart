import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings/notification_providers.dart';

/// R26fx2：**全局唯一通知出口** —— 右上角小弹条（≤1/3 屏宽，绝不占全屏）。
///
/// 所有页面通知统一走这里（替代散落各处的 `ScaffoldMessenger.showSnackBar`
/// 底部条与任何可能的全屏弹层）：`appNotify(context, '消息')` →
/// `recentNotificationsProvider.append` → AppShell 挂载的
/// [GlobalNotificationToast] 渲染为右上角紧凑弹条。
///
/// `title` 为事件来源标签（世界 / 播放 / 权限 / 场景…），显示在消息前。
void appNotify(
  BuildContext context,
  String message, {
  String title = '提示',
}) {
  try {
    final ProviderContainer container = ProviderScope.containerOf(context);
    container.read(recentNotificationsProvider.notifier).append(title, message);
  } catch (_) {
    // 极端情况（context 不在 ProviderScope 内）：静默丢弃，避免崩导航。
  }
}

/// 无 context 版本（Consumer 场景直接用 [WidgetRef]）。
void appNotifyRef(
  WidgetRef ref,
  String message, {
  String title = '提示',
}) {
  ref.read(recentNotificationsProvider.notifier).append(title, message);
}
