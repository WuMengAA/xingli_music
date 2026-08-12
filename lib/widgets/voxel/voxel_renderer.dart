/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 · 渲染管线（Phase 1 · 纯函数，不依赖 Flutter widgets）
/// ════════════════════════════════════════════════════════════════════════
///
/// 输入 [VoxelWorld] + [VoxelCamera] + [RenderConfig]，输出一帧可绘制的
/// [VoxelFrame]（天空调色板 + 不透明面列表 + 半透明面列表，均已投影到屏幕空间）。
/// 管线（`docs/体素世界技术方案.md` §2）：
///
/// ```
/// 列级粗剔除(距离/方位) → 逐方块面收集 → ① 相邻遮挡剔除 → ② 背面剔除
///   → 透视投影(含近裁剪) → 分面着色 + 雾 → 深度降序排序 → 面数预算裁剪
/// ```
///
/// 关键约定：
/// - 遮挡判定一律用 `Voxel.occludes`（`solid && !transparent`），
///   **不能用 `VoxelWorld.isSolid`** —— 水的 `solid == true`，用它会把水下
///   地形面误剔除（水里露空洞）。
/// - 无 Z-buffer，用画家算法：面按相机空间深度**从远到近**绘制；
///   不透明与半透明分两趟，避免"水面盖住它前面的树"。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, Size;

import 'voxel_camera.dart';
import 'voxel_daynight.dart';
import 'voxel_textures.dart';
import 'voxel_world.dart';
import 'voxel_world_types.dart';

/// 立方体的六个面（法线方向）。
enum BlockFace {
  /// +Y
  top,

  /// -Y
  bottom,

  /// -Z
  north,

  /// +Z
  south,

  /// +X
  east,

  /// -X
  west,
}

/// 分面基础亮度（受光方向；§2.5）。
const Map<BlockFace, double> kFaceBrightness = <BlockFace, double>{
  BlockFace.top: 1.00,
  BlockFace.south: 0.86,
  BlockFace.east: 0.78,
  BlockFace.north: 0.70,
  BlockFace.west: 0.62,
  BlockFace.bottom: 0.48,
};

/// 半透明方块的绘制不透明度。
const double kWaterAlpha = 0.62;

/// 一个待绘制的方块面（已投影到屏幕空间）。
class RenderFace {
  RenderFace({
    required this.xy,
    required this.argb,
    required this.depth,
    required this.voxel,
    required this.face,
    this.uv,
    this.tint = 0xFFFFFFFF,
  });

  /// 4 个屏幕顶点（8 个 double，按四边形环绕顺序）。
  final Float32List xy;

  /// 已含分面亮度 + 雾 + alpha 的颜色（ARGB32，供 `Vertices.raw` 直接使用）。
  final int argb;

  /// 面中心的相机空间深度（排序键，越大越远）。
  final double depth;

  final Voxel voxel;
  final BlockFace face;

  /// 贴图 UV（图集像素坐标，8 个 double）；非空表示启用纹理贴图。
  final Float32List? uv;

  /// 贴图调制色（白=原色，远=雾色；乘到纹理上），供 `BlendMode.modulate`。
  final int tint;

  bool get translucent => voxel.isTransparent;
}

/// 批量网格：把同一材质的若干方块面拼进单一顶点缓冲，一次 [ui.Vertices.raw]
/// 提交给 GPU，把「每面一个 drawVertices」(成百上千次 GPU draw call) 折叠成
/// 每材质 1 次 —— 软件光栅器→GPU 硬件渲染的关键加速点（R25）。
///
/// 顶点按 `VertexMode.triangles` 展开：每面 6 顶点（2 三角形）。
/// 线段批次（描边）用 `VertexMode.lines`：每边 2 顶点。
class VoxelMeshBatch {
  const VoxelMeshBatch({
    required this.positions,
    required this.colors,
    this.uv,
  });

  /// 屏幕空间顶点（每面 12 个 double）。
  final Float32List positions;

  /// 每顶点 packed ARGB（与 [positions] 等顶点数）。
  final Int32List colors;

  /// 贴图 UV（仅贴图批次；每面 12 个 double）。
  final Float32List? uv;
}

/// 天空 / 光照调色板（按时相插值）。
class SkyPalette {
  const SkyPalette({
    required this.zenith,
    required this.horizon,
    required this.fog,
    required this.light,
  });

  /// 天顶色。
  final Color zenith;

  /// 地平线色。
  final Color horizon;

  /// 雾色（远处方块向它混合）。
  final Color fog;

  /// 全局光照系数（乘到分面亮度上）。
  final double light;

  /// 时相 → 调色板。[phase] ∈ [0,1)：0 黎明 / 0.25 正午 / 0.5 黄昏 / 0.75 夜。
  static SkyPalette at(double phase) {
    final double p = ((phase % 1) + 1) % 1;
    const List<SkyPalette> keys = <SkyPalette>[
      // 黎明
      SkyPalette(
        zenith: Color(0xFF5B7FB8),
        horizon: Color(0xFFF2B98A),
        fog: Color(0xFFD9BCA6),
        light: 0.78,
      ),
      // 正午
      SkyPalette(
        zenith: Color(0xFF4A8FE0),
        horizon: Color(0xFFBFE0F5),
        fog: Color(0xFFC7DDEE),
        light: 1.0,
      ),
      // 黄昏
      SkyPalette(
        zenith: Color(0xFF3E4E86),
        horizon: Color(0xFFF09A5C),
        fog: Color(0xFFC98C74),
        light: 0.74,
      ),
      // 夜
      SkyPalette(
        zenith: Color(0xFF0C1330),
        horizon: Color(0xFF25325C),
        fog: Color(0xFF1B2445),
        light: 0.52,
      ),
    ];
    final double t = p * keys.length;
    final int i = t.floor() % keys.length;
    final int j = (i + 1) % keys.length;
    final double f = t - t.floor();
    final SkyPalette a = keys[i];
    final SkyPalette b = keys[j];
    return SkyPalette(
      zenith: Color.lerp(a.zenith, b.zenith, f)!,
      horizon: Color.lerp(a.horizon, b.horizon, f)!,
      fog: Color.lerp(a.fog, b.fog, f)!,
      light: a.light + (b.light - a.light) * f,
    );
  }
}

/// 渲染参数（一次性传入，便于按性能档位降级）。
class RenderConfig {
  const RenderConfig({
    this.renderDistance = 28,
    this.maxFaces = 3000,
    this.fogEnabled = true,
    this.occlusionCull = true,
    this.backFaceCull = true,
    // R26r：视锥/方位剔除总开关（用户要求全部关闭以排查透视）。
    this.frustumCull = true,
    this.waterAnimation = true,
    this.skyGradient = true,
    this.viewDistanceChunks = 4,
    this.lodStartChunks = 2,
    this.lodStepChunks = 2,
    // R26p2：云层区块视距（默认 3 区块 = 48 格半径云场覆盖）。
    this.cloudViewDistanceChunks = 3,
    this.textureEnabled = true,
    this.maxChunkBuildsPerFrame = 4,
    // R26p：默认关闭区块级 LOD 面剔除——其 allowMask 启发式只保留「主朝向面」，
    // 会误删走廊/隧道里垂直于视线的侧壁面（剔穿墙）。正确性优先，远处面数已由
    // 分帧构建 + LOD 采样步长 + 视锥/背面剔除共同收敛。
    this.lodFaceCull = false,
    // R26r：区块级 LOD 采样降精度总开关（用户要求关闭 → 全距离满精度）。
    this.lodEnabled = true,
  });

  /// 区块边长（格，R23m：16×16 一区块，MC 惯例）。
  static const int chunkSize = 16;

  /// 列级距离剔除半径（方块；区块机制下仍参与距离裁剪）。
  final double renderDistance;

  /// 每帧面数硬上限（超出时从最远处丢弃，损失被雾掩盖）。
  final int maxFaces;

  /// 远处向天空雾色混合。
  final bool fogEnabled;

  /// 相邻遮挡剔除开关（调试用；关掉会让面数暴涨十倍）。
  final bool occlusionCull;

  /// 背面剔除开关。
  final bool backFaceCull;

  /// 视锥/方位剔除总开关（R26r：用户要求全部关闭以排查透视——关掉后
  /// 不剔除「完全在视角外」的区块、也不做逐面方位粗剔除）。
  final bool frustumCull;

  /// 水面波纹（只动水的顶面）。
  final bool waterAnimation;

  /// 天空竖直渐变（关闭时用纯地平线色）。
  final bool skyGradient;

  /// 视距（区块数，R23m：默认 4 = 64 格；设置里可调）。
  final int viewDistanceChunks;

  /// LOD 起始距离（区块数，R23m：默认 2 = 32 格外开始降精度）。
  final int lodStartChunks;

  /// 每 N 区块降一级精度（R23m：默认 1 = 每远一区块降一级）。
  final int lodStepChunks;

  /// 云层区块视距（R26p2：默认 3 = 48 格半径云场覆盖）。
  /// 渲染端云场以相机为中心重定心，覆盖半径 = 区块数 × 16 格。
  final int cloudViewDistanceChunks;

  /// 是否使用 16×16 纹理图集贴图（R24c）。关闭则回退纯色平铺。
  final bool textureEnabled;

  /// R26f：每帧最多构建的 chunk 数（分帧构建）。跑图/转身时新 chunk miss
  /// 全部在单帧建会卡；限制预算后，超出的 chunk 本帧跳过、下帧补建
  /// （缓存天然记录已建/未建，帧间只差 1 帧，雾遮挡下无感）。
  final int maxChunkBuildsPerFrame;

  /// R26i：按区块朝向减面（LOD 面数）。以区块为整体只算一次「视角→可见面」
  /// 规则（0~30° 1 面 / 30~60° 2 面 / 60~90° 1 面 / >90° 0 面），应用到本
  /// 区块全部侧面（忽略顶/底面，地面不消失）；距相机 < lodStart 的近区块不裁剪。
  /// 仅第一/三人称生效，俯瞰/2.5D 关闭（需全图）。
  final bool lodFaceCull;

  /// 区块级 LOD 采样降精度总开关（R26r：关闭 → 所有距离满采样，无 LOD 抽稀）。
  final bool lodEnabled;

