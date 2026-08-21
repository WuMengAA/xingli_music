/// ════════════════════════════════════════════════════════════════════════
/// 切 Tab 进出场模糊过渡脉冲（批3 #580 · C）
/// ════════════════════════════════════════════════════════════════════════
///
/// 切 Tab 时对「内容区」做一次短暂的整屏磨砂脉冲（模糊强度 0→峰→0 的三角波，
/// 约 220ms），让页面切换更柔和——模糊过渡而非硬切。脉冲绘于 dock / 浮层之下，
/// dock 保持清晰。
///
/// 省电模式（[PerformanceMode.performance]）或模糊强度为 0 时直接跳过，零开销。
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings/performance_providers.dart';
import '../../providers/shell/shell_providers.dart';

/// 切 Tab 整屏磨砂脉冲。
class TabSwitchBlurPulse extends ConsumerStatefulWidget {
  const TabSwitchBlurPulse({super.key});

  @override
  ConsumerState<TabSwitchBlurPulse> createState() =>
      _TabSwitchBlurPulseState();
}

class _TabSwitchBlurPulseState extends ConsumerState<TabSwitchBlurPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  Widget build(BuildContext context) {
    // 切 Tab 时重播脉冲（首帧 prev==null 不触发）。
    ref.listen<int>(shellPageIndexProvider, (int? previous, int next) {
      if (previous != null && previous != next) {
        _ctrl.forward(from: 0);
      }
    });

    final PerformanceMode perf = ref.watch(performanceModeProvider);
    if (perf == PerformanceMode.performance) return const SizedBox.shrink();
    final double blur = ref.watch(glassBlurProvider);
    if (blur <= 0) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (BuildContext context, Widget? child) {
          final double v = _ctrl.value;
          // 三角波：0→1（峰）→0，约 220ms 的短暂脉冲。
          final double pulse = (1 - (2 * v - 1).abs()).clamp(0.0, 1.0);
          if (pulse <= 0.001) return const SizedBox.shrink();
          return BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: blur * pulse,
              sigmaY: blur * pulse,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}
