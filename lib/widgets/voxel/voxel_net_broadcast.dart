/// ════════════════════════════════════════════════════════════════════════
/// 联机广播节流（cl79）：纯 Dart，无 Flutter 依赖，可单测。
///
/// 背景（条目2 联机带宽）：此前每 100ms（10Hz）无条件全量广播玩家机位/视角，
/// 静止与微动也发，多人场景带宽/CPU 浪费。本文件抽出「是否值得广播」的判定：
/// 位移超阈值或视角变化超阈值才发；完全静止不发（世界视图另带 5s 静止心跳
/// 兜底，保证新加入的同伴能看到静止玩家）。
/// ════════════════════════════════════════════════════════════════════════
library;

/// 归一化角度差（度），处理 yaw 环绕（如 359°→0° 实际只差 1°，而非 359°）。
double _angleDiff(double a, double b) {
  double d = (a - b) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d.abs();
}

/// 判断是否需要广播玩家机位/视角（联机带宽节流）。
///
/// [prev*] 为上次已广播值（任一为 `null` 视为首次，必发）；[cur*] 为当前值。
/// 水平位移 > [moveThreshold] 米（默认 0.1）或 yaw/pitch 变化 > [angleThreshold]
/// 度（默认 1.0）才返回 `true`；否则 `false`（静止 / 微动不发）。
bool shouldBroadcastTransform(
  double? prevX,
  double? prevY,
  double? prevZ,
  double? prevYaw,
  double? prevPitch,
  double curX,
  double curY,
  double curZ,
  double curYaw,
  double curPitch, {
  double moveThreshold = 0.1,
  double angleThreshold = 1.0,
}) {
  if (prevX == null ||
      prevY == null ||
      prevZ == null ||
      prevYaw == null ||
      prevPitch == null) {
    return true;
  }
  final double dx = curX - prevX;
  final double dy = curY - prevY;
  final double dz = curZ - prevZ;
  if (dx * dx + dy * dy + dz * dz > moveThreshold * moveThreshold) return true;
  if (_angleDiff(curYaw, prevYaw) > angleThreshold) return true;
  if (_angleDiff(curPitch, prevPitch) > angleThreshold) return true;
  return false;
}