  RenderConfig copyWith({
    double? renderDistance,
    int? maxFaces,
    bool? fogEnabled,
    bool? occlusionCull,
    bool? backFaceCull,
    bool? frustumCull,
    bool? waterAnimation,
    bool? skyGradient,
    int? viewDistanceChunks,
    int? lodStartChunks,
    int? lodStepChunks,
    int? cloudViewDistanceChunks,
    bool? textureEnabled,
    bool? lodFaceCull,
    bool? lodEnabled,
  }) {
    return RenderConfig(
      renderDistance: renderDistance ?? this.renderDistance,
      maxFaces: maxFaces ?? this.maxFaces,
      fogEnabled: fogEnabled ?? this.fogEnabled,
      occlusionCull: occlusionCull ?? this.occlusionCull,
      backFaceCull: backFaceCull ?? this.backFaceCull,
      frustumCull: frustumCull ?? this.frustumCull,
      waterAnimation: waterAnimation ?? this.waterAnimation,
      skyGradient: skyGradient ?? this.skyGradient,
      viewDistanceChunks: viewDistanceChunks ?? this.viewDistanceChunks,
      lodStartChunks: lodStartChunks ?? this.lodStartChunks,
      lodStepChunks: lodStepChunks ?? this.lodStepChunks,
      cloudViewDistanceChunks:
          cloudViewDistanceChunks ?? this.cloudViewDistanceChunks,
      textureEnabled: textureEnabled ?? this.textureEnabled,
      maxChunkBuildsPerFrame:
          maxChunkBuildsPerFrame ?? this.maxChunkBuildsPerFrame,
      lodFaceCull: lodFaceCull ?? this.lodFaceCull,
      lodEnabled: lodEnabled ?? this.lodEnabled,
    );
  }
}

/// 一帧渲染结果。
class VoxelFrame {
  const VoxelFrame({
    required this.sky,
    required this.opaque,
    required this.translucent,
    required this.columnsVisited,
    required this.facesCollected,
    this.chunkHits = 0,
    this.chunkMisses = 0,
    this.sunX = 0,
    this.sunY = 1,
    this.sunZ = 0,
    this.sunWeight = 0,
    this.sunSX = 0,
    this.sunSY = 0,
    this.sunVisible = false,
    this.moonSX = 0,
    this.moonSY = 0,
    this.moonVisible = false,
    this.opaquePlainBuckets = const <VoxelMeshBatch?>[],
    this.opaqueTexturedBuckets = const <VoxelMeshBatch?>[],
    this.waterBuckets = const <VoxelMeshBatch?>[],
    this.edgeBuckets = const <VoxelMeshBatch?>[],
  });

  final SkyPalette sky;

  /// 不透明面（Pass A），深度降序（远 → 近）。
  final List<RenderFace> opaque;

  /// 半透明面（Pass B：水 / 玻璃），深度降序。
  final List<RenderFace> translucent;

  /// 通过列级粗剔除的列数（性能诊断）。
  final int columnsVisited;

  /// 预算裁剪前收集到的面数（性能诊断）。
  final int facesCollected;

  /// 区块几何缓存命中 / 未命中数（R23s 性能诊断）。
  final int chunkHits;
  final int chunkMisses;

  /// 太阳方向（世界空间，已归一化）与方向光权重（0=夜，1=正午），供画家绘制太阳/天象。
  final double sunX;
  final double sunY;
  final double sunZ;
  final double sunWeight;

  /// R26i：太阳/月亮的屏幕坐标（像素，已由相机投影——转视角时天象随世界
  /// 真实移动，是「实体」而非屏幕固定）。不可见（落在相机后方/地平线下）时
  /// [sunVisible]/[moonVisible]=false，画家不绘制。
  final double sunSX;
  final double sunSY;
  final bool sunVisible;
  final double moonSX;
  final double moonSY;
  final bool moonVisible;

  /// 批量网格（R25 GPU 加速）：非贴图/贴图不透明面 / 水面 / 描边，各按相机深度
  /// 分 8 桶（远→近）。逐桶提交并与描边桶交错 → 画家算法正确，消除透视/穿墙。
  /// 桶为空 = null。空帧（[empty]）全部为空，画家回退逐面绘制。
  final List<VoxelMeshBatch?> opaquePlainBuckets;
  final List<VoxelMeshBatch?> opaqueTexturedBuckets;
  final List<VoxelMeshBatch?> waterBuckets;

  /// R26b 描边深度桶：按相机深度分 8 桶、远→近排列，绘制时与地形面桶交错
  /// 提交——前面面的描边正确盖住后面面的描边（修复「描边透视」）。
  final List<VoxelMeshBatch?> edgeBuckets;

  int get faceCount => opaque.length + translucent.length;

  static const VoxelFrame empty = VoxelFrame(
    sky: SkyPalette(
      zenith: Color(0xFF4A8FE0),
      horizon: Color(0xFFBFE0F5),
      fog: Color(0xFFC7DDEE),
      light: 1,
    ),
    opaque: <RenderFace>[],
    translucent: <RenderFace>[],
    opaquePlainBuckets: const <VoxelMeshBatch?>[],
    opaqueTexturedBuckets: const <VoxelMeshBatch?>[],
    waterBuckets: const <VoxelMeshBatch?>[],
    edgeBuckets: const <VoxelMeshBatch?>[],
    columnsVisited: 0,
    facesCollected: 0,
    sunSX: 0,
    sunSY: 0,
    sunVisible: false,
    moonSX: 0,
    moonSY: 0,
    moonVisible: false,
  );
}

