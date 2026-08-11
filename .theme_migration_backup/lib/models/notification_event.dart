import 'package:flutter/foundation.dart';

/// 通知事件日志条目（v2 M6 · P2-M6-4）。
///
/// A5 已裁决：本轮**自动记录**播放 / 场景关键事件（provider 内 append），
/// 不做独立持久化；如需要可后续落盘。
@immutable
class NotificationEvent {
  const NotificationEvent({
    required this.id,
    required this.title,
    required this.message,
    required this.at,
  });

  /// 事件 id（时间戳 + 序号）。
  final String id;

  /// 事件标题（如「播放」「切场景」）。
  final String title;

  /// 事件详情。
  final String message;

  /// 发生时间。
  final DateTime at;

  /// 时间展示文案（HH:mm:ss）。
  String get timeLabel {
    final String hh = at.hour.toString().padLeft(2, '0');
    final String mm = at.minute.toString().padLeft(2, '0');
    final String ss = at.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}
