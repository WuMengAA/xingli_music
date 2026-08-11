/// ════════════════════════════════════════════════════════════════════════
/// 帧率节流 Binding（R22）
/// ════════════════════════════════════════════════════════════════════════
///
/// Flutter 引擎默认按显示器 vsync 全速渲染，没有官方的「限制渲染帧率」API。
/// 用户要求帧率限制（24/30/60/120）**全局生效**——通过在 SchedulerBinding
/// 层拦截 `scheduleFrame()` 实现节流：距上一帧不足 `1000/fps` 毫秒的
/// 调度请求延迟到下一允许时刻。
///
/// - 目标帧率由全局变量 [throttledFps] 提供（Riverpod 侧更新），
///   120 及以上不节流（等效关闭）；
/// - 副作用：帧调度延迟会让连续动画变卡（这正是「限帧省电」的目的）；
///   输入响应同样被节流，低帧率下交互会略有延迟，属预期代价。
/// - 仅 release 应用 main() 使用；测试环境用 TestWidgetsFlutterBinding，
///   不受影响。
///
/// 用法（main.dart 首行，必须在任何 ensureInitialized 之前）：
/// ```dart
/// ThrottledWidgetsBinding().initInstances();
/// ```
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// 全局帧率节流目标（每秒帧数）。由 fpsLimitProvider 同步更新；
/// 默认 60（不高于常规屏刷新率，几乎不节流）。
int throttledFps = 60;

/// 带帧率节流的 WidgetsBinding。
class ThrottledWidgetsBinding extends WidgetsFlutterBinding {
  final Stopwatch _last = Stopwatch()..start();
  bool _pending = false;
  Timer? _timer;

  @override
  void scheduleFrame() {
    final int fps = throttledFps;
    // 120 及以上视为不限帧（引擎 vsync 上限）；无效值（<=0）防御直通。
    if (fps >= 120 || fps <= 0) {
      super.scheduleFrame();
      return;
    }
    final int intervalUs = 1000000 ~/ fps;
    final int elapsedUs = _last.elapsedMicroseconds;
    if (elapsedUs >= intervalUs) {
      // 距上一帧已够久：立即出帧
      _pending = false;
      _last..reset()..start();
      super.scheduleFrame();
      return;
    }
    // 未到允许时刻：挂起一次，到点后【直接出帧】。
    // ⚠️ 不能在 Timer 回调里先 reset 再走一遍 scheduleFrame() 判断——
    // reset 后 elapsed=0 永远小于间隔 → 无限挂 Timer、永不渲染 → 黑屏
    //（R22 实测双端开机即黑屏的根因）。
    if (!_pending) {
      _pending = true;
      _timer?.cancel();
      final int waitUs = intervalUs - elapsedUs;
      _timer = Timer(Duration(microseconds: waitUs), () {
        _pending = false;
        _last..reset()..start();
        super.scheduleFrame();
      });
    }
  }
}