/// 纯函数渲染器。
abstract final class VoxelRenderer {
  /// 构建一帧：世界 + 相机 + 视口 + 配置 → 有序面列表。
  ///
  /// [timePhase] 驱动天色 / 光照；[wavePhase] 驱动水面波纹（单位：循环数）。
  static VoxelFrame buildFrame({
    required VoxelWorld world,
    required VoxelCamera camera,
    required Size viewport,
    RenderConfig config = const RenderConfig(),
    double timePhase = 0.25,
    double wavePhase = 0,
    List<VoxelEntity> entities = const <VoxelEntity>[],
    VoxelChunkCache? cache,
    List<PointLight> lights = const <PointLight>[],
  }) {
    if (viewport.width <= 1 || viewport.height <= 1) return VoxelFrame.empty;

    final ViewBasis b = camera.basis;
    final ProjectionParams proj = camera.projectionFor(viewport);
    final SkyPalette sky = SkyPalette.at(timePhase);

    // R23v 昼夜：由时相推出太阳方向 + 方向光权重（夜里为 0，只剩环境光）。
    final DayNightCycle sun = DayNightCycle(phase: timePhase);
    final ({double x, double y, double z}) sd = sun.sunDir;
    final double sunWeight = sun.sunWeight;

    // R26i：把太阳/月亮投影到屏幕（真实 3D 天象——转视角时随世界移动，
    // 不是屏幕固定贴图）。白天画太阳（eye + sunDir·R），夜里画月亮
    // （eye - sunDir·R：此时 sunDir.y<0 → -sunDir 在头顶上方）。落在相机
    // 后方 / 地平线下 → projectWith 返回 null → 不可见。
    double sunSX = 0, sunSY = 0;
    bool sunVisible = false;
    double moonSX = 0, moonSY = 0;
    bool moonVisible = false;
    {
      final double R = camera.far * 0.9;
      final ScreenPoint? sp = VoxelCamera.projectWith(
        b.eyeX + sd.x * R,
        b.eyeY + sd.y * R,
        b.eyeZ + sd.z * R,
        b,
        proj,
      );
      if (sp != null) {
        sunSX = sp.x;
        sunSY = sp.y;
        sunVisible = true;
      }
      final ScreenPoint? mp = VoxelCamera.projectWith(
        b.eyeX - sd.x * R,
        b.eyeY - sd.y * R,
        b.eyeZ - sd.z * R,
        b,
        proj,
      );
      if (mp != null) {
        moonSX = mp.x;
        moonSY = mp.y;
        moonVisible = true;
      }
    }

    final List<RenderFace> allFaces = <RenderFace>[];

    // R25 批量缓冲：把每面顶点拼进「按相机深度分 8 桶」的列表，画家逐桶
    // 远→近提交并与描边桶交错（见 _drawBatched）——画家算法正确，消除
    // 「透视/穿墙」（原单批按区块网格顺序提交，远处块会盖住近处块）。
    // 每桶存按面顶点 + 颜色，保留逐角 AO。
    List<List<double>> newBuckets() =>
        List<List<double>>.generate(8, (_) => <double>[]);
    List<List<int>> newColBuckets() =>
        List<List<int>>.generate(8, (_) => <int>[]);
    final List<List<double>> plainPosB = newBuckets();
    final List<List<int>> plainColB = newColBuckets();
    final List<List<double>> texPosB = newBuckets();
    final List<List<double>> texUVB = newBuckets();
    final List<List<int>> texColB = newColBuckets();
    final List<List<double>> waterPosB = newBuckets();
    final List<List<double>> waterUVB = newBuckets();
    final List<List<int>> waterColB = newColBuckets();
    // R26b：描边深度桶（远→近 8 桶）——修复「描边透视」。
    final List<List<double>> edgePosB = newBuckets();
    final List<List<int>> edgeColB = newColBuckets();
    // R26q：每桶逐面深度（1 个 double/面），固化前在桶内做远→近排序，
    // 消除「单桶内 chunk 迭代顺序错序」导致的滑窗内透视（8 桶只切深度段，
    // 段内仍须排序才正确）。
    final List<List<double>> plainDepthB = newBuckets();
    final List<List<double>> texDepthB = newBuckets();
    final List<List<double>> waterDepthB = newBuckets();
    final List<List<double>> edgeDepthB = newBuckets();
    const int kOutline = 0x4D000000; // 描边色：~30% 黑，ARGB
    // R26f：描边最大深度（世界格）。超过则不生成描边（远处不可见 + 省面数）。
    const double kEdgeMaxDepth = 15.0;

    // 把一面拼进对应批次（贴图 / 纯色 / 水 / 描边）。
    // [depth]：面中心相机深度（0~far），描边按其落入深度桶，绘制时远→近，
    // 使前面面的描边正确盖住后面面的描边（消除透视）。
    void pushFace(Float32List xy, Float32List? uv, int argb, int tint,
        bool translucentFace,
        [double depth = 0,
        List<double>? ao,
        double aoScale = 1.0,
        List<bool>? edgeMask]) {
      final double x0 = xy[0], y0 = xy[1];
      final double x1 = xy[2], y1 = xy[3];
      final double x2 = xy[4], y2 = xy[5];
      final double x3 = xy[6], y3 = xy[7];
      final int c = uv != null
          ? (translucentFace
              ? (tint & 0x00FFFFFF) |
                  ((kWaterAlpha * 255).round().clamp(0, 255) << 24)
              : tint)
          : argb;
      // R26j：顶点烘焙 AO + 斜度着色。6 顶点（2 三角形）逐角颜色 = 基色 ×
      // 角落 AO × 斜度；未传 ao（云 / 实体等路径）保持整面同色。
      final List<int> cols = ao == null
          ? <int>[c, c, c, c, c, c]
          : <int>[
              _modulate(c, ao[0] * aoScale),
              _modulate(c, ao[1] * aoScale),
              _modulate(c, ao[2] * aoScale),
              _modulate(c, ao[0] * aoScale),
              _modulate(c, ao[2] * aoScale),
              _modulate(c, ao[3] * aoScale),
            ];
      final int bkt = (depth / camera.far * 8).floor().clamp(0, 7);
      if (uv != null) {
        final double u0 = uv[0], v0 = uv[1];
        final double u1 = uv[2], v1 = uv[3];
        final double u2 = uv[4], v2 = uv[5];
        final double u3 = uv[6], v3 = uv[7];
        if (translucentFace) {
          waterPosB[bkt]
            ..add(x0)..add(y0)..add(x1)..add(y1)..add(x2)..add(y2)
            ..add(x0)..add(y0)..add(x2)..add(y2)..add(x3)..add(y3);
          waterUVB[bkt]
            ..add(u0)..add(v0)..add(u1)..add(v1)..add(u2)..add(v2)
            ..add(u0)..add(v0)..add(u2)..add(v2)..add(u3)..add(v3);
          waterColB[bkt]..addAll(cols);
          waterDepthB[bkt].add(depth);
        } else {
          texPosB[bkt]
            ..add(x0)..add(y0)..add(x1)..add(y1)..add(x2)..add(y2)
            ..add(x0)..add(y0)..add(x2)..add(y2)..add(x3)..add(y3);
          texUVB[bkt]
            ..add(u0)..add(v0)..add(u1)..add(v1)..add(u2)..add(v2)
            ..add(u0)..add(v0)..add(u2)..add(v2)..add(u3)..add(v3);
          texColB[bkt]..addAll(cols);
          texDepthB[bkt].add(depth);
        }
      } else {
        plainPosB[bkt]
          ..add(x0)..add(y0)..add(x1)..add(y1)..add(x2)..add(y2)
          ..add(x0)..add(y0)..add(x2)..add(y2)..add(x3)..add(y3);
        plainColB[bkt]..addAll(cols);
        plainDepthB[bkt].add(depth);
      }
      // 描边：仅不透明面。每条边画成一条细长方块（2 三角形），
      // drawVertices 无 line 模式，故用细长方块近似（R25 描边诉求）。
      // R26b：按 depth 落桶，绘制时远→近，前面面的描边盖住后面面的描边。
      // R26f：距离衰减——深度 > 15 格不画描边（1.1px 细线远处不可见，
      // 但每面要生成 8 个三角形，是面数黑洞，近距画、远距省）。
      if (!translucentFace && depth < kEdgeMaxDepth) {
        const double hw = 1.1; // 描边半宽（px）
        final List<(double, double)> ec = <(double, double)>[
          (x0, y0),
          (x1, y1),
          (x2, y2),
          (x3, y3),
        ];
        final List<double> ebp = edgePosB[bkt];
        final List<int> ebc = edgeColB[bkt];
        final List<double> ebd = edgeDepthB[bkt];
        for (int e = 0; e < 4; e++) {
          // R26l：只描「我能看见的轮廓边」——内部边（两侧面都朝相机）跳过。
          if (edgeMask != null && !edgeMask[e]) continue;
          final (double ax, double ay) = ec[e];
          final (double bx, double by) = ec[(e + 1) % 4];
          final double dx = bx - ax;
          final double dy = by - ay;
          final double len = math.sqrt(dx * dx + dy * dy);
          if (len < 0.5) continue;
          final double nx = -dy / len * hw;
          final double ny = dx / len * hw;
          ebp
            ..add(ax + nx)..add(ay + ny)
            ..add(bx + nx)..add(by + ny)
            ..add(bx - nx)..add(by - ny)
            ..add(ax + nx)..add(ay + ny)
            ..add(bx - nx)..add(by - ny)
            ..add(ax - nx)..add(ay - ny);
          ebc
            ..add(kOutline)..add(kOutline)..add(kOutline)
            ..add(kOutline)..add(kOutline)..add(kOutline);
          ebd.add(depth);
        }
      }
    }

    // 列级粗剔除参数：距离 + 水平方位角（留 0.35rad 余量）。
    // R23m：距离上限 = max(区块视距, renderDistance)，区块视距为主。
    // R26：渲染距离随 FOV 联动——拉远（fov→120°）时系数≈1 全距离开（不再
    // 「剔除太狠」）；放大（fov 缩小）时系数下降，远处不渲染（省性能）。
    final double maxDist = math.max(
      config.renderDistance,
      config.viewDistanceChunks * RenderConfig.chunkSize.toDouble(),
    ) * (camera.fov / VoxelCamera.maxFov).clamp(0.3, 1.0);

    // 列级（按面中心）方位粗剔除参数：水平前向 + 半锥角。R23s 改为**每帧**
    // 作用在缓存面上（相机相关），不再进入相机无关的 chunk 几何缓存——
    // 既保留"跳过相机侧后方 / 边缘面"的投影开销节省，又不污染缓存。
    final double hFwdX = math.sin(camera.yaw);
    final double hFwdZ = math.cos(camera.yaw);
    final double aspect = viewport.width / viewport.height;
    final double halfFovX = camera.fullWidth
        ? camera.fov / 2
        : math.atan(math.tan(camera.fov / 2) * aspect);
    // R26n：面级粗剔除阈值放宽——只剔「明显在身后」（cos < -0.5 ≈ 视角外 120°），
    // 朝下/朝上俯视时侧面的面不再被误剔（用户「lz<0.1 太保守」反馈）。
    final double cosLimit = math.cos(math.min(math.pi, halfFovX + 1.2));
    // 视线水平分量长度（恒为 1，保留原判定以防未来改用含俯仰的前向）。
    final double horizLen = math.sqrt(hFwdX * hFwdX + hFwdZ * hFwdZ);
    final bool cullAzimuth = horizLen >= 0.3;

    // 雾距：R26i 起雾点 = LOD 起始距离（lodStart），向外浓度递增（smoothstep）
    // 融入天空雾色，把 LOD 接缝"化"进地平线雾里，消除硬切 popping。
    // lodStart 在下方区块循环前才算出，故实际赋值见其下方。
    late final double fogStart;
    late final double fogSpan;

    // 复用缓冲：4 顶点 × (x, y, z)（投影时临时写入）。
    final Float64List corners = Float64List(12);

    int columns = 0;
    int chunkHits = 0;
    int chunkMisses = 0;
    int buildsThisFrame = 0; // R26f：分帧构建预算计数

    // R23m 区块机制：16×16 一区块，按「相机周围 viewDistanceChunks 区块」
    // 组织遍历；距相机 lodStartChunks 区块外开始 LOD 降精度——
    // 每远 lodStepChunks 区块，列采样步长 ×2（1,2,4,8…）。远处面数指数下降，
    // 性能与距离成正比，无限世界可跑。
    const int cs = RenderConfig.chunkSize;
    final int vd = config.viewDistanceChunks;
    final double lodStart = config.lodStartChunks * cs.toDouble();
    final double lodStep = math.max(1, config.lodStepChunks) * cs.toDouble();
    final int camChunkX = (b.eyeX / cs).floor();
    final int camChunkZ = (b.eyeZ / cs).floor();
    final double chunkVd = vd * cs.toDouble();

    // R26i/R26r：起雾点。原取 LOD 起始距离；LOD 关闭后改为视距的 80%，
    // 使雾与渲染距离挂钩、不再依赖 LOD 设置。
    fogStart = math.max(1.0, chunkVd * 0.8);
    fogSpan = math.max(1.0, maxDist - fogStart);

    // R23s 区块几何缓存：每个 (cx,cz,lod) 的"occlusion 可见面"集合是相机无关的，
    // 只与地形有关 → 缓存后跨帧 / 相机平移复用，每帧省掉百万级 world.get +
    // isFaceHidden（邻居查询嵌套）。每帧仅对缓存面做 backFaceCull（用缓存法线）
    // + 投影 + 着色；方位 / 距离剔除改由 project 返回 null（相机后方）自然处理，
    // 比列级方位剔除更正确（并修复 R23k "只渲染一角" 隐患）。
    for (int cz = camChunkZ - vd; cz <= camChunkZ + vd; cz++) {
      for (int cx = camChunkX - vd; cx <= camChunkX + vd; cx++) {
        final int cx0 = cx * cs;
        final int cz0 = cz * cs;
        final double ccx = cx0 + cs * 0.5 - b.eyeX;
        final double ccz = cz0 + cs * 0.5 - b.eyeZ;
        final double cdist = math.sqrt(ccx * ccx + ccz * ccz);
        if (cdist > chunkVd + cs * 0.75) continue;

        // R26n：视锥剔除——只剔除「完全在视角外」的区块（AABB 8 角视锥测试，
        // 任一角落在视锥内即保留，含俯仰；比逐面/中心点判断更精确、不会漏掉
        // 脚下与视角边缘的方块）。玩家所在区块永不剔除。俯瞰/2.5D 保持水平剔除。
        // R26r：frustumCull 关闭时整段跳过（用户要求排查透视时全保留）。
        if (cullAzimuth && config.frustumCull) {
          if (camera.fullWidth) {
            final double dot = (ccx * hFwdX + ccz * hFwdZ) / cdist;
            final double chunkAng =
                math.atan(cs * 0.75 / math.max(1.0, cdist));
            if (dot < math.cos(halfFovX + chunkAng)) continue;
          } else {
            final bool camInChunk = b.eyeX >= cx0 &&
                b.eyeX < cx0 + cs &&
                b.eyeZ >= cz0 &&
                b.eyeZ < cz0 + cs;
            // R26p：相机紧邻 3×3 区块（含侧墙/顶棚/地板）永不视锥剔除——
            // 狭小空间里贴脸的相邻区块 8 角常以极陡角度落于视锥外，原逻辑会整块
            // 剔掉导致「剔穿墙」。半径 1 仅多保 8 个区块，开销可忽略。
            final bool nearCam =
                (cx - camChunkX).abs() <= 1 && (cz - camChunkZ).abs() <= 1;
            if (!camInChunk &&
                !nearCam &&
                !_chunkInFrustum(b, proj, cx0, cz0, cs, world.maxY)) {
              continue;
            }
          }
        }

        // R26i：按区块朝向减面（LOD 面数）。整个区块只算一次「视角→可见面」
        // 规则，应用到本区块全部侧面（忽略顶/底面，地面不消失）；距相机 <
        // lodStart 的近区块不裁剪（保留全部侧面，避免近处建筑"穿帮"）；俯瞰
        // /2.5D 关闭（需全图）。bit: 0:+X 1:-X 2:+Z 3:-Z。
        int allowMask = 0xF;
        if (config.lodFaceCull && !camera.fullWidth && cdist > lodStart) {
          // 视角前向水平分量 (hFwdX,hFwdZ) 与「指向区块中心」水平方向的点积
          // = cos(夹角)：正对=1，正侧=0，身后<0。
          final double dot = (ccx * hFwdX + ccz * hFwdZ) / cdist;
          if (dot <= 0) {
            allowMask = 0; // >90° 身后：0 个侧面（顶/底面仍保留）
          } else {
            // 主朝向面 = 指向玩家的水平面（=-dirToChunk 的主导轴）。
            final double ux = ccx / cdist, uz = ccz / cdist;
            final int mainAxis = ux.abs() >= uz.abs()
                ? (ux >= 0 ? 1 : 0) // 区块在 +X → 我们看见 -X 面(bit1)
                : (uz >= 0 ? 3 : 2); // 区块在 +Z → 看见 -Z 面(bit3)
            // 侧边面 = 垂直于主面、且与视角偏转同向的那一侧。
            final int sideAxis = ux.abs() >= uz.abs()
                ? (hFwdZ >= 0 ? 2 : 3) // 主沿 X → 侧沿 Z，取视角偏 Z 向
                : (hFwdX >= 0 ? 0 : 1); // 主沿 Z → 侧沿 X，取视角偏 X 向
            if (dot < 0.5) {
              allowMask = 1 << sideAxis; // 60~90°：只画侧边面
            } else if (dot < 0.866) {
              allowMask = (1 << mainAxis) | (1 << sideAxis); // 30~60°：主+侧
            } else {
              allowMask = 1 << mainAxis; // 0~30°：只画主面
            }
          }
        }

        // LOD 级别（相机相关：决定采样步长，故计入缓存 key）。
        // R26r：lodEnabled 关闭 → 永远 0（满精度），不再随距离抽稀。
        int lod = 0;
        if (config.lodEnabled && cdist > lodStart) {
          lod = ((cdist - lodStart) / lodStep).floor().clamp(0, 3);
        }
        final int step = 1 << lod; // 1,2,4,8
        // 交错偏移：奇数 LOD 区块半格错位，减弱远处"网格感"。
        final int off = lod.isEven ? 0 : step ~/ 2;

        // 取 / 建本 chunk 的相机无关几何（occlusion 剔除后的可见外壳面）。
        // R26f：分帧构建——每帧最多建 maxChunkBuildsPerFrame 个，超预算的
        // miss 本帧跳过（不渲染该 chunk），下帧补建；缓存记录已建/未建。
        ChunkMesh? mesh;
        if (cache != null) {
          mesh = cache.get(cx, cz, lod);
          if (mesh != null) {
            chunkHits++;
          } else {
            if (buildsThisFrame >= config.maxChunkBuildsPerFrame) continue;
            buildsThisFrame++;
            chunkMisses++;
            mesh = _buildChunkMesh(world, cx0, cz0, step, off, config);
            cache.put(cx, cz, lod, mesh);
          }
        } else {
          mesh = _buildChunkMesh(world, cx0, cz0, step, off, config);
        }
        columns += mesh.columns;

        // 统一投影：backFaceCull（相机相关）+ 水波 + 透视 + 着色。
        for (final CachedFace cf in mesh.faces) {
          // 背面剔除：法线与"眼→面中心"同向即背面（用缓存法线，省重算）。
          if (config.backFaceCull) {
            final double ccx2 = cf.bx + cf.nx * 0.5 - b.eyeX;
            final double ccy2 = cf.by + cf.ny * 0.5 - b.eyeY;
            final double ccz2 = cf.bz + cf.nz * 0.5 - b.eyeZ;
            if (ccx2 * cf.nx + ccy2 * cf.ny + ccz2 * cf.nz >= 0) continue;
          }

          // 方位粗剔除（每帧，相机相关）：只保留相机朝向半锥内的面，
          // 跳过侧后方 / 边缘面——否则这类面深度趋近近平面，投影坐标爆表
          // （数万）且永不入屏，纯属浪费。cf.bx/bz 即列中心，等价原列级剔除。
          // R26r：frustumCull 关闭时跳过（全保留）。
          if (cullAzimuth && config.frustumCull) {
            final double colX = cf.bx - b.eyeX;
            final double colZ = cf.bz - b.eyeZ;
            if (camera.fullWidth) {
              final double d2 = colX * colX + colZ * colZ;
              if (d2 > 4) {
                final double d = math.sqrt(d2);
                if ((colX * hFwdX + colZ * hFwdZ) / d < cosLimit) continue;
              }
            } else {
              // 3D 视锥：用含俯仰的视线前向，避免看脚下时误剔近处下方块。
              final double colY = cf.by - b.eyeY;
              final double d2 = colX * colX + colY * colY + colZ * colZ;
              if (d2 > 4) {
                final double d = math.sqrt(d2);
                final double dot3 =
                    (colX * b.fwdX + colY * b.fwdY + colZ * b.fwdZ) / d;
                if (dot3 < cosLimit) continue;
              }
            }
          }

          // R26i：区块级 LOD 减面（allowMask 已按本区块算好，应用到各侧面）。
          // 顶/底面（ny≠0）不在侧面规则内 → 永远保留；只按 nx/nz 判定 4 个
          // 水平侧面的取舍。
          if (allowMask != 0xF) {
            int bit = -1;
            if (cf.nx > 0.5) {
              bit = 0;
            } else if (cf.nx < -0.5) {
              bit = 1;
            } else if (cf.nz > 0.5) {
              bit = 2;
            } else if (cf.nz < -0.5) {
              bit = 3;
            }
            if (bit >= 0 && (allowMask & (1 << bit)) == 0) continue;
          }

          corners.setRange(0, 12, cf.corners);
          // 水面波纹：只动水顶面 y（数量少，不破坏剔除前提）。
          if (cf.voxel == Voxel.water && cf.face == BlockFace.top) {
            for (int i = 0; i < 4; i++) {
              final double vx = corners[i * 3];
              final double vz = corners[i * 3 + 2];
              double h = 0.9;
              if (config.waterAnimation) {
                h += 0.06 *
                    math.sin(
                      2 * math.pi * wavePhase * 1.5 + 0.7 * vx + 0.5 * vz,
                    );
              }
              corners[i * 3 + 1] = cf.by + (h - 0.5);
            }
          }

          // 透视投影（任一顶点在近平面之后 / 相机后方 → 整面丢弃）。
          final Float32List xy = Float32List(8);
          double depthSum = 0;
          bool clipped = false;
          for (int i = 0; i < 4; i++) {
            final ScreenPoint? sp = VoxelCamera.projectWith(
              corners[i * 3],
              corners[i * 3 + 1],
              corners[i * 3 + 2],
              b,
              proj,
            );
            if (sp == null) {
              clipped = true;
              break;
            }
            xy[i * 2] = sp.x;
            xy[i * 2 + 1] = sp.y;
            depthSum += sp.depth;
          }
          if (clipped) continue;

          final double depth = depthSum / 4;
          if (depth > camera.far) continue;

          final (int argb, int tint) = _colorOf(
            voxel: cf.voxel,
            face: cf.face,
            depth: depth,
            sky: sky,
            config: config,
            fogStart: fogStart,
            fogSpan: fogSpan,
            lights: lights,
            sunWeight: sunWeight,
            sunX: sd.x,
            sunY: sd.y,
            sunZ: sd.z,
            fx: cf.bx + cf.nx * 0.5,
            fy: cf.by + cf.ny * 0.5,
            fz: cf.bz + cf.nz * 0.5,
          );
          final Float32List? uv =
              config.textureEnabled ? VoxelTextureAtlas.tileUV(cf.voxel.index) : null;
          final RenderFace rf = RenderFace(
            xy: xy,
            argb: argb,
            depth: depth,
            voxel: cf.voxel,
            face: cf.face,
            uv: uv,
            tint: tint,
          );
          // R24c：单桶深度排序（opaque + translucent 合并），保证水被前方
          // 不透明地形正确遮挡（画家算法下透明面必须参与全局远→近排序）。
          allFaces.add(rf);
          // R25：同时拼入批量缓冲（画家一次性提交，GPU 加速）。
          // R26j：逐顶点 AO × 斜度烘焙进颜色。
          // R26l：不透明面按轮廓边掩码描边（内部边不描）。
          final List<bool>? edgeMask =
              (cf.voxel.isTransparent || depth >= kEdgeMaxDepth)
                  ? null
                  : _faceEdgeMask(world, cf, b);
          pushFace(xy, uv, argb, tint, cf.voxel.isTransparent, depth,
              cf.ao, cf.tilt, edgeMask);
        }
      }
    }

    // 实体（如 AI 陪伴小人）：当作额外方块盒，与地形一起参与深度排序 / 预算裁剪。
    // R24c：实体面也并入同一全局桶（不再分 opaque/translucent 两 Pass），
    // 画家算法下所有面统一远→近排序，水/玻璃才能被正确遮挡。
    for (final VoxelEntity en in entities) {
      // R26g：生物视锥剔除——第一/三人称下不在视角内的生物整只跳过
      //（只不渲染、不删）；俯瞰模式全渲染。与地形共用 cosLimit 半锥。
      if (!camera.fullWidth) {
        final double ex = en.position.x - b.eyeX;
        final double ey = (en.position.y + 1.0) - b.eyeY;
        final double ez = en.position.z - b.eyeZ;
        final double ed = math.sqrt(ex * ex + ey * ey + ez * ez);
        if (ed > 1e-3) {
          final double edot = (ex * b.fwdX + ey * b.fwdY + ez * b.fwdZ) / ed;
          if (edot < cosLimit) continue;
        }
      }
      _emitEntity(
        allFaces,
        allFaces,
        en,
        b,
        proj,
        sky,
        config,
        fogStart,
        fogSpan,
        camera.far,
        pushFace,
      );
    }

    // R26b：世界空间方块云（不透明、自北向南漂移）——进统一投影/深度排序。
    _emitClouds(
      allFaces,
      world,
      b,
      proj,
      camera.far,
      timePhase,
      config.cloudViewDistanceChunks,
      pushFace,
    );

    final int collected = allFaces.length;

    // 画家算法：远 → 近（单桶，水/地形/实体统一）。
    // R23q：128 桶桶排序替代全量 sort——按相机深度分桶（桶内保序），O(n)。
    _bucketSortByDepth(allFaces, camera.far);

    // 面数预算：超限时丢最远的（视觉损失被雾掩盖）。
    // R23o：预算随视距放大——固定上限在视距大时会把近处面也裁掉，
    // 按区块数线性扩容。
    final int faceBudget = config.maxFaces *
        math.max(1, (config.viewDistanceChunks + 2) ~/ 3);
    _trimFarthest(allFaces, faceBudget);

    // R25：把累积的批量缓冲固化为类型化数组（空则 null，画家回退逐面绘制）。
    // R26p-camera：地形面按深度 8 桶固化（远→近），与描边桶交错绘制。
    // R26q：固化前先在桶内按深度远→近排序（见 `_sortFacesByDepth`），消除
    // 「单桶内 chunk 迭代顺序错序」导致的滑窗内透视——画家算法正确性的关键。
    // R26r2：固化前做地形面数预算——超预算从最远桶往前裁掉最远的面（这些面
    // 全在雾区：雾起点=视距 80%，视觉不可见），近处永远满精度、无露洞，性能有上界。
    List<VoxelMeshBatch?> buildBuckets(
      List<List<double>> posB,
      List<List<int>> colB, {
      List<List<double>>? uvB,
      required List<List<double>> depthB,
      required int budget,
    }) {
      // Pass 1：每桶先做远→近排序。
      for (int i = 0; i < 8; i++) {
        if (posB[i].isEmpty) continue;
        _sortFacesByDepth(
          pos: posB[i],
          col: colB[i],
          uv: uvB != null ? uvB[i] : null,
          depth: depthB[i],
        );
      }
      // Pass 2：面数预算（排序后桶内 index 0 = 最远，从最远桶往前裁）。
      int total = 0;
      for (int i = 0; i < 8; i++) {
        total += posB[i].length ~/ 12;
      }
      if (total > budget) {
        for (int i = 7; i >= 0 && total > budget; i--) {
          final int n = posB[i].length ~/ 12;
          if (n == 0) continue;
          final int drop = math.min(n, total - budget);
          final int start = drop * 12;
          posB[i].removeRange(0, start);
          colB[i].removeRange(0, drop * 6);
          if (uvB != null) uvB[i].removeRange(0, start);
          total -= drop;
        }
      }
      // Pass 3：固化。
      final List<VoxelMeshBatch?> out = <VoxelMeshBatch?>[];
      for (int i = 0; i < 8; i++) {
        if (posB[i].isEmpty) continue;
        out.add(VoxelMeshBatch(
          positions: Float32List.fromList(posB[i]),
          colors: Int32List.fromList(colB[i]),
          uv: uvB != null && uvB[i].isNotEmpty
              ? Float32List.fromList(uvB[i])
              : null,
        ));
      }
      return out;
    }
    final List<VoxelMeshBatch?> opaquePlainBuckets = buildBuckets(plainPosB,
        plainColB,
        depthB: plainDepthB, budget: faceBudget);
    final List<VoxelMeshBatch?> opaqueTexturedBuckets = buildBuckets(texPosB,
        texColB,
        uvB: texUVB, depthB: texDepthB, budget: faceBudget);
    final List<VoxelMeshBatch?> waterBuckets = buildBuckets(waterPosB,
        waterColB,
        uvB: waterUVB, depthB: waterDepthB, budget: faceBudget);
    // R26b：描边深度桶（远→近，绘制时正确遮挡，修「描边透视」）。
    final List<VoxelMeshBatch?> edgeBuckets = buildBuckets(edgePosB, edgeColB,
        depthB: edgeDepthB, budget: faceBudget);

    return VoxelFrame(
      sky: sky,
      opaque: allFaces,
      translucent: const <RenderFace>[],
      opaquePlainBuckets: opaquePlainBuckets,
      opaqueTexturedBuckets: opaqueTexturedBuckets,
      waterBuckets: waterBuckets,
      edgeBuckets: edgeBuckets,
      sunX: sd.x,
      sunY: sd.y,
      sunZ: sd.z,
      sunWeight: sunWeight,
      sunSX: sunSX,
      sunSY: sunSY,
      sunVisible: sunVisible,
      moonSX: moonSX,
      moonSY: moonSY,
      moonVisible: moonVisible,
      columnsVisited: columns,
      facesCollected: collected,
      chunkHits: chunkHits,
      chunkMisses: chunkMisses,
    );
  }

