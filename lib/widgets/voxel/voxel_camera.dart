/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 · 透视相机（Phase 1 · 纯数学，不依赖 Flutter widgets）
/// ════════════════════════════════════════════════════════════════════════
///
/// 坐标系（与 `docs/体素世界技术方案.md` §2.2 一致）：右手系，
/// **X 向东、Y 向上、Z 向南**；方块 `(x,y,z)` 占据 `[x,x+1]×[y,y+1]×[z,z+1]`。
///
/// 视图变换用**基向量点乘**而非 4×4 矩阵乘（省一半乘法）：
/// ```
/// forward = (sin(yaw)·cos(pitch),  sin(pitch),  cos(yaw)·cos(pitch))
/// right   = (cos(yaw),             0,          -sin(yaw))
/// up      = forward × right = (-sin(yaw)·sin(pitch), cos(pitch), -cos(yaw)·sin(pitch))
///
/// d = world - eye;  viewX = d·right;  viewY = d·up;  viewZ = d·forward
/// ```
/// 透视投影（viewport = W×H，`f = 1/tan(fov/2)`，`aspect = W/H`）：
/// ```
/// screenX = W/2 + (viewX · f / aspect) / viewZ · (W/2)
/// screenY = H/2 - (viewY · f)          / viewZ · (H/2)
/// depth   = viewZ                       // > near 才可见
/// ```
///
/// 近裁剪默认做**整面丢弃**（`projectWith`：任一顶点 `viewZ < near` 即丢，用于
/// 天象 / 选区 / LOD 等远距离几何）；逐方块面改用 `projectFaceClipped` 做
/// Sutherland–Hodgman 单平面**多边形裁剪**（S1：根治贴脸墙面的穿墙）。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Size;

import 'voxel_world.dart';
import 'voxel_world_types.dart';

/// 轻量三维向量（不引 vector_math，避免新依赖）。
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  static const Vec3 zero = Vec3(0, 0, 0);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 get normalized {
    final double l = length;
    return l < 1e-9 ? Vec3.zero : Vec3(x / l, y / l, z / l);
  }

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}

/// 投影结果：屏幕像素 + 相机空间深度。
class ScreenPoint {
  const ScreenPoint(this.x, this.y, this.depth);

  final double x;
  final double y;

  /// 相机空间 `viewZ`，越大越远（用于画家算法排序与雾）。
  final double depth;

  Offset get offset => Offset(x, y);

  @override
  String toString() =>
      'ScreenPoint(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, d=${depth.toStringAsFixed(2)})';
}

/// S1：近平面裁剪后的面多边形结果（由 [VoxelCamera.projectFaceClipped] 返回）。
///
/// [xy] 长度 = `n * 2`（屏幕像素，顶点环绕序）；[uv] 同长（可空）；[n] ∈ {3,4,5}。
/// [n]==4 时 [xy]/[uv] 为原四边形（快路径），[n]∈{3,5} 为裁剪薄片。
class ClippedFace {
  ClippedFace(this.xy, this.uv, this.n, this.depth);

  final Float32List xy;
  final Float32List? uv;
  final int n;
  final double depth;
}

/// 预计算的视图基（三角函数每帧只算一次，逐顶点复用）。
///
/// 字段拆成 double 而非 [Vec3]，是为了让渲染器内层循环零对象分配。
class ViewBasis {
  ViewBasis({
    required this.eyeX,
    required this.eyeY,
    required this.eyeZ,
    required this.rightX,
    required this.rightY,
    required this.rightZ,
    required this.upX,
    required this.upY,
    required this.upZ,
    required this.fwdX,
    required this.fwdY,
    required this.fwdZ,
  });

  final double eyeX, eyeY, eyeZ;
  final double rightX, rightY, rightZ;
  final double upX, upY, upZ;
  final double fwdX, fwdY, fwdZ;

  Vec3 get forward => Vec3(fwdX, fwdY, fwdZ);
  Vec3 get right => Vec3(rightX, rightY, rightZ);
  Vec3 get up => Vec3(upX, upY, upZ);
}

