import 'package:flutter/material.dart';

/// 播放动作的统一反馈通道（共享约定 C6）
///
/// `PlaybackActions` 的每个方法都返回一个 `String`：空串代表成功，
/// 非空代表需要告知用户的原因（曲库为空、文件不可播…）。
/// **这个返回值必须被消费**，否则用户点了没反应会以为应用卡死。
///
/// 所有调用点（`MiniPlayer` / `LibraryPage` / `NowPlayingPage`）统一走这里，
/// 保证提示样式与生命周期处理只有一份实现。
Future<void> runPlaybackAction(
  BuildContext context,
  Future<String> Function() action,
) async {
  // await 之前先取 messenger —— 之后 context 可能已失效
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String message = await action();
  if (message.isEmpty) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
}

/// 同步动作的轻提示（如切换播放模式）
void showPlaybackToast(BuildContext context, String message) {
  if (message.isEmpty) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
      ),
    );
}
