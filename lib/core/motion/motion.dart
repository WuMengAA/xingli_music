import 'dart:math';

import 'package:flutter/animation.dart';

/// 动画引擎（对应规格 Module 4：motor 包，曲线 + 弹簧）
///
/// 提供两类能力：
///  1. 命名曲线：直线 / 轻柔 / 干脆 / 平滑 / 安静，以及 Cupertino 风格回弹曲线
///     （[CupertinoMotion.bouncy] 等）。
///  2. 弹簧数值模型 [SpringMotion]：可程序化采样任意时刻的位移 / 速度，
///     参数为物理直觉的 mass / stiffness / damping。
///
/// 整个 App 的过渡统一从此处取曲线，避免散落的 Curves.xxx 与手写 sin 脉冲。
class Motion {
  const Motion._();

  /// 线性（无缓动）
  static const Curve linear = Curves.linear;

  /// 轻柔：ease-out cubic，适合面板、卡片淡入
  static const Curve gentle = Curves.easeOutCubic;

  /// 干脆：ease-out expo，适合切换、入场
  static const Curve snappy = Curves.easeOutExpo;

  /// 平滑：ease-in-out cubic，适合背景 / 尺寸过渡
  static const Curve smooth = Curves.easeInOutCubic;

  /// 安静：ease-in cubic，适合收起 / 退场
  static const Curve calm = Curves.easeInCubic;

  /// Cupertino 风格曲线集合（对应规格 CupertinoMotion）
  static const CupertinoMotion cupertino = CupertinoMotion();

  /// 构造一个弹簧曲线（基于给定物理参数）
  static Curve springCurve({
    double mass = 1.0,
    double stiffness = 170.0,
    double damping = 22.0,
  }) =>
      _SpringCurve(SpringMotion(
        mass: mass,
        stiffness: stiffness,
        damping: damping,
      ));

  /// 构造一个弹簧数值模型（可程序化采样）
  static SpringMotion spring({
    double mass = 1.0,
    double stiffness = 170.0,
    double damping = 22.0,
  }) =>
      SpringMotion(
        mass: mass,
        stiffness: stiffness,
        damping: damping,
      );
}

/// Cupertino 风格回弹曲线集合（对应规格 CupertinoMotion.bouncy）
class CupertinoMotion {
  const CupertinoMotion();

  /// 回弹：带轻微过冲，落下时"弹"一下
  Curve get bouncy => _BouncyCurve();

  /// 衰减：快速到位后轻微回弹（近似 iOS 标准过渡）
  Curve get decay => _DecayCurve();

  /// 标准 UI 过渡
  Curve get standard => Curves.easeInOut;
}

/// 弹簧数值模型：物理直觉的 mass / stiffness / damping
///
/// [valueAt] 给出从 0 到 1 的位移比例（可能过冲 >1 再回落），
/// 适合驱动自定义动画（如卡片缩放、光晕呼吸）。
class SpringMotion {
  const SpringMotion({
    required this.mass,
    required this.stiffness,
    required this.damping,
  });

  final double mass;
  final double stiffness;
  final double damping;

  /// 在时刻 [t]（秒）的位移比例（0 → 1，欠阻尼会过冲后回落）
  double valueAt(double t) {
    if (t <= 0) return 0.0;
    final double w0 = sqrt(stiffness / mass);
    final double zeta = damping / (2 * sqrt(stiffness * mass));
    if (zeta < 1) {
      final double wd = w0 * sqrt(1 - zeta * zeta);
      final double e = exp(-zeta * w0 * t);
      final double s = (zeta / sqrt(1 - zeta * zeta)) * sin(wd * t);
      return 1 - e * (cos(wd * t) + s);
    } else if (zeta == 1) {
      final double e = exp(-w0 * t);
      return 1 - e * (1 + w0 * t);
    } else {
      final double wd = w0 * sqrt(zeta * zeta - 1);
      final double e = exp(-zeta * w0 * t);
      final double k = zeta / sqrt(zeta * zeta - 1);
      // x = 1 - e·[cosh(wd·t) + k·sinh(wd·t)]
      //   = 1 - (e/2)·[(1+k)·e^{wdt} + (1-k)·e^{-wdt}]
      final double term =
          (1 + k) * exp(wd * t) + (1 - k) * exp(-wd * t);
      return 1 - e * 0.5 * term;
    }
  }
}

/// 弹簧曲线：把 [SpringMotion] 适配为 Flutter [Curve]
///
/// 约定归一化进度映射到 0.6s 的弹簧过程（约一个结算周期），
/// 让 AnimatedContainer / AnimatedScale 等也能用弹簧手感。
class _SpringCurve extends Curve {
  const _SpringCurve(this._spring);
  final SpringMotion _spring;
  @override
  double transform(double t) {
    if (t <= 0) return 0.0;
    if (t >= 1) return 1.0;
    return _spring.valueAt(t * 0.6);
  }
}

/// 回弹曲线：带轻微过冲（elasticOut 的轻量版）
class _BouncyCurve extends Curve {
  @override
  double transform(double t) {
    if (t <= 0) return 0.0;
    if (t >= 1) return 1.0;
    const double c4 = pi * 2 / 3;
    return (pow(2.0, -10 * t) * sin((t * 10 - 0.75) * c4) + 1.0).toDouble();
  }
}

/// 衰减曲线：快速到位，无过冲（比 easeOutCubic 更"干脆"）
class _DecayCurve extends Curve {
  @override
  double transform(double t) {
    if (t <= 0) return 0.0;
    if (t >= 1) return 1.0;
    return (1.0 - pow(1.0 - t, 5)).toDouble();
  }
}