/// 视口相关的投影常量（每帧算一次）。
class ProjectionParams {
  const ProjectionParams({
    required this.halfW,
    required this.halfH,
    required this.scaleX,
    required this.scaleY,
    required this.near,
  });

  final double halfW;
  final double halfH;

  /// `f / aspect * halfW`。
  final double scaleX;

  /// `f * halfH`。
  final double scaleY;

  final double near;
}

/// 透视相机（不可变；旋转 / 移动返回新实例，便于 Phase 4 取景快照复现）。
class VoxelCamera {
  VoxelCamera({
    required this.position,
    this.yaw = 0.0,
    this.pitch = -0.35,
    this.fov = 1.0472, // 60°
    this.near = 0.06,
    this.far = 64.0,
    this.fullWidth = false,
  });

  /// 俯瞰全景机位：站在世界南侧外，朝 +Z 看向世界中心。
  ///
  /// **全图视角（[fullWidth]=true）**：水平视野固定（投影端处理），
  /// 相机距离拉到覆盖世界对角线——竖屏（aspect<1）下世界也能完整
  /// 铺满宽度，而不是被窄水平视野裁成"屏幕上方一条"（R23 真机实测
  /// 安卓竖屏 aspect≈0.45 时水平视野仅 29°，24 格世界只能看到 8 格）。
  factory VoxelCamera.overview(VoxelWorld world) {
    final double cx = world.sizeX / 2;
    final double cz = world.sizeZ / 2;
    final double diag =
        math.sqrt(world.sizeX * world.sizeX + world.sizeZ * world.sizeZ);
    // 相机距中心 ≈0.9×对角线：水平 60° 视野下完整覆盖全图。
    final double radius = diag * 0.9;
    final double height = world.maxY * 0.75 + 1.0;
    final double groundY = world.waterLevel + 1.0;
    return VoxelCamera(
      position: Vec3(cx, height, cz - radius),
      // yaw = 0 ⇒ forward 水平分量指向 +Z，正对世界中心。
      pitch: -math.atan2(height - groundY, radius),
      fullWidth: true,
      // R23u：maxY 升到 256 后相机随之升高，俯视地形深度远超默认 far=64，
      // 必须放大 far 否则整帧被裁成空白（拍照/俯瞰视图）。
      far: 1024.0,
    );
  }

  /// 2.5D 等距视角（R23）：像 2.5D 场景一样斜 45° 俯视整个体素世界。
  ///
  /// 相机在世界东南角上空，看向西北对角线；全图视角（[fullWidth]=true）
  /// 保证竖屏下世界完整铺满宽度。
  factory VoxelCamera.iso2d5(VoxelWorld world) {
    final double cx = world.sizeX / 2;
    final double cz = world.sizeZ / 2;
    final double diag =
        math.sqrt(world.sizeX * world.sizeX + world.sizeZ * world.sizeZ);
    final double radius = diag * 0.95;
    final double height = world.maxY * 1.2 + 4.0;
    final double groundY = world.waterLevel + 1.0;
    // 东南角：+X +Z 方向；yaw = 5π/4 ⇒ 视线指向西北（-X -Z）中心。
    return VoxelCamera(
      position: Vec3(cx + radius * 0.707, height, cz + radius * 0.707),
      yaw: 5 * math.pi / 4,
      pitch: -math.atan2(height - groundY, radius),
      fullWidth: true,
      far: 1024.0,
    );
  }

  /// 相机世界坐标（方块为单位，可小数）。
  final Vec3 position;

  /// 偏航（弧度，绕 Y 轴；0 = 朝 +Z）。
  final double yaw;

  /// 俯仰（弧度；负 = 俯视）。
  final double pitch;

  /// 垂直视场角（弧度）。
  final double fov;

  final double near;
  final double far;

  /// 全图视角（俯瞰 / 2.5D）：投影时**水平视野固定为 [fov]**，垂直视野随
  /// 视口 aspect 放大且各向同性（不变形）——窄屏（竖屏手机）下世界完整
  /// 铺满宽度，而不是被标准垂直-fov 投影压成"屏幕上方一条"。
  final bool fullWidth;