  /// 面是否被相邻方块遮挡（§2.3 规则表）。
  ///
  /// | 当前块 | 邻块 | 绘制 |
  /// |---|---|---|
/// | 任意 | 不透明实心 | 否 |
/// | 水 | 水 | 否（水体只留外壳） |
/// | 叶 | 叶 | 否（fast 树叶：不透明实心，内部面剔除，只留外壳） |
/// | 任意 | 空气 | 是 |
  static bool isFaceHidden(
    VoxelWorld w,
    int x,
    int y,
    int z,
    BlockFace f, [
    Voxel? selfHint, // R23q：调用方已取过 self，避免重复 get
  ]) {
    final Voxel self = selfHint ?? w.get(x, y, z);
    if (self.isEmpty) return true;
    final Voxel nb = w.get(
      x + _normalX(f).toInt(),
      y + _normalY(f).toInt(),
      z + _normalZ(f).toInt(),
    );
    if (nb.isEmpty) return false;
    if (nb.occludes) return true;
    // 邻块半透明：水的同型内部面剔除，叶保留。
    if (self == Voxel.water && nb == Voxel.water) return true;
    return false;
  }

  // ── 内部工具 ─────────────────────────────────────────────

  static void _trimFarthest(List<RenderFace> faces, int budget) {
    if (faces.length > budget) faces.removeRange(0, faces.length - budget);
  }

