/// ════════════════════════════════════════════════════════════════════════
/// 昼夜循环 + 光照（R23v · GDD §2.4）
/// ════════════════════════════════════════════════════════════════════════
///
/// 两块能力：
///   1. [DayNightCycle] —— 时相推进器。把真实经过的秒数换算成 0~1 的时相，
///      交给渲染器的 `SkyPalette.at(phase)` 得到天色 + 全局光照系数。
///   2. [PointLight] —— 方块光源。火把 / 篝火 / 熔炉在夜里向周围泼一圈暖光，
///      由渲染器按「面中心到光源的距离」做线性衰减叠加。
///
/// 时相约定（与 `SkyPalette.at` 的关键帧一致）：
///   0.00 黎明 06:00 · 0.25 正午 12:00 · 0.50 黄昏 18:00 · 0.75 午夜 00:00
///
/// 纯数据 + 纯函数，不依赖 Flutter 渲染层，可在测试里直接跑。
library;

import 'dart:math' as math;

import 'voxel_world_types.dart';

/// 昼夜模式。
enum DayNightMode {
  /// 时间流动（默认）。
  flowing('流动'),

  /// 锁定白天（正午）。
  fixedDay('白天'),

  /// 锁定黄昏。
  fixedDusk('黄昏'),

  /// 锁定黑夜（午夜）。
  fixedNight('黑夜');

  const DayNightMode(this.label);
  final String label;

  /// 锁定模式对应的固定时相（流动模式返回 null）。
  double? get lockedPhase => switch (this) {
        DayNightMode.flowing => null,
        DayNightMode.fixedDay => 0.25,
        DayNightMode.fixedDusk => 0.5,
        DayNightMode.fixedNight => 0.75,
      };

  /// 循环切到下一档（HUD 时钟点一下换一档）。
  DayNightMode get next =>
      DayNightMode.values[(index + 1) % DayNightMode.values.length];
}

/// 昼夜循环推进器（可变状态，由视图每帧 `advance`）。
class DayNightCycle {
  DayNightCycle({
    double phase = 0.25,
    this.dayLength = 1200,
    DayNightMode mode = DayNightMode.flowing,
  })  : _phase = _wrap(phase),
        _mode = mode;

  /// 一整天的真实秒数（默认 1200 s = 20 分钟一昼夜，对齐我的世界；
  /// 1 秒 = 20 ticks → 24000 ticks 一整天 = MC 标准）。
  final double dayLength;

  double _phase;
  DayNightMode _mode;

  /// 当前时相 ∈ [0,1)。
  double get phase => _mode.lockedPhase ?? _phase;

  /// 当前模式。
  DayNightMode get mode => _mode;

  set mode(DayNightMode m) {
    // 从锁定切回流动时，从当前显示的时相接着走，避免时间突跳。
    if (_mode != DayNightMode.flowing) _phase = _mode.lockedPhase ?? _phase;
    _mode = m;
  }

  /// 推进 [dt] 秒（锁定模式下不动）。返回是否发生了可见变化。
  bool advance(double dt) {
    if (_mode != DayNightMode.flowing || dt <= 0) return false;
    _phase = _wrap(_phase + dt / dayLength);
    return true;
  }

  /// 直接设定时相（调试 / 存档恢复）。
  void setPhase(double p) => _phase = _wrap(p);

  /// 24 小时制小时数（浮点，0~24）。
  double get hour => (phase * 24 + 6) % 24;

  /// 时钟串 `HH:MM`。
  String get clock {
    final double h = hour;
    final int hh = h.floor();
    final int mm = ((h - hh) * 60).floor();
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  /// 是否处于夜间（怪物生成 / 方块光生效的判定）。
  bool get isNight => phase > 0.58 && phase < 0.94;

  /// 太阳（夜里是月亮）方向的单位向量：从世界指向光源。
  ///
  /// 正午在头顶偏南，日出偏东、日落偏西；夜里高度为负（月亮以微弱补光代替）。
  ({double x, double y, double z}) get sunDir {
    // 日出（phase 0）在 +X 方向，正午头顶，日落 -X。
    final double a = (phase - 0.25) * 2 * math.pi;
    final double y = math.cos(a);
    final double x = -math.sin(a);
    const double z = -0.35; // 略偏南，避免正南北面完全等亮
    final double len = math.sqrt(x * x + y * y + z * z);
    return (x: x / len, y: y / len, z: z / len);
  }

  /// 方向光权重：白天强、夜里几乎没有（只剩环境光）。
  double get sunWeight {
    final double e = sunDir.y; // 太阳高度
    return e <= 0 ? 0.0 : (e * 0.9).clamp(0.0, 0.9);
  }

  static double _wrap(double p) => ((p % 1) + 1) % 1;

  DayNightCycle copy() =>
      DayNightCycle(phase: _phase, dayLength: dayLength, mode: _mode);
}

/// 点光源（方块光）：世界坐标 + 强度 + 半径。
class PointLight {
  const PointLight({
    required this.x,
    required this.y,
    required this.z,
    required this.strength,
    required this.range,
    required this.tint,
  });

  /// 光源中心（方块中心，世界坐标）。
  final double x, y, z;

  /// 峰值强度（叠加到面亮度上的系数）。
  final double strength;

  /// 影响半径（格，线性衰减到 0）。
  final double range;

  /// 光色（暖橙 / 冷白，按发光方块类型）。
  final int tint;

  /// 面中心 [(fx,fy,fz)] 处得到的光强（超出半径为 0）。
  double intensityAt(double fx, double fy, double fz) {
    final double dx = x - fx;
    final double dy = y - fy;
    final double dz = z - fz;
    final double d2 = dx * dx + dy * dy + dz * dz;
    final double r2 = range * range;
    if (d2 >= r2) return 0;
    // 平方衰减更接近真实，但线性在低分辨率体素上更"干净"，取二者折中。
    final double t = 1 - math.sqrt(d2) / range;
    return strength * t * t;
  }
}

/// 发光方块表：方块类型 → (强度, 半径, 光色)。
///
/// 只有玩家放置的功能方块会发光，地形生成不会产生光源，
/// 所以世界里的光源集合天然稀疏，逐面遍历成本可忽略。
const Map<Voxel, ({double strength, double range, int tint})> kBlockLights =
    <Voxel, ({double strength, double range, int tint})>{
  Voxel.torch: (strength: 0.95, range: 9.0, tint: 0xFFFFB865),
  Voxel.campfire: (strength: 0.85, range: 11.0, tint: 0xFFFF9A45),
  Voxel.furnace: (strength: 0.45, range: 6.0, tint: 0xFFFFC98A),
  Voxel.gold: (strength: 0.18, range: 4.0, tint: 0xFFFFE9A8),
  Voxel.diamond: (strength: 0.20, range: 4.5, tint: 0xFFBFF6FF),
};

/// 方块自发光亮度（画自己时的地板亮度，夜里也不会全黑）。
double selfEmissionOf(Voxel v) => switch (v) {
      Voxel.torch => 1.15,
      Voxel.campfire => 1.05,
      Voxel.furnace => 0.85,
      Voxel.gold => 0.72,
      Voxel.diamond => 0.74,
      _ => 0.0,
    };