  /// 俯仰硬限位（±88.8°，R26l：允许朝正上/正下。基向量由 sin/cos 直接
  /// 构造、恒正交归一（right 恒水平），无需动态 Up / 四元数也不会有万向节锁；
  /// 留 1.2° 余量避免 cp=0 数值边缘）。
  static const double maxPitch = 1.55;

  /// 视场角限位（约 31.5°~110°）。
  ///
  /// R26o：上限从 2.094(120°) 收到 1.92(110°)——极广角 + 近裁剪镜像会让
  /// 身后几何倒置（用户「拉倒广角画面颠倒」）；硬丢弃近裁剪后广角仍需留
  /// 安全余量。fullWidth（俯瞰/2.5D）模式下 [fov] 即水平视野；
  /// 第一/三人称（fullWidth=false）为垂直视野（水平由 aspect 推导）。
  static const double minFov = 0.55;
  static const double maxFov = 1.92;

  /// 眼高（walk/第一人称模式贴地时用；R23 用户定版：人物 1.6 米）。
  static const double eyeHeight = 1.6;

  /// 第一人称跳跃高度（米，R26r5：1.25m 最高点，≈MC；配合 gravity=32
  /// 滞空约 0.5s，可跨上 1 格台阶）。
  static const double jumpHeight = 1.25;

  /// 第一人称重力加速度（方块 / 秒²，R26r5：32 ≈ MC 手感——2 格落不伤、
  /// 3 格起摔伤）。
  static const double gravity = 32.0;

  late final ViewBasis basis = _buildBasis();

  ViewBasis _buildBasis() {
    final double sy = math.sin(yaw);
    final double cy = math.cos(yaw);
    final double sp = math.sin(pitch);
    final double cp = math.cos(pitch);
    return ViewBasis(
      eyeX: position.x,
      eyeY: position.y,
      eyeZ: position.z,
      rightX: cy,
      rightY: 0,
      rightZ: -sy,
      upX: -sy * sp,
      upY: cp,
      upZ: -cy * sp,
      fwdX: sy * cp,
      fwdY: sp,
      fwdZ: cy * cp,
    );
  }

  /// 视线方向（单位向量）。
  Vec3 forwardVector() => basis.forward;

  /// 相机右方（水平，单位向量）。
  Vec3 rightVector() => basis.right;

  /// 相机上方（单位向量）。
  Vec3 upVector() => basis.up;

  /// 水平前向（忽略俯仰，用于行走）。
  Vec3 walkForward() => Vec3(math.sin(yaw), 0, math.cos(yaw));

  /// 视口相关投影常量。
  ProjectionParams projectionFor(Size viewport, {bool? horizontalFov}) {
    final double w = viewport.width <= 0 ? 1 : viewport.width;
    final double h = viewport.height <= 0 ? 1 : viewport.height;
    final double halfW = w / 2;
    final double halfH = h / 2;
    if (horizontalFov ?? fullWidth) {
      // 全图视角：水平视野固定 = fov；垂直方向保持各向同性（scaleY=scaleX，
      // 像素等距不变形）。竖屏 aspect<1 时垂直视野自动放大（>60°），
      // 世界完整铺满宽度。否则标准垂直-fov 在竖屏下水平视野被压到 ~29°，
      // 世界只显示中间一条（R23 真机"上方一条+9/10 黑屏"的根因）。
      final double scale = (1 / math.tan(fov / 2)) * halfW;
      return ProjectionParams(
        halfW: halfW,
        halfH: halfH,
        scaleX: scale,
        scaleY: scale,
        near: near,
      );
    }
    // 标准（自由视角 / 第一人称）：垂直视野 = fov。
    final double f = 1 / math.tan(fov / 2);
    final double aspect = w / h;
    return ProjectionParams(
      halfW: halfW,
      halfH: halfH,
      scaleX: f / aspect * halfW,
      scaleY: f * halfH,
      near: near,
    );
  }

  /// 世界点 → 屏幕点；在近平面之后（或超出 [far]）返回 null。
  ScreenPoint? project(Vec3 worldPoint, Size viewport) {
    final ProjectionParams p = projectionFor(viewport);
    return projectWith(worldPoint.x, worldPoint.y, worldPoint.z, basis, p);
  }

