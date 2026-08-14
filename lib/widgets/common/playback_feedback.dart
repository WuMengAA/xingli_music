import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings/notification_providers.dart';

/// 播放动作的统一反馈通道（共享约定 C6）
///
/// `PlaybackActions` 的每个方法都返回一个 `String`：空串代表成功，
/// 非空代表需要告知用户的原因（曲库为空、文件不可播…）。
/// **这个返回值必须被消费**，否则用户点了没反应会以为应用卡死。
///
/// 所有调用点（`MiniPlayer` / `LibraryPage` / `NowPlayingPage`）统一走这里，
/// 保证提示样式与生命周期处理只有一份实现。
/// D（用户确认）：所有通知统一走全局右上角 toast（右侧 ≤1/3 宽、不占全屏），
/// 不再用底部 SnackBar。
Future<void> runPlaybackAction(
  BuildContext context,
  Future<String> Function() action,
) async {
  final String message = await action();
  if (message.isEmpty) return;
  if (context.mounted) {
    _toast(context, message);
  }
}

/// 同步动作的轻提示（如切换播放模式）
void showPlaybackToast(BuildContext context, String message) {
  if (message.isEmpty) return;
  if (context.mounted) {
    _toast(context, message);
  }
}

void _toast(BuildContext context, String message) {
  // 经 Riverpod 全局通知（需 context 的 ProviderScope——调用点均在 widget 树内）。
  try {
    final ProviderContainer? c = ProviderScope.containerOf(context,
        listen: false);
    if (c != null) {
      c.read(recentNotificationsProvider.notifier).append('提示', message);
      return;
    }
  } catch (_) {
    // 容器取不到（极少数测试/非 widget 上下文）→ 兜底忽略，不抛。
  }
}