  /// 128 桶桶排序（R23q）：按相机深度从远到近分桶，桶内保序。
  ///
  /// 面少（<64）直接 sort；面多时分桶 O(n)，同桶深度近似、绘制顺序
  /// 不影响画家算法结果（技术文档 §排序优化，省 ~60% 排序开销）。
  static void _bucketSortByDepth(List<RenderFace> faces, double far) {
    final int n = faces.length;
    if (n < 64) {
      faces.sort((RenderFace a, RenderFace b) => b.depth.compareTo(a.depth));
      return;
    }
    const int buckets = 128;
    final List<List<RenderFace>> bs =
        List<List<RenderFace>>.generate(
            buckets, (_) => <RenderFace>[]);
    final double span = math.max(1e-6, far / buckets);
    for (final RenderFace f in faces) {
      int bi = (f.depth / span).floor();
      if (bi < 0) {
        bi = 0;
      } else if (bi >= buckets) {
        bi = buckets - 1;
      }
      bs[buckets - 1 - bi].add(f); // 远桶在前
    }
    faces.clear();
    for (final List<RenderFace> b in bs) {
      if (b.isNotEmpty) faces.addAll(b);
    }
  }

  /// 单桶内逐面深度排序（R26q）：把同一深度桶里的面按相机深度从远到近排序，
  /// 消除「桶内 chunk 迭代顺序错序」导致的滑窗内透视。画家算法下，桶已按
  /// 远→近顺序绘制（见 `_drawBatched`），桶内再保证远面先画、近面后画即正确。
  ///
  /// [pos] 每面 12 个 double（6 顶点）；[col] 每面 6 个 int（与 pos 等顶点数）；
  /// [uv] 每面 12 个 double（贴图批次，可空）；[depth] 每面 1 个 double。
  /// 就地重排 [pos]/[col]/[uv]，不新建列表交给调用方。
  static void _sortFacesByDepth({
    required List<double> pos,
    required List<int> col,
    List<double>? uv,
    required List<double> depth,
  }) {
    final int n = depth.length; // 面数
    if (n < 2) return;
    final List<int> order = List<int>.generate(n, (int i) => i);
    // 远（depth 大）在前 → 先画；近（depth 小）在后 → 后画覆盖。
    order.sort((int a, int b) => depth[b].compareTo(depth[a]));
    final Float32List np = Float32List(pos.length);
    final Int32List nc = Int32List(col.length);
    final Float32List? nu = uv == null ? null : Float32List(uv.length);
    for (int k = 0; k < n; k++) {
      final int s = order[k];
      np.setRange(k * 12, k * 12 + 12, pos, s * 12);
      nc.setRange(k * 6, k * 6 + 6, col, s * 6);
      if (nu != null) nu.setRange(k * 12, k * 12 + 12, uv!, s * 12);
    }
    pos
      ..clear()
      ..addAll(np);
    col
      ..clear()
      ..addAll(nc);
    if (nu != null) {
      uv!
        ..clear()
        ..addAll(nu);
    }
  }

  /// 面法线（单位向量，供方向光点乘）。
  static (double, double, double) normalOf(BlockFace f) => switch (f) {
        BlockFace.top => (0.0, 1.0, 0.0),
        BlockFace.bottom => (0.0, -1.0, 0.0),
        BlockFace.north => (0.0, 0.0, -1.0),
        BlockFace.south => (0.0, 0.0, 1.0),
        BlockFace.west => (-1.0, 0.0, 0.0),
        BlockFace.east => (1.0, 0.0, 0.0),
      };

