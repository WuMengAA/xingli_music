/// ════════════════════════════════════════════════════════════════════════
/// 性能模式（低端设备优化）
/// ════════════════════════════════════════════════════════════════════════
///
/// 应对「长时间运行高负载画面导致发热 / 性能下降」（Wear OS / 低端机）。
/// 三档控制视觉开销，设置即时全局生效并持久化（key: `performanceMode`）：
///
/// | 档位 | 噪点纹理      | 玻璃模糊            | 动画           |
/// |------|--------------|---------------------|----------------|
/// | 省电 | 关闭          | 关闭（降为纯色）     | 最快            |
/// | 均衡 | 保留（低密度）| 保留（低 blur）     | 标准            |
/// | 流畅 | 保留          | 保留（满 blur）     | 标准            |
///
/// 默认「均衡」：兼顾观感与发热；手表 / 低端机可在设置中切「省电」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 性能档位（字符串持久化：balanced / power_save / smooth）。
enum PerformanceMode {
  /// 均衡：默认，噪点 + 低玻璃模糊。
  balanced,

  /// 省电：关噪点、关玻璃模糊、最快动画（低端 / Wear OS 推荐）。
  powerSave,

  /// 流畅：全特效（噪点 + 满玻璃模糊）。
  smooth,
}

/// 当前性能模式，默认「均衡」。
///
/// ⚠️ **不读 prefs**：初始值内置（balanced），冷启动由
/// `restoreSettings` 显式覆盖、运行期由 `settingsSyncProvider` 落盘。
/// 这样纯组件/测试环境（无 prefs 注入）也能正常 watch，不抛异常。
final performanceModeProvider = StateProvider<PerformanceMode>(
  (ref) => PerformanceMode.balanced,
);

/// 是否渲染噪点纹理（AppShell 全屏 / 播放面板 / 沉浸画布）。
final noiseEnabledProvider = Provider<bool>((ref) {
  return switch (ref.watch(performanceModeProvider)) {
    PerformanceMode.powerSave => false,
    PerformanceMode.balanced || PerformanceMode.smooth => true,
  };
});

/// 玻璃模糊强度（0 = 关闭模糊，仅纯色半透明）。
final glassBlurProvider = Provider<double>((ref) {
  return switch (ref.watch(performanceModeProvider)) {
    PerformanceMode.powerSave => 0,
    PerformanceMode.balanced => 12,
    PerformanceMode.smooth => 20,
  };
});

/// 动画时长缩放系数（1.0 标准 / 0.5 省电最快）。
final motionScaleProvider = Provider<double>((ref) {
  return switch (ref.watch(performanceModeProvider)) {
    PerformanceMode.powerSave => 0.5,
    PerformanceMode.balanced || PerformanceMode.smooth => 1.0,
  };
});
