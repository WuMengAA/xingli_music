import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_providers.dart';

/// 睡眠定时状态（播放体验优化）。
///
/// - [remaining] 非 null：倒计时模式，到点暂停播放；
/// - [onTrackEnd] = true：当前曲目自然播放结束后暂停（剩余时间未知，显示「本曲结束」）。
class SleepTimerState {
  const SleepTimerState(this.remaining, this.onTrackEnd);

  /// 剩余时间（倒计时模式）；null 表示未启用或「本曲结束」模式。
  final Duration? remaining;

  /// 是否「当前曲目结束后停止」模式。
  final bool onTrackEnd;

  /// 是否处于启用状态（任一模式）。
  bool get active => remaining != null || onTrackEnd;
}

/// 睡眠定时 Provider（单例 Notifier，常驻于 ProviderScope）。
///
/// 倒计时到点或本曲自然结束 → 调用 [AudioService.pauseOnly] 暂停播放。
final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>(
  (ref) => SleepTimerNotifier(ref),
);

/// 睡眠定时控制器：管理倒计时 / 本曲结束监听，到点自动暂停播放。
class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  SleepTimerNotifier(this.ref) : super(const SleepTimerState(null, false));

  final Ref ref;
  Timer? _timer;
  StreamSubscription<void>? _completedSub;

  /// 按倒计时启动：到点自动暂停（#485：暂停时冻结计时，恢复播放自动续计）。
  void start(Duration duration) {
    _clear();
    final svc = ref.read(audioServiceProvider);
    state = SleepTimerState(duration, false);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!svc.musicPlaying) return; // 暂停态：不递减，冻结倒计时
      final Duration? r = state.remaining;
      if (r == null) return;
      final Duration next = r - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _fire();
      } else {
        state = SleepTimerState(next, false);
      }
    });
  }

  /// 当前曲目自然播放结束后停止（监听 [AudioService.trackCompletedStream]）。
  ///
  /// 无正在播放的曲目时静默忽略（无法挂起）。#486：绑定当前曲 uri，仅当仍是
  /// 该曲自然结束时触发，并抑制自动续播，避免「下一首先起播再被暂停」的闪烁。
  void startOnTrackEnd() {
    _clear();
    final svc = ref.read(audioServiceProvider);
    final bound = svc.currentTrack;
    if (bound == null) return;
    svc.setSuppressAutoAdvance(true); // #486：本曲结束期间不自动续播
    state = const SleepTimerState(null, true);
    _completedSub = svc.trackCompletedStream.listen((_) {
      // #486：必须是本曲结束模式，且当前曲仍是绑定那首，才暂停；
      // 否则（切歌/自动过渡导致绑定的曲已不在播）定时失效、复位。
      if (state.onTrackEnd && svc.currentTrack?.uri == bound.uri) {
        _fire();
      } else {
        _clear();
      }
    });
  }

  /// 到点触发：暂停播放并复位状态。
  void _fire() {
    _clear();
    unawaited(ref.read(audioServiceProvider).pauseOnly());
  }

  /// 取消定时（用户主动取消或复位）。
  void cancel() {
    if (!state.active) return;
    _clear();
  }

  /// 清理定时器与监听（保留 state 直到最后统一复位，避免中间帧闪回）。
  void _clear() {
    _timer?.cancel();
    _timer = null;
    _completedSub?.cancel();
    _completedSub = null;
    // #486：复位「抑制自动续播」，避免残留标志影响后续正常自动播放。
    ref.read(audioServiceProvider).setSuppressAutoAdvance(false);
    if (state.active) state = const SleepTimerState(null, false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _completedSub?.cancel();
    super.dispose();
  }
}
