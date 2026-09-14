/// 播放失败 · 常驻错误位（#playback-error：失败可见 + 可重试）
///
/// 统一的「播放失败」状态：引擎错误流（[AudioService.playErrorStream]）、
/// 自动下一首失败、手动切歌失败都汇入这里；两页沉浸播放器（主页 /
/// 整页正在播放）共用 [PlaybackErrorBanner] 渲染「错误文案 + 重试 + 关闭」。
///
/// 与一次性 toast（[recentNotificationsProvider]）并存：toast 保留，
/// 本 provider 提供可常驻、可重试的失败位。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';

/// 重试动作类型：决定 [PlaybackErrorBanner] 点击「重试」时触发哪个播放动作。
enum PlaybackRetryKind {
  /// 重新播放指定曲目（[PlaybackError.track] 必填）。
  playTrack,

  /// 播放下一首。
  next,

  /// 切换播放 / 暂停。
  toggle,

  /// 无重试动作（仅展示 + 关闭）。
  none,
}

/// 一条播放失败信息。
class PlaybackError {
  const PlaybackError({
    required this.message,
    required this.kind,
    this.track,
  });

  final String message;
  final PlaybackRetryKind kind;

  /// 重试要播放的曲目（[PlaybackRetryKind.playTrack] 时使用）。
  final Track? track;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackError &&
          message == other.message &&
          kind == other.kind &&
          track == other.track;

  @override
  int get hashCode => Object.hash(message, kind, track);

  @override
  String toString() => 'PlaybackError($kind: $message)';
}

/// 当前播放失败（null = 无失败，不显示错误条）。
final playbackErrorProvider =
    NotifierProvider<PlaybackErrorNotifier, PlaybackError?>(
  PlaybackErrorNotifier.new,
);

class PlaybackErrorNotifier extends Notifier<PlaybackError?> {
  @override
  PlaybackError? build() => null;

  /// 上报一条播放失败（覆盖上一条；最新一条生效）。
  void report(PlaybackError error) => state = error;

  /// 清除失败位（错误条消失）。
  void clear() => state = null;
}