  /// 已预计算 basis / params 的快速投影（渲染器内层循环用，零分配路径的入口）。
  static ScreenPoint? projectWith(
    double wx,
    double wy,
    double wz,
    ViewBasis b,
    ProjectionParams p,
  ) {
    final double dx = wx - b.eyeX;
    final double dy = wy - b.eyeY;
    final double dz = wz - b.eyeZ;
    final double viewZ = dx * b.fwdX + dy * b.fwdY + dz * b.fwdZ;
    // R26o：近裁剪改回**硬丢弃**（viewZ < near → 整面丢弃）——R26l 的「夹紧
    // 到 0.02」会把相机**身后**的顶点镜像投影到屏幕边缘，广角/FOV 大时身后
    // 几何变多 → 画面颠倒（用户「拉倒广角颠倒」）。看脚下方块已由 AABB
    // 视锥剔除（R26n）正确保留，不再需要夹紧。
    if (viewZ < p.near) return null;
    final double viewX = dx * b.rightX + dy * b.rightY + dz * b.rightZ;
    final double viewY = dx * b.upX + dy * b.upY + dz * b.upZ;
    final double inv = 1 / viewZ;
    return ScreenPoint(
      p.halfW + viewX * p.scaleX * inv,
      p.halfH - viewY * p.scaleY * inv,
      viewZ,
    );
  }