  /// R26j：把颜色 RGB 乘系数 [k]（保留 alpha）。用于顶点烘焙 AO（角落 ×0.33）
  /// 与斜度着色（陡坡 ×0.8 / 平地 ×1.1，允许 >1 提亮）。
  static int _modulate(int argb, double k) {
    final double f = k.clamp(0.0, 1.25);
    final int a = (argb >> 24) & 0xFF;
    final int r = ((((argb >> 16) & 0xFF) * f).round()).clamp(0, 255);
    final int g = ((((argb >> 8) & 0xFF) * f).round()).clamp(0, 255);
    final int b = (((argb & 0xFF) * f).round()).clamp(0, 255);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  /// R23v 光照合成：天光分面亮度 × 方向光 + 自发光 + 方块点光。
  ///
  /// 返回 (亮度系数, 暖光色, 染色权重)。方块光在夜里权重更高（白天被天光
  /// 淹没），这样火把只在该发光的时候发光，白天不会糊成一团橙。
  static (double, int, double) _lighting({
    required Voxel voxel,
    required BlockFace face,
    required SkyPalette sky,
    required List<PointLight> lights,
    required double sunWeight,
    required double sunX,
    required double sunY,
    required double sunZ,
    required double fx,
    required double fy,
    required double fz,
  }) {
    double lm = kFaceBrightness[face]! * sky.light;

    // 方向光：朝太阳的面更亮，背阴面更暗（权重随太阳高度衰减，夜里为 0）。
    if (sunWeight > 0) {
      final (double nx, double ny, double nz) = normalOf(face);
      final double d = nx * sunX + ny * sunY + nz * sunZ;
      lm *= 1 + sunWeight * 0.20 * d;
    }

    // 自发光：火把 / 篝火 / 熔炉画自己时不受夜色压暗。
    final double self = selfEmissionOf(voxel);
    if (self > lm) lm = self;

    // 方块点光。
    int tint = 0;
    double tintAmt = 0;
    if (lights.isNotEmpty) {
      double add = 0;
      double tr = 0, tg = 0, tb = 0;
      for (final PointLight l in lights) {
        final double i = l.intensityAt(fx, fy, fz);
        if (i <= 0) continue;
        add += i;
        tr += ((l.tint >> 16) & 0xFF) * i;
        tg += ((l.tint >> 8) & 0xFF) * i;
        tb += (l.tint & 0xFF) * i;
      }
      if (add > 0) {
        // 夜里天光弱 → 方块光突出；正午天光满 → 几乎看不出来。
        final double nightBoost = (1.3 - sky.light).clamp(0.12, 1.0);
        final double eff = (add * nightBoost).clamp(0.0, 0.9);
        lm += eff;
        tintAmt = (eff * 0.55).clamp(0.0, 0.45);
        tint = 0xFF000000 |
            ((tr / add).round().clamp(0, 255) << 16) |
            ((tg / add).round().clamp(0, 255) << 8) |
            (tb / add).round().clamp(0, 255);
      }
    }
    return (lm.clamp(0.0, 1.7), tint, tintAmt);
  }

  static (int argb, int tint) _colorOf({
    required Voxel voxel,
    required BlockFace face,
    required double depth,
    required SkyPalette sky,
    required RenderConfig config,
    required double fogStart,
    required double fogSpan,
    List<PointLight> lights = const <PointLight>[],
    double sunWeight = 0,
    double sunX = 0,
    double sunY = 1,
    double sunZ = 0,
    double fx = 0,
    double fy = 0,
    double fz = 0,
  }) {
    final VoxelSpec spec = voxel.spec;
    final Color base =
        (face == BlockFace.top && spec.top != null) ? spec.top! : spec.base;
    final double alpha = switch (voxel) {
      Voxel.water => kWaterAlpha,
      _ => 1.0,
    };
    final (double lm, int tint, double tintAmt) = _lighting(
      voxel: voxel,
      face: face,
      sky: sky,
      lights: lights,
      sunWeight: sunWeight,
      sunX: sunX,
      sunY: sunY,
      sunZ: sunZ,
      fx: fx,
      fy: fy,
      fz: fz,
    );
    Color c = shade(base, lm, alpha: alpha);
    if (tintAmt > 0) {
      c = Color.lerp(c, Color(tint), tintAmt)!.withValues(alpha: alpha);
    }
    // 雾距（smoothstep）：近处无雾，远处融入天空雾色。
    double fogT = 0;
    if (config.fogEnabled) {
      final double raw = ((depth - fogStart) / fogSpan).clamp(0.0, 1.0);
      fogT = raw * raw * (3 - 2 * raw);
      c = Color.lerp(c, sky.fog, fogT)!.withValues(alpha: alpha);
    }
    final int argb = c.toARGB32();
    // 贴图调制色：白色基 × 亮度 ×（远→雾色）。近=原色，远=雾色（乘到纹理）。
    final double l = lm.clamp(0.0, 1.0);
    final int fr = ((1 - fogT) * 255 + fogT * sky.fog.r * 255).round();
    final int fg = ((1 - fogT) * 255 + fogT * sky.fog.g * 255).round();
    final int fb = ((1 - fogT) * 255 + fogT * sky.fog.b * 255).round();
    final int tintArgb = 0xFF000000 |
        ((fr * l).round().clamp(0, 255) << 16) |
        ((fg * l).round().clamp(0, 255) << 8) |
        (fb * l).round().clamp(0, 255);
    return (argb, tintArgb);
  }

  /// 写入面的 4 个世界顶点（环绕顺序，供三角化 0-1-2 / 0-2-3）。
  static void _fillCorners(
    BlockFace f,
    int x,
    int y,
    int z,
    Float64List out,
  ) {
    final double x0 = x.toDouble();
    final double y0 = y.toDouble();
    final double z0 = z.toDouble();
    final double x1 = x0 + 1;
    final double y1 = y0 + 1;
    final double z1 = z0 + 1;
    switch (f) {
      case BlockFace.top:
        _setQuad(out, x0, y1, z0, x1, y1, z0, x1, y1, z1, x0, y1, z1);
      case BlockFace.bottom:
        _setQuad(out, x0, y0, z0, x0, y0, z1, x1, y0, z1, x1, y0, z0);
      case BlockFace.north: // -Z
        _setQuad(out, x0, y0, z0, x1, y0, z0, x1, y1, z0, x0, y1, z0);
      case BlockFace.south: // +Z
        _setQuad(out, x0, y0, z1, x0, y1, z1, x1, y1, z1, x1, y0, z1);
      case BlockFace.west: // -X
        _setQuad(out, x0, y0, z0, x0, y1, z0, x0, y1, z1, x0, y0, z1);
      case BlockFace.east: // +X
        _setQuad(out, x1, y0, z0, x1, y0, z1, x1, y1, z1, x1, y1, z0);
    }
  }

  static void _setQuad(
    Float64List o,
    double ax,
    double ay,
    double az,
    double bx,
    double by,
    double bz,
    double cx,
    double cy,
    double cz,
    double dx,
    double dy,
    double dz,
  ) {
    o[0] = ax;
    o[1] = ay;
    o[2] = az;
    o[3] = bx;
    o[4] = by;
    o[5] = bz;
    o[6] = cx;
    o[7] = cy;
    o[8] = cz;
    o[9] = dx;
    o[10] = dy;
    o[11] = dz;
  }

  static double _normalX(BlockFace f) => switch (f) {
        BlockFace.east => 1,
        BlockFace.west => -1,
        _ => 0,
      };

  static double _normalY(BlockFace f) => switch (f) {
        BlockFace.top => 1,
        BlockFace.bottom => -1,
        _ => 0,
      };

  static double _normalZ(BlockFace f) => switch (f) {
        BlockFace.south => 1,
        BlockFace.north => -1,
        _ => 0,
      };

  // ── 云（水平云面，R26i）─────────────────────────────────
  //
  // 用户诉求：云是**平行于水平面**、高度固定 64 格的云面；**无限刷新**（贴图
  // 无缝拼接天空盒）——相机移动时云场以相机为中心重定心、永远铺满视野；随昼夜
  // 自北向南（+Z）漂移。实现：在 y=64 处铺一层「云胞」网格，每胞用连续值噪声
  // 决定密度（>阈值成云、留空为天），密度驱动亮度 → 蓬松无缝；每帧重定心 +
  // 时间漂移 = 无限且无接缝。
  static void _emitClouds(
    List<RenderFace> out,
    VoxelWorld world,
    ViewBasis b,
    ProjectionParams proj,
    double far,
    double timePhase,
    int cloudChunks,
    void Function(Float32List, Float32List?, int, int, bool, [double]) pushFace,
  ) {
    const double cloudY = 64.0; // 水平云面高度（用户指定 64 格）
    // R26p2：覆盖半径由云层区块视距驱动（区块数 × 16 格），默认 3 = 48 格；
    // 重定心→无限（相机移动时云场始终以玩家为中心、铺满视野）。
    final double half = cloudChunks * 16.0;
    const double cell = 7.0; // 云胞间距（密度/性能平衡点）
    // R26n：相机在云层上（或云层高度）→ 不渲染云（避免从上方看/朝上看时
    // 云面糊成白/黄滤镜）。
    if (b.eyeY >= cloudY - 1.0) return;
    // 自北向南（+Z）漂移：一个昼夜（timePhase 0→1）移动约 120 格。
    final double drift = timePhase * 120.0;
    // 重定心：网格原点对齐到相机所在 cell，使云场始终以玩家为中心（无缝无限）。
    final double ox = (b.eyeX / cell).floor() * cell;
    final double oz = (b.eyeZ / cell).floor() * cell;
    for (double gx = -half; gx <= half; gx += cell) {
      for (double gz = -half; gz <= half; gz += cell) {
        final double wx = ox + gx;
        final double wz = oz + gz + drift;
        final double n = _cloudNoise(wx, wz); // 连续值噪声（无缝、无突跳）
        if (n < 0.52) continue; // 留空 → 天空
        final double bright = (0.74 + 0.26 * n).clamp(0.0, 1.0);
        // R26n：云改为**半透明**（α≈0.62，摄像机可透过）单顶面（非方块）。
        final int argb = Color.fromRGBO(
          (244 * bright).round(),
          (247 * bright).round(),
          (255 * bright).round(),
          0.62,
        ).toARGB32();
        _cloudQuad(
          out,
          wx - cell * 0.46,
          cloudY,
          wz - cell * 0.46,
          wx + cell * 0.46,
          wz + cell * 0.46,
          b,
          proj,
          far,
          pushFace,
          argb,
        );
      }
    }
  }

  /// 连续值噪声（两层 hash 双线性插值）：确定性、无缝、无帧间突跳。
  static double _cloudNoise(double x, double z) {
    final double fx = x * 0.11, fz = z * 0.11;
    final int xi = fx.floor(), zi = fz.floor();
    final double tx = fx - xi, tz = fz - zi;
    final double Function(double) s = (double v) => v * v * (3 - 2 * v);
    final double a = _hash2(xi, zi);
    final double bb = _hash2(xi + 1, zi);
    final double c = _hash2(xi, zi + 1);
    final double d = _hash2(xi + 1, zi + 1);
    final double top = a + (bb - a) * s(tx);
    final double bot = c + (d - c) * s(tx);
    return top + (bot - top) * s(tz);
  }

  /// 整数哈希 → [0,1)。
  static double _hash2(int x, int z) {
    int h = x * 374761393 + z * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    h ^= h >> 16;
    return (h & 0x7FFFFFFF) / 0x7FFFFFFF;
  }

  /// 投影一个半透明单顶面（云），并入批次与深度排序。
  static void _cloudQuad(
    List<RenderFace> out,
    double x0,
    double y,
    double z0,
    double x1,
    double z1,
    ViewBasis b,
    ProjectionParams proj,
    double far,
    void Function(Float32List, Float32List?, int, int, bool, [double]) pushFace,
    int argb,
  ) {
    final List<double> c = <double>[x0, y, z0, x1, y, z0, x1, y, z1, x0, y, z1];
    final Float32List xy = Float32List(8);
    double depthSum = 0;
    bool clipped = false;
    for (int i = 0; i < 4; i++) {
      final ScreenPoint? sp = VoxelCamera.projectWith(
        c[i * 3],
        c[i * 3 + 1],
        c[i * 3 + 2],
        b,
        proj,
      );
      if (sp == null) {
        clipped = true;
        break;
      }
      xy[i * 2] = sp.x;
      xy[i * 2 + 1] = sp.y;
      depthSum += sp.depth;
    }
    if (clipped) return;
    final double depth = depthSum / 4;
    if (depth > far) return;
    pushFace(xy, null, argb, argb, false, depth);
    out.add(RenderFace(
      xy: xy,
      argb: argb,
      depth: depth,
      voxel: Voxel.stone,
      face: BlockFace.top,
    ));
  }

  /// 把一个实体（默认一个 6 盒的小人）拆成方块盒，并入对应 Pass。
  ///
  /// 发光实体走半透明 Pass（自带 alpha），否则走不透明 Pass，与地形共用
  /// 同一套投影 / 分面亮度 / 雾，保证视觉连续。
  static void _emitEntity(
    List<RenderFace> opaque,
    List<RenderFace> translucent,
    VoxelEntity en,
    ViewBasis b,
    ProjectionParams proj,
    SkyPalette sky,
    RenderConfig config,
    double fogStart,
    double fogSpan,
    double far,
    void Function(Float32List, Float32List?, int, int, bool, [double]) pushFace,
  ) {
    final double px = en.position.x;
    final double py = en.position.y;
    final double pz = en.position.z;
    final double s = en.scale;
    final Color body = en.color;
    final Color head = shade(body, 1.18);
    final Color limb = shade(body, 0.82);
    final bool glow = en.glow;
    final double alpha = glow ? 0.6 : 1.0;
    final Voxel vmat = glow ? Voxel.water : Voxel.stone;
    final List<RenderFace> target = glow ? translucent : opaque;
    final bool skin = en.useSkin;

    final double leg = 0.9 * s;
    final double torsoTop = 1.7 * s;
    final double headTop = 2.2 * s;
    final double armLo = 0.95 * s;
    final double armHi = 1.65 * s;

    // 双腿
    _emitBox(target, px - 0.18, py, pz - 0.15, px - 0.02, py + leg, pz + 0.15,
        limb, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'legL' : null);
    _emitBox(target, px + 0.02, py, pz - 0.15, px + 0.18, py + leg, pz + 0.15,
        limb, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'legR' : null);
    // 躯干
    _emitBox(target, px - 0.35, py + leg, pz - 0.22, px + 0.35, py + torsoTop,
        pz + 0.22, body, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'torso' : null);
    // 头
    _emitBox(target, px - 0.25, py + torsoTop, pz - 0.25, px + 0.25, py + headTop,
        pz + 0.25, head, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'head' : null);
    // 双臂
    _emitBox(target, px - 0.55, py + armLo, pz - 0.15, px - 0.32, py + armHi,
        pz + 0.15, limb, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'armL' : null);
    _emitBox(target, px + 0.32, py + armLo, pz - 0.15, px + 0.55, py + armHi,
        pz + 0.15, limb, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'armR' : null);
  }

  /// 把一个轴对齐方块盒的 6 个面投影后并入 [out]（与地形面同一处理管线）。
  ///
  /// [pushFace] 把面拼进批量缓冲（画家一次性 drawVertices）；实体此前只写 [out]
  /// 导致批量模式下不绘制，现已修正。[skinPart] 非空且贴图开启/有皮肤时，
  /// 该盒各面按 MC 2× 皮肤布局映射图集 UV（走贴图批次），失败回退纯色。
  static void _emitBox(
    List<RenderFace> out,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    Color base,
    double alpha,
    SkyPalette sky,
    RenderConfig config,
    double fogStart,
    double fogSpan,
    double far,
    ViewBasis b,
    ProjectionParams proj,
    Voxel vmat, {
    List<PointLight> lights = const <PointLight>[],
    double sunWeight = 0,
    double sunX = 0,
    double sunY = 1,
    double sunZ = 0,
    required void Function(Float32List, Float32List?, int, int, bool, [double]) pushFace,
    String? skinPart,
  }) {
    // 实体取包围盒中心做点光采样（体积小，逐面精算没有收益）。
    final double cxm = (x0 + x1) * 0.5;
    final double cym = (y0 + y1) * 0.5;
    final double czm = (z0 + z1) * 0.5;
    // 六面顶点（与 [_fillCorners] 同环绕顺序：0-1-2-3）。
    final List<List<double>> quads = <List<double>>[
      <double>[x0, y1, z0, x1, y1, z0, x1, y1, z1, x0, y1, z1], // top
      <double>[x0, y0, z0, x0, y0, z1, x1, y0, z1, x1, y0, z0], // bottom
      <double>[x0, y0, z0, x1, y0, z0, x1, y1, z0, x0, y1, z0], // north
      <double>[x0, y0, z1, x0, y1, z1, x1, y1, z1, x1, y0, z1], // south
      <double>[x0, y0, z0, x0, y1, z0, x0, y1, z1, x0, y0, z1], // west
      <double>[x1, y0, z0, x1, y0, z1, x1, y1, z1, x1, y1, z0], // east
    ];
    final List<BlockFace> faceOrder = <BlockFace>[
      BlockFace.top,
      BlockFace.bottom,
      BlockFace.north,
      BlockFace.south,
      BlockFace.west,
      BlockFace.east,
    ];

    for (int k = 0; k < 6; k++) {
      final List<double> c = quads[k];
      final BlockFace f = faceOrder[k];
      final Float32List xy = Float32List(8);
      double depthSum = 0;
      bool clipped = false;
      for (int i = 0; i < 4; i++) {
        final ScreenPoint? sp = VoxelCamera.projectWith(
          c[i * 3],
          c[i * 3 + 1],
          c[i * 3 + 2],
          b,
          proj,
        );
        if (sp == null) {
          clipped = true;
          break;
        }
        xy[i * 2] = sp.x;
        xy[i * 2 + 1] = sp.y;
        depthSum += sp.depth;
      }
      if (clipped) continue;
      final double depth = depthSum / 4;
      if (depth > far) continue;
      final (double elm, int etint, double etintAmt) = _lighting(
        voxel: vmat,
        face: f,
        sky: sky,
        lights: lights,
        sunWeight: sunWeight,
        sunX: sunX,
        sunY: sunY,
        sunZ: sunZ,
        fx: cxm,
        fy: cym,
        fz: czm,
      );
      Color col = shade(base, elm, alpha: alpha);
      if (etintAmt > 0) {
        col = Color.lerp(col, Color(etint), etintAmt)!.withValues(alpha: alpha);
      }
      // 雾距（smoothstep）：实体同样融入地平线雾，避免远处僵尸/掉落物突兀。
      double fogT = 0;
      if (config.fogEnabled) {
        final double raw = ((depth - fogStart) / fogSpan).clamp(0.0, 1.0);
        fogT = raw * raw * (3 - 2 * raw);
        col = Color.lerp(col, sky.fog, fogT)!.withValues(alpha: alpha);
      }
      // 皮肤 UV（并入同一图集 → 走贴图批次；无皮肤/未开启/失败回退纯色）。
      Float32List? uv;
      if (skinPart != null && config.textureEnabled && VoxelTextureAtlas.hasSkin) {
        final Float32List? rect = VoxelTextureAtlas.skinRectFor(skinPart, f.index);
        if (rect != null) {
          uv = _skinUV(rect, f, x0, y0, z0, x1, y1, z1);
        }
      }
      final int argb = col.toARGB32();
      // 贴图调制色：白色基 × 亮度 ×（远→雾色），乘到皮肤纹理上呈明暗/雾。
      final double l = elm.clamp(0.0, 1.0);
      final int fr = ((1 - fogT) * 255 + fogT * sky.fog.r * 255).round();
      final int fg = ((1 - fogT) * 255 + fogT * sky.fog.g * 255).round();
      final int fb = ((1 - fogT) * 255 + fogT * sky.fog.b * 255).round();
      final int tintArgb = 0xFF000000 |
          ((fr * l).round().clamp(0, 255) << 16) |
          ((fg * l).round().clamp(0, 255) << 8) |
          (fb * l).round().clamp(0, 255);
      // 入批量缓冲（贴图 / 纯色两路），保证批量模式可见。
      pushFace(xy, uv, argb, tintArgb, alpha < 1, depth);
      out.add(RenderFace(
        xy: xy,
        argb: argb,
        depth: depth,
        voxel: vmat,
        face: f,
      ));
    }
  }

  /// 把某盒某面的 4 角（[_fillCorners] 环绕序 0-1-2-3）映射到皮肤矩形内的图集 UV。
  ///
  /// u 取水平轴（top/bottom→x，north/south→x，west/east→z），v 取竖直轴（y）；
  /// v 翻转（1 - v）使纹理上缘对齐盒顶，保证头脸等正向显示。
  static Float32List _skinUV(
    Float32List rect,
    BlockFace f,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
  ) {
    final double sx = rect[0], sy = rect[1], sw = rect[2], sh = rect[3];
    final double dx = x1 - x0, dy = y1 - y0, dz = z1 - z0;
    late final List<(double, double)> uvLocal;
    switch (f) {
      case BlockFace.top:
      case BlockFace.bottom:
        uvLocal = <(double, double)>[
          ((x0 - x0) / dx, (z0 - z0) / dz),
          ((x1 - x0) / dx, (z0 - z0) / dz),
          ((x1 - x0) / dx, (z1 - z0) / dz),
          ((x0 - x0) / dx, (z1 - z0) / dz),
        ];
      case BlockFace.north:
      case BlockFace.south:
        uvLocal = <(double, double)>[
          ((x0 - x0) / dx, (y0 - y0) / dy),
          ((x1 - x0) / dx, (y0 - y0) / dy),
          ((x1 - x0) / dx, (y1 - y0) / dy),
          ((x0 - x0) / dx, (y1 - y0) / dy),
        ];
      case BlockFace.west:
      case BlockFace.east:
        uvLocal = <(double, double)>[
          ((z0 - z0) / dz, (y0 - y0) / dy),
          ((z1 - z0) / dz, (y0 - y0) / dy),
          ((z1 - z0) / dz, (y1 - y0) / dy),
          ((z0 - z0) / dz, (y1 - y0) / dy),
        ];
    }
    final Float32List out = Float32List(8);
    for (int i = 0; i < 4; i++) {
      final double u = uvLocal[i].$1;
      final double v = 1 - uvLocal[i].$2; // 翻转：纹理上=面顶
      out[i * 2] = sx + u * sw;
      out[i * 2 + 1] = sy + v * sh;
    }
    return out;
  }

  /// R26n：chunk AABB（8 角）是否与相机视锥相交。任一角的相机空间坐标
  /// 落在近/远/左右/上下范围内即可见——**保守判定：只会多渲染、绝不漏渲染**
  /// （用户要求「不剔除玩家所在区块，只剔除视角外区块」；含俯仰，看脚下/看天
  /// 都正确）。8 角 × 每区块一次，量级可忽略。
  static bool _chunkInFrustum(
    ViewBasis b,
    ProjectionParams p,
    int x0,
    int z0,
    int cs,
    int maxY,
  ) {
    // 由投影参数反推视锥半角正切：tanHalfX = halfW / scaleX，tanHalfY = halfH / scaleY。
    final double tanX = p.halfW / p.scaleX;
    final double tanY = p.halfH / p.scaleY;
    for (int i = 0; i < 8; i++) {
      final double wx = x0 + ((i & 1) == 0 ? 0.0 : cs.toDouble());
      final double wy = (i & 2) == 0 ? 0.0 : maxY.toDouble();
      final double wz = z0 + ((i & 4) == 0 ? 0.0 : cs.toDouble());
      final double dx = wx - b.eyeX;
      final double dy = wy - b.eyeY;
      final double dz = wz - b.eyeZ;
      final double vz = dx * b.fwdX + dy * b.fwdY + dz * b.fwdZ;
      if (vz < 0.02 || vz > 8192) continue; // 近/远（远取宽松，距离上限已先行把关）
      final double vx = dx * b.rightX + dy * b.rightY + dz * b.rightZ;
      final double vy = dx * b.upX + dy * b.upY + dz * b.upZ;
      if (vx.abs() <= vz * tanX && vy.abs() <= vz * tanY) return true;
    }
    return false;
  }

  /// R26j：烘焙 4 角环境光遮蔽（AO）。每角在**面平面内**查 2 个正交邻居
  /// + 1 个对角邻居：被 3 面夹击 → 0.33（≈用户「×0.3 涂黑」），完全暴露 → 1.0。
  /// 相机无关（只依赖世界遮挡），随 chunk 几何缓存复用。
  static Float32List _cornerAO(
    VoxelWorld w,
    BlockFace f,
    int x,
    int y,
    int z,
    Float64List corners,
  ) {
    // 法线轴 + 两个切向轴（X=0, Y=1, Z=2）。
    final int nax = (f == BlockFace.top || f == BlockFace.bottom)
        ? 1
        : (f == BlockFace.north || f == BlockFace.south ? 2 : 0);
    final int t1 = nax == 0 ? 1 : 0;
    final int t2 = 3 - nax - t1; // 0+1+2=3
    // 正法线面（top/south/east）位于 block+1 层，负法线面位于 block 层。
    final bool posN = f == BlockFace.top ||
        f == BlockFace.south ||
        f == BlockFace.east;
    final int faceLevel = posN ? (nax == 0 ? x : (nax == 1 ? y : z)) + 1
        : (nax == 0 ? x : (nax == 1 ? y : z));
    final List<int> block = <int>[x, y, z];
    final Float32List ao = Float32List(4);
    for (int i = 0; i < 4; i++) {
      final double c0 = corners[i * 3];
      final double c1 = corners[i * 3 + 1];
      final double c2 = corners[i * 3 + 2];
      final List<double> cc = <double>[c0, c1, c2];
      final int s1 = cc[t1] >= block[t1] + 0.5 ? 1 : -1;
      final int s2 = cc[t2] >= block[t2] + 0.5 ? 1 : -1;
      final List<int> n1 = <int>[x, y, z];
      n1[t1] = block[t1] + s1;
      n1[nax] = faceLevel;
      final List<int> n2 = <int>[x, y, z];
      n2[t2] = block[t2] + s2;
      n2[nax] = faceLevel;
      final List<int> nd = <int>[x, y, z];
      nd[t1] = block[t1] + s1;
      nd[t2] = block[t2] + s2;
      nd[nax] = faceLevel;
      final int o1 = w.get(n1[0], n1[1], n1[2]).isEmpty ? 0 : 1;
      final int o2 = w.get(n2[0], n2[1], n2[2]).isEmpty ? 0 : 1;
      final int od = w.get(nd[0], nd[1], nd[2]).isEmpty ? 0 : 1;
      ao[i] = (3 - o1 - o2 - od) / 3.0;
    }
    return ao;
  }

  /// R26l：面 4 条边的可见性（「描边只描我能看见的轮廓」）。
  ///
  /// 边 [e] 连接角 [e] 与角 `(e+1)%4`。取边中点沿「面平面内、垂直该边」的
  /// 外方向指向的邻块：邻块为空 → 轮廓边，描；邻块「同法线面」也朝相机
  /// （共面相邻）→ 内部边，不描；邻面背向相机 → 轮廓边，描。
  /// 结果与 `pushFace` 的边序一致（角序环绕）。每帧计算（相机相关），
  /// 成本 = 4×`world.get` + 点积，远小于投影本身。
  static List<bool> _faceEdgeMask(
    VoxelWorld w,
    CachedFace cf,
    ViewBasis b,
  ) {
    final double ex = b.eyeX, ey = b.eyeY, ez = b.eyeZ;
    final double nx = cf.nx, ny = cf.ny, nz = cf.nz;
    final Float64List c = cf.corners;
    final double cx = cf.bx, cy = cf.by, cz = cf.bz; // 块中心
    final double fcX = cx + nx * 0.5, fcY = cy + ny * 0.5, fcZ = cz + nz * 0.5;
    final int bx = cx.round(), by = cy.round(), bz = cz.round();
    final List<bool> vis = List<bool>.filled(4, true);
    for (int e = 0; e < 4; e++) {
      final int i0 = e, i1 = (e + 1) % 4;
      final double mx = (c[i0 * 3] + c[i1 * 3]) / 2;
      final double my = (c[i0 * 3 + 1] + c[i1 * 3 + 1]) / 2;
      final double mz = (c[i0 * 3 + 2] + c[i1 * 3 + 2]) / 2;
      // 面平面内、垂直该边的外方向（= 面中心 → 边中点，取单位符号）。
      int ox = 0, oy = 0, oz = 0;
      final double ddx = mx - fcX, ddy = my - fcY, ddz = mz - fcZ;
      if (ddx.abs() > 0.01) ox = ddx > 0 ? 1 : -1;
      if (ddy.abs() > 0.01) oy = ddy > 0 ? 1 : -1;
      if (ddz.abs() > 0.01) oz = ddz > 0 ? 1 : -1;
      final int nbX = bx + ox, nbY = by + oy, nbZ = bz + oz;
      // 邻块为空 → 轮廓边，保留描边。
      if (w.get(nbX, nbY, nbZ).isEmpty) continue;
      // 邻块同法线面是否朝相机：邻面中心 = 邻块中心 + 0.5·法线。
      final double nfX = nbX + 0.5 + nx * 0.5 - ex;
      final double nfY = nbY + 0.5 + ny * 0.5 - ey;
      final double nfZ = nbZ + 0.5 + nz * 0.5 - ez;
      final double dot = nfX * nx + nfY * ny + nfZ * nz;
      if (dot < 0) vis[e] = false; // 邻面朝相机 → 共面内部边，不描
    }
    return vis;
  }

  /// 生成单个区块的**相机无关**几何（occlusion 剔除后的可见外壳面）。
  ///
  /// 只依赖地形（与相机朝向 / 位置无关），故可被 [VoxelChunkCache] 跨帧缓存。
  /// 不做 backFaceCull / 投影 / 雾——这些相机相关步骤留在每帧投影阶段。
  static ChunkMesh _buildChunkMesh(
    VoxelWorld world,
    int cx0,
    int cz0,
    int step,
    int off,
    RenderConfig config,
  ) {
    const int cs = RenderConfig.chunkSize;
    final List<CachedFace> faces = <CachedFace>[];
    int columns = 0;
    for (int x = cx0 + off; x < cx0 + cs; x += step) {
      for (int z = cz0 + off; z < cz0 + cs; z += step) {
        columns++;
        // R23q 地表带遍历：只查地形高度附近的 y（含树冠缓冲）。
        // R23u：取 5×5 邻域最高地形，兜住相邻更高群系（山地）树冠的悬垂。
        int hBase = world.terrainHeightAt(x, z);
        for (int dx = -2; dx <= 2; dx++) {
          for (int dz = -2; dz <= 2; dz++) {
            final int hn = world.terrainHeightAt(x + dx, z + dz);
            if (hn > hBase) hBase = hn;
          }
        }
        final int yStart = (hBase - 6).clamp(0, world.maxY - 1);
        final int yEnd = (hBase + 10).clamp(0, world.maxY - 1);
        // R26j：斜度着色——由列高差判断陡坡（压暗 20%）/ 平地（提亮 10%）。
        // 相机无关，随 chunk 缓存复用。
        final int hC = world.terrainHeightAt(x, z);
        final double dX = (world.terrainHeightAt(x + 1, z) - hC).toDouble();
        final double dZ = (world.terrainHeightAt(x, z + 1) - hC).toDouble();
        final double slope = math.sqrt(dX * dX + dZ * dZ);
        final double tilt = slope > 2.0 ? 0.8 : (slope < 0.5 ? 1.1 : 1.0);
        for (int y = yStart; y <= yEnd; y++) {
          final Voxel v = world.get(x, y, z);
          if (v.isEmpty) continue;
          for (final BlockFace f in BlockFace.values) {
            if (config.occlusionCull && isFaceHidden(world, x, y, z, f, v)) {
              continue;
            }
            final double nx = _normalX(f);
            final double ny = _normalY(f);
            final double nz = _normalZ(f);
            final Float64List c = Float64List(12);
            _fillCorners(f, x, y, z, c);
            faces.add(CachedFace(
              c,
              v,
              f,
              nx,
              ny,
              nz,
              x + 0.5,
              y + 0.5,
              z + 0.5,
              _cornerAO(world, f, x, y, z, c),
              tilt,
            ));
          }
        }
      }
    }
    return ChunkMesh(faces, columns);
  }
}

/// 缓存的单个方块面（相机无关：世界坐标 + 类型 + 法线 + 块中心）。
class CachedFace {
  CachedFace(
    this.corners,
    this.voxel,
    this.face,
    this.nx,
    this.ny,
    this.nz,
    this.bx,
    this.by,
    this.bz,
    this.ao,
    this.tilt,
  );

