import 'dart:math' as math;

/// ───────────────────────────────────────────────────────────────────────
/// 弹簧物理 —— 阻尼弹簧 ODE m·ẍ + c·ẋ + k·(x - target) = 0 的闭式解
///
/// 移植自 martin65536/liquid-glass-webgl 的 `spring.ts`，
/// 上游匹配 AndroidLiquidGlass 的 DampedDragAnimation.kt：
///   - 欠阻尼（ζ < 1）：有超调、弹跳 —— 按钮按下、拖拽偏移、开关缩放
///   - 临界阻尼（ζ = 1）：平滑无超调 —— 开关值/按下（spring(1f, 1000f)）、
///     tab 指示器
/// ───────────────────────────────────────────────────────────────────────

/// CSS 像素 ≈ 密度无关像素（目录用 DP=1）。
const double kLgDp = 1.0;

// 通用欠阻尼弹簧（ζ = 0.5）：速度 / 挤压 / 拉伸
// ωn = √300 ≈ 17.3205（m = 1）—— 字面量 const，用于可选项默认值
const double kSpringK = 300;
const double kSpringDampingRatio = 0.5;
const double kSpringOmegaN = 17.320508075688775;
final double kSpringOmegaD = kSpringOmegaN * math.sqrt(1 - kSpringDampingRatio * kSpringDampingRatio);

// 沉降阈值；0.003 仍视觉不可见（<0.3% 值域）但几帧内稳定
const double kSpringThreshold = 0.003;

// 临界阻尼弹簧：开关值/按下（spring(1f, 1000f) → 1000f）
const double kToggleValueK = 1000;
const double kToggleValueOmegaN = 31.622776601683793; // √1000

// 开关 scaleX（spring(0.6f, 250f)）
const double kToggleScaleXK = 250;
const double kToggleScaleXDampingRatio = 0.6;
const double kToggleScaleXOmegaN = 15.811388300841896; // √250
final double kToggleScaleXOmegaD = kToggleScaleXOmegaN * math.sqrt(1 - kToggleScaleXDampingRatio * kToggleScaleXDampingRatio);

// 开关 scaleY（spring(0.7f, 250f)）
const double kToggleScaleYK = 250;
const double kToggleScaleYDampingRatio = 0.7;
const double kToggleScaleYOmegaN = 15.811388300841896; // √250
final double kToggleScaleYOmegaD = kToggleScaleYOmegaN * math.sqrt(1 - kToggleScaleYDampingRatio * kToggleScaleYDampingRatio);

// 开关拖拽速度（spring(0.5f, 300f)）
const double kToggleVelocityK = 300;
const double kToggleVelocityDampingRatio = 0.5;
const double kToggleVelocityOmegaN = 17.320508075688775; // √300
final double kToggleVelocityOmegaD = kToggleVelocityOmegaN * math.sqrt(1 - kToggleVelocityDampingRatio * kToggleVelocityDampingRatio);

/// 欠阻尼弹簧一步（闭式解，dt 秒）。
/// 返回 { value, velocity }。
({double value, double velocity}) springStepUnderdamped(
  double current,
  double velocity,
  double target,
  double dt, {
  double omegaN = kSpringOmegaN,
  double dampingRatio = kSpringDampingRatio,
}) {
  final x0 = current - target;
  final v0 = velocity;
  final omegaD = omegaN * math.sqrt(1 - dampingRatio * dampingRatio);
  final decay = math.exp(-dampingRatio * omegaN * dt);
  final cosWd = math.cos(omegaD * dt);
  final sinWd = math.sin(omegaD * dt);
  final offset = x0 * decay * cosWd +
      ((v0 + dampingRatio * omegaN * x0) / omegaD) * decay * sinWd;
  final b0 = (v0 + dampingRatio * omegaN * x0) / omegaD;
  final newVel = -dampingRatio * omegaN * offset +
      decay * (-x0 * omegaD * sinWd + b0 * omegaD * cosWd);
  return (value: target + offset, velocity: newVel);
}

/// 临界阻尼弹簧一步（闭式解）。匹配 DampedDragAnimation 的
/// x(t) = target + x0·e^(-ωn·t) + (v0 + ωn·x0)·t·e^(-ωn·t)。
({double value, double velocity}) springStepCritical(
  double current,
  double velocity,
  double target,
  double dt, {
  double omegaN = kToggleValueOmegaN,
}) {
  final x0 = current - target;
  final v0 = velocity;
  final decay = math.exp(-omegaN * dt);
  final offset = x0 * decay + (v0 + omegaN * x0) * dt * decay;
  final newVel = -omegaN * x0 * decay + (v0 + omegaN * x0) * (decay - omegaN * dt * decay);
  return (value: target + offset, velocity: newVel);
}

/// 便捷封装：欠阻尼通用弹簧状态机（对应 WebGL 版 springStep1D）。
class Spring1D {
  double value;
  double velocity;
  final double omegaN;
  final double dampingRatio;

  Spring1D({
    this.value = 0,
    this.velocity = 0,
    this.omegaN = kSpringOmegaN,
    this.dampingRatio = kSpringDampingRatio,
  });

  /// 推进到 [target]，返回是否仍在运动（|距离| 或 |速度| 超过阈值）。
  bool step(double target, double dt) {
    final r = springStepUnderdamped(value, velocity, target, dt,
        omegaN: omegaN, dampingRatio: dampingRatio);
    value = r.value;
    velocity = r.velocity;
    return (value - target).abs() > kSpringThreshold || velocity.abs() > kSpringThreshold;
  }
}

/// 便捷封装：临界阻尼弹簧状态机。
class SpringCritical1D {
  double value;
  double velocity;
  final double omegaN;

  SpringCritical1D({this.value = 0, this.velocity = 0, this.omegaN = kToggleValueOmegaN});

  /// 推进到 [target]，返回是否仍在运动。
  bool step(double target, double dt) {
    final r = springStepCritical(value, velocity, target, dt, omegaN: omegaN);
    value = r.value;
    velocity = r.velocity;
    return (value - target).abs() > kSpringThreshold || velocity.abs() > kSpringThreshold;
  }
}