  /// S1：带近平面多边形裁剪的面投影。根治「小空间穿墙」——贴脸墙面常跨过眼
  /// 平面，单个顶点 `viewZ < near` 时旧 `projectWith` 整面硬丢弃 → 看穿墙。
  /// 改为 **Sutherland–Hodgman 单平面裁剪**（clip 非 clamp）：保留 `viewZ >= near`
  /// 一侧，在眼平面处按 `t=(near−zi)/(zj−zi)` 世界空间插值生成新顶点，得 3~5 边形。
  ///
  /// 全 4 顶点 `viewZ >= near` → 走原 4 顶点快路径（零额外拓扑变化，沿用
  /// `pushFace` 的逐角 AO / 描边）；全 `< near` → 返回 null（整面丢弃）；
  /// 混合 → 裁剪出 3~5 边形薄片（路由到 `_pushPolygon`）。
  ///
  /// [corners]：12 个 double（4 顶点 × (x,y,z)，四边形环绕序）。
  /// [uv]：8 个 double（4 顶点 × (u,v)，可空 → 无贴图不裁剪 uv）。
  static ClippedFace? projectFaceClipped(
    Float64List corners,
    Float32List? uv,
    ViewBasis b,
    ProjectionParams p,
  ) {
    // 1) 4 顶点相机空间深度（viewZ = d·fwd）。
    final double z0 = (corners[0] - b.eyeX) * b.fwdX +
        (corners[1] - b.eyeY) * b.fwdY +
        (corners[2] - b.eyeZ) * b.fwdZ;
    final double z1 = (corners[3] - b.eyeX) * b.fwdX +
        (corners[4] - b.eyeY) * b.fwdY +
        (corners[5] - b.eyeZ) * b.fwdZ;
    final double z2 = (corners[6] - b.eyeX) * b.fwdX +
        (corners[7] - b.eyeY) * b.fwdY +
        (corners[8] - b.eyeZ) * b.fwdZ;
    final double z3 = (corners[9] - b.eyeX) * b.fwdX +
        (corners[10] - b.eyeY) * b.fwdY +
        (corners[11] - b.eyeZ) * b.fwdZ;
    final bool a0 = z0 >= p.near;
    final bool a1 = z1 >= p.near;
    final bool a2 = z2 >= p.near;
    final bool a3 = z3 >= p.near;
    final int inCount =
        (a0 ? 1 : 0) + (a1 ? 1 : 0) + (a2 ? 1 : 0) + (a3 ? 1 : 0);

    if (inCount == 4) {
      // 快路径：4 顶点全部在眼前 → 原投影（零裁剪成本，拓扑不变）。
      final Float32List xy = Float32List(8);
      double dsum = 0;
      final List<double> zs = <double>[z0, z1, z2, z3];
      for (int i = 0; i < 4; i++) {
        final ScreenPoint sp = _projectWithZ(
            corners[i * 3], corners[i * 3 + 1], corners[i * 3 + 2], zs[i], b, p);
        xy[i * 2] = sp.x;
        xy[i * 2 + 1] = sp.y;
        dsum += sp.depth;
      }
      return ClippedFace(xy, uv, 4, dsum / 4);
    }
    if (inCount == 0) return null;

    // 混合：Sutherland–Hodgman 单平面裁剪（保留 viewZ >= near 一侧）。
    // 输出世界顶点（最多 5）+ uv（若传入）。
    final Float64List ow = Float64List(15);
    final Float32List ou = Float32List(10);
    int on = 0;
    final List<double> sx = <double>[corners[0], corners[3], corners[6], corners[9]];
    final List<double> sy = <double>[corners[1], corners[4], corners[7], corners[10]];
    final List<double> sz = <double>[corners[2], corners[5], corners[8], corners[11]];
    final List<double> szz = <double>[z0, z1, z2, z3];
    final List<bool> sa = <bool>[a0, a1, a2, a3];
    final List<double> su = uv == null
        ? const <double>[]
        : <double>[uv[0], uv[2], uv[4], uv[6]];
    final List<double> sv = uv == null
        ? const <double>[]
        : <double>[uv[1], uv[3], uv[5], uv[7]];
    for (int i = 0; i < 4; i++) {
      final int j = (i + 1) % 4;
      if (sa[i]) {
        ow[on * 3] = sx[i];
        ow[on * 3 + 1] = sy[i];
        ow[on * 3 + 2] = sz[i];
        if (uv != null) {
          ou[on * 2] = su[i];
          ou[on * 2 + 1] = sv[i];
        }
        on++;
      }
      if (sa[i] != sa[j]) {
        // 边跨越近平面 → 交点 t=(near−zi)/(zj−zi)，新顶点恰在 viewZ=near 上。
        final double t = (p.near - szz[i]) / (szz[j] - szz[i]);
        ow[on * 3] = sx[i] + (sx[j] - sx[i]) * t;
        ow[on * 3 + 1] = sy[i] + (sy[j] - sy[i]) * t;
        ow[on * 3 + 2] = sz[i] + (sz[j] - sz[i]) * t;
        if (uv != null) {
          ou[on * 2] = su[i] + (su[j] - su[i]) * t;
          ou[on * 2 + 1] = sv[i] + (sv[j] - sv[i]) * t;
        }
        on++;
      }
    }
    // 投影裁剪后多边形（所有顶点 viewZ >= near）。
    final Float32List xy = Float32List(on * 2);
    final Float32List? fuv = uv == null ? null : Float32List(on * 2);
    double dsum = 0;
    for (int k = 0; k < on; k++) {
      final ScreenPoint sp =
          _projectSafe(ow[k * 3], ow[k * 3 + 1], ow[k * 3 + 2], b, p);
      xy[k * 2] = sp.x;
      xy[k * 2 + 1] = sp.y;
      dsum += sp.depth;
      if (fuv != null) {
        fuv[k * 2] = ou[k * 2];
        fuv[k * 2 + 1] = ou[k * 2 + 1];
      }
    }
    return ClippedFace(xy, fuv, on, dsum / on);
  }

  /// 已算好 viewZ 的快速投影（clip 快路径用；viewZ 已保证 >= near）。
  static ScreenPoint _projectWithZ(
    double wx,
    double wy,
    double wz,
    double vz,
    ViewBasis b,
    ProjectionParams p,
  ) {
    final double z = vz < p.near ? p.near : vz; // 仅捕获 FP 边界
    final double dx = wx - b.eyeX;
    final double dy = wy - b.eyeY;
    final double dz = wz - b.eyeZ;
    final double vx = dx * b.rightX + dy * b.rightY + dz * b.rightZ;
    final double vy = dx * b.upX + dy * b.upY + dz * b.upZ;
    final double inv = 1 / z;
    return ScreenPoint(
      p.halfW + vx * p.scaleX * inv,
      p.halfH - vy * p.scaleY * inv,
      z,
    );
  }

