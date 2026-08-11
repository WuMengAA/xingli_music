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
/// 近裁剪只做**整面丢弃**（任一顶点 `viewZ < near` 即丢），不做多边形裁剪；
/// 由移动时的贴地 / 边界约束把相机挡在方块外，代价远低于 Sutherland–Hodgman。
library;

import 'dart:math' as math;
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
    this.near = 0.12,
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

  /// 俯仰硬限位（±83°，避免万向节翻转）。
  static const double maxPitch = 1.45;

  /// 视场角限位（约 31.5°~85.9°）。
  static const double minFov = 0.55;
  static const double maxFov = 1.50;

  /// 眼高（walk/第一人称模式贴地时用；R23 用户定版：人物 1.6 米）。
  static const double eyeHeight = 1.6;

  /// 第一人称跳跃高度（米，R24b：1.4 米，滞空足够跨上 1 格台阶）。
  static const double jumpHeight = 1.4;

  /// 第一人称重力加速度（方块 / 秒²，近似 MC）。
  static const double gravity = 22.0;

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
    if (viewZ < p.near) return null; // 简单近裁剪：整面丢弃
    final double viewX = dx * b.rightX + dy * b.rightY + dz * b.rightZ;
    final double viewY = dx * b.upX + dy * b.upY + dz * b.upZ;
    final double inv = 1 / viewZ;
    return ScreenPoint(
      p.halfW + viewX * p.scaleX * inv,
      p.halfH - viewY * p.scaleY * inv,
      viewZ,
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
  static double groundHeightAt(VoxelWorld world, double x, double z) {
    final int xi = x.floor();
    final int zi = z.floor();
    for (int y = world.maxY - 1; y >= 0; y--) {
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
  });

  /// 脚底中心（y 贴地）。
  final Vec3 position;

  /// 主体色（ARGB）。无皮肤或贴图失败时作为纯色回退。
  final Color color;

  /// 整体缩放（默认 1.0 ≈ 2.2 格高）。
  final double scale;

  /// 是否发光（主动发言时高亮，走半透明 Pass）。
  final bool glow;

  /// 是否使用玩家皮肤贴图（#169）：各面按 MC 2× 皮肤布局采样图集。
  final bool useSkin;
}