  /// 4 个世界顶点（12 个 double，按四边形环绕顺序）。
  final Float64List corners;

  final Voxel voxel;
  final BlockFace face;

  /// 面法线（backFaceCull 用，缓存省每帧重算）。
  final double nx, ny, nz;

  /// 所属方块中心（世界坐标；backFaceCull 判定与水面波纹基准）。
  final double bx, by, bz;

  /// R26j：4 角环境光遮蔽（1.0 亮 → 0.33 暗角），逐顶点烘焙进颜色。
  /// 相机无关（只依赖世界遮挡），随 chunk 几何缓存复用。
  final Float32List ao;

  /// R26j：斜度着色系数（陡坡 0.8 / 平地 1.1 / 常态 1.0）。
  final double tilt;
}

/// 一个区块的可见面集合（相机无关的几何体）。
class ChunkMesh {
  ChunkMesh(this.faces, this.columns);

  final List<CachedFace> faces;

  /// 本区块遍历的列数（调试统计）。
  final int columns;
}

/// 区块几何缓存：跨帧复用 occlusion 可见面，消除每帧百万级 [VoxelWorld.get]
/// + [VoxelRenderer.isFaceHidden]（邻居查询嵌套）。
///
/// key = (cx, cz, lod)：LOD 是相机相关的（决定采样步长），故纳入 key—
/// 相机移动跨 LOD 边界时该区块 key 变化 → 自然重建。相机平移 / 旋转
/// （同 lod）则直接命中，几何完全复用。
///
/// 编辑方块后调用 [invalidate] 使受影响区块失效（或 [clear] 整体清空）。
class VoxelChunkCache {
  VoxelChunkCache({this.maxChunks = 256});