  /// 裁剪后顶点的安全投影：viewZ < near 时夹紧到 near（仅 FP 边界——几何
  /// 已被裁剪到 >= near 一侧），避免 `projectWith` 返回 null 丢顶点。
  static ScreenPoint _projectSafe(
    double wx,
    double wy,
    double wz,
    ViewBasis b,
    ProjectionParams p,
  ) {
    final double dx = wx - b.eyeX;
    final double dy = wy - b.eyeY;
    final double dz = wz - b.eyeZ;
    final double vz = dx * b.fwdX + dy * b.fwdY + dz * b.fwdZ;
    final double z = vz < p.near ? p.near : vz;
    final double vx = dx * b.rightX + dy * b.rightY + dz * b.rightZ;
    final double vy = dx * b.upX + dy * b.upY + dz * b.upZ;
    final double inv = 1 / z;
    return ScreenPoint(
      p.halfW + vx * p.scaleX * inv,
      p.halfH - vy * p.scaleY * inv,
      z,
    );
  }

  /// 世界点 → 相机空间（供视锥 / 音效方向复用）。
  Vec3 toView(Vec3 world) {
    final ViewBasis b = basis;
    final double dx = world.x - b.eyeX;
    final double dy = world.y - b.eyeY;
    final double dz = world.z - b.eyeZ;
    return Vec3(
      dx * b.rightX + dy * b.rightY + dz * b.rightZ,
      dx * b.upX + dy * b.upY + dz * b.upZ,
      dx * b.fwdX + dy * b.fwdY + dz * b.fwdZ,
    );
  }

  /// 旋转（弧度增量）；pitch 夹在 ±[maxPitch]。
  VoxelCamera rotate(double dYaw, double dPitch) {
    double ny = (yaw + dYaw) % (2 * math.pi);
    if (ny < 0) ny += 2 * math.pi;
    return copyWith(
      yaw: ny,
      pitch: (pitch + dPitch).clamp(-maxPitch, maxPitch),
    );
  }

  /// 变焦：[factor] > 1 拉近（fov 变小）。
  VoxelCamera zoom(double factor) {
    if (factor <= 0) return this;
    return copyWith(fov: (fov / factor).clamp(minFov, maxFov));
  }

  /// 平移（相机局部步进，单位 = 方块）。
  ///
  /// - [forward] 沿水平前向（忽略俯仰，避免"前进就往地里钻"）；
  /// - [strafe] 沿右方；[lift] 沿世界 +Y。
  /// - 传入 [world] 时：XZ 夹在世界内缩 1 格；
  ///   [stickToGround] 为真时贴地（眼高 = 地面 + [eyeHeight]），
  ///   否则只保证不低于地面 0.4 格。
  ///
  /// **水面可过**：地面高度用 `occludes`（水不遮挡）判定，
  /// 因此走进水里会自然下沉半身，而不是被当成墙挡住。
  VoxelCamera move({
    double forward = 0,
    double strafe = 0,
    double lift = 0,
    VoxelWorld? world,
    bool stickToGround = false,
  }) {
    if (forward == 0 && strafe == 0 && lift == 0) return this;
    final double sy = math.sin(yaw);
    final double cy = math.cos(yaw);
    double nx = position.x + sy * forward + cy * strafe;
    double nz = position.z + cy * forward - sy * strafe;
    double ny = position.y + lift;

    if (world != null) {
      // R23k：无限地图——去掉出生大陆边界空气墙，只留超大软边界兜底。
      const double limit = 1000000.0;
      nx = nx.clamp(-limit, limit);
      nz = nz.clamp(-limit, limit);
      final double ground = groundHeightAt(world, nx, nz);
      if (stickToGround) {
        ny = ground + eyeHeight;
      } else {
        ny = ny.clamp(ground + 0.4, world.maxY + 12.0);
      }
    }
    return copyWith(position: Vec3(nx, ny, nz));
  }

  VoxelCamera copyWith({
    Vec3? position,
    double? yaw,
    double? pitch,
    double? fov,
    double? near,
    double? far,
    bool? fullWidth,
  }) {
    return VoxelCamera(
      position: position ?? this.position,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      fov: fov ?? this.fov,
      near: near ?? this.near,
      far: far ?? this.far,
      fullWidth: fullWidth ?? this.fullWidth,
    );
  }

  /// 地面高度（最高 `occludes` 方块的顶面 y）。
  ///
  /// ⚠️ 不用 [VoxelWorld.surfaceHeight]：它基于 `solid`，会把水面当地表。
  ///
  /// [startY]：从该高度**往下**扫（默认世界顶）。第一人称落地 / 边缘容差传
  /// 脚底高度——树叶已实体化（R26r6），若不限起始高度，站在树下会被头顶的
  /// 树冠误判成"脚下的地"（旧 R26n「被顶到树顶」的根因）；从脚底往下扫，
  /// 脚下没支撑才往下找，树冠不影响地面判定。
  static double groundHeightAt(VoxelWorld world, double x, double z,
      [double? startY]) {
    final int xi = x.floor();
    final int zi = z.floor();
    final int topRaw = startY == null ? world.maxY - 1 : startY.floor();
    final int top =
        topRaw < 0 ? 0 : (topRaw > world.maxY - 1 ? world.maxY - 1 : topRaw);
    for (int y = top; y >= 0; y--) {
      if (world.get(xi, y, zi).occludes) return y + 1.0;
    }
    return 0;
  }

  /// 相机当前是否浸在水里（Phase 2 水下滤镜 / 减速用）。
  bool isUnderwater(VoxelWorld world) =>
      world.get(position.x.floor(), position.y.floor(), position.z.floor()) ==
      Voxel.water;

  @override
  String toString() =>
      'VoxelCamera($position, yaw=${yaw.toStringAsFixed(2)}, '
      'pitch=${pitch.toStringAsFixed(2)}, fov=${fov.toStringAsFixed(2)})';
}

/// 世界中的体素实体（如 AI 陪伴小人），由渲染器当作额外方块盒叠加绘制。
///
/// [position] 为脚底中心点（世界坐标，单位方块），角色沿 +Y 向上生长约 2.2 格。
class VoxelEntity {
  const VoxelEntity({
    required this.position,
    required this.color,
    this.scale = 1.0,
    this.glow = false,
    this.useSkin = false,
    this.swing = 0, // R26r11：走路摇摆角（弧度，四肢绕肩/髋支点摆动，0=静止）
    this.lookYaw = 0, // R26r14：模型绕垂直轴的朝向（弧度）；躯干+四肢随其旋转
    this.lookPitch = 0, // R26r14：头部俯仰（弧度）；头部额外绕 X 轴倾斜跟随视线
  });

  /// 脚底中心（y 贴地）。
  final Vec3 position;

  /// 主体色（ARGB）。无皮肤或贴图失败时作为纯色回退。
  final Color color;

  /// 整体缩放（默认 1.0 ≈ 2.2 格高）。
  final double scale;

  /// R26r11：走路摇摆角（弧度）。>0 表示四肢前后摆动（交叉步态），
  /// 由 `_emitEntity` 应用于左右臂/腿绕肩/髋支点的旋转。
  final double swing;

  /// 是否发光（主动发言时高亮，走半透明 Pass）。
  final bool glow;

  /// 是否使用玩家皮肤贴图（#169）：各面按 MC 2× 皮肤布局采样图集。
  final bool useSkin;

  /// R26r14：模型整体绕垂直轴（Y）的朝向（弧度）。躯干+四肢随其旋转，
  /// 使「身体跟随头部 / 头部跟随视线」——第三人称下玩家朝向跟随相机朝向。
  final double lookYaw;

  /// R26r14：头部俯仰（弧度）。头部在整体朝向基础上额外绕水平轴倾斜，
  /// 跟随相机俯仰（视线上下），呈现「头部跟随视线」。
  final double lookPitch;
}