  /// 最大缓存区块数（LRU 近似：超限删最老插入项）。
  /// 默认 256 覆盖 64 格半径窗口（9×9=81 区块）绰绰有余，玩家移动时
  /// 仅窗口边缘少数区块进出，远小于每帧全窗口重建。
  final int maxChunks;

  final Map<(int, int, int), ChunkMesh> _chunks =
      <(int, int, int), ChunkMesh>{};

  /// 命中 / 未命中计数（调试诊断）。
  int hits = 0;
  int misses = 0;

  // key = (cx, cz, lod)。用记录类型做**无碰撞**键——早期用 XOR 哈希会
  // 在小坐标对上发生碰撞，导致首帧就误命中（缓存串台）。记录键值相等、零碰撞。
  static (int, int, int) _key(int cx, int cz, int lod) => (cx, cz, lod);

  ChunkMesh? get(int cx, int cz, int lod) {
    final ChunkMesh? m = _chunks[_key(cx, cz, lod)];
    if (m != null) {
      hits++;
    } else {
      misses++;
    }
    return m;
  }

  void put(int cx, int cz, int lod, ChunkMesh mesh) {
    final (int, int, int) k = _key(cx, cz, lod);
    if (_chunks.length >= maxChunks && !_chunks.containsKey(k)) {
      // LRU 近似：删最老插入的（LinkedHashMap 保持插入序）。
      _chunks.remove(_chunks.keys.first);
    }
    _chunks[k] = mesh;
  }

  /// 使 (cx,cz) 区块的所有 LOD 版本失效（编辑后调用）。
  void invalidate(int cx, int cz) {
    for (int lod = 0; lod <= 3; lod++) {
      _chunks.remove(_key(cx, cz, lod));
    }
  }

  void clear() => _chunks.clear();
}
