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
    this.waterAnimation = true,
    this.skyGradient = true,
    this.viewDistanceChunks = 4,
    this.lodStartChunks = 2,
    this.lodStepChunks = 2,
    this.textureEnabled = true,
    this.maxChunkBuildsPerFrame = 4,
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

  /// 是否使用 16×16 纹理图集贴图（R24c）。关闭则回退纯色平铺。
  final bool textureEnabled;

  /// R26f：每帧最多构建的 chunk 数（分帧构建）。跑图/转身时新 chunk miss
  /// 全部在单帧建会卡；限制预算后，超出的 chunk 本帧跳过、下帧补建
  /// （缓存天然记录已建/未建，帧间只差 1 帧，雾遮挡下无感）。
  final int maxChunkBuildsPerFrame;

  RenderConfig copyWith({
    double? renderDistance,
    int? maxFaces,
    bool? fogEnabled,
    bool? occlusionCull,
    bool? backFaceCull,
    bool? waterAnimation,
    bool? skyGradient,
    int? viewDistanceChunks,
    int? lodStartChunks,
    int? lodStepChunks,
    bool? textureEnabled,
  }) {
    return RenderConfig(
      renderDistance: renderDistance ?? this.renderDistance,
      maxFaces: maxFaces ?? this.maxFaces,
      fogEnabled: fogEnabled ?? this.fogEnabled,
      occlusionCull: occlusionCull ?? this.occlusionCull,
      backFaceCull: backFaceCull ?? this.backFaceCull,
      waterAnimation: waterAnimation ?? this.waterAnimation,
      skyGradient: skyGradient ?? this.skyGradient,
      viewDistanceChunks: viewDistanceChunks ?? this.viewDistanceChunks,
      lodStartChunks: lodStartChunks ?? this.lodStartChunks,
      lodStepChunks: lodStepChunks ?? this.lodStepChunks,
      textureEnabled: textureEnabled ?? this.textureEnabled,
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
    this.opaquePlain,
    this.opaqueTextured,
    this.waterBatch,
    this.edges,
    this.edgeBatches = const <VoxelMeshBatch>[],
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

  /// 批量网格（R25 GPU 加速）：非贴图不透明面 / 贴图不透明面 / 水面 / 描边线段。
  /// 为空时画家回退到逐面绘制（如 [empty] 占位帧）。
  final VoxelMeshBatch? opaquePlain;
  final VoxelMeshBatch? opaqueTextured;
  final VoxelMeshBatch? waterBatch;
  final VoxelMeshBatch? edges;

  /// R26b 描边深度桶：按相机深度分 8 桶、远→近排列，绘制时前面面的描边
  /// 正确盖住后面面的描边（修复「描边透视」——旧实现所有描边一次提交，
  /// 后面面的描边会穿透前面面显示）。空 = 无描边。
  final List<VoxelMeshBatch> edgeBatches;

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
    columnsVisited: 0,
    facesCollected: 0,
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

    final List<RenderFace> allFaces = <RenderFace>[];

    // R25 批量缓冲：把每面顶点拼进单一列表，画家一次性提交（见 VoxelMeshBatch）。
    // 每面 6 顶点（2 三角形）；线段批次（描边）每边 2 顶点。
    final List<double> plainPos = <double>[];
    final List<int> plainCol = <int>[];
    final List<double> texPos = <double>[];
    final List<double> texUV = <double>[];
    final List<int> texCol = <int>[];
    final List<double> waterPos = <double>[];
    final List<double> waterUV = <double>[];
    final List<int> waterCol = <int>[];
    final List<double> edgePos = <double>[];
    final List<int> edgeCol = <int>[];
    // R26b：描边深度桶（远→近 8 桶）——修复「描边透视」。
    final List<List<double>> edgePosB =
        List<List<double>>.generate(8, (_) => <double>[]);
    final List<List<int>> edgeColB =
        List<List<int>>.generate(8, (_) => <int>[]);
    const int kOutline = 0x4D000000; // 描边色：~30% 黑，ARGB
    // R26f：描边最大深度（世界格）。超过则不生成描边（远处不可见 + 省面数）。
    const double kEdgeMaxDepth = 15.0;

    // 把一面拼进对应批次（贴图 / 纯色 / 水 / 描边）。
    // [depth]：面中心相机深度（0~far），描边按其落入深度桶，绘制时远→近，
    // 使前面面的描边正确盖住后面面的描边（消除透视）。
    void pushFace(Float32List xy, Float32List? uv, int argb, int tint,
        bool translucentFace, [double depth = 0]) {
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
      if (uv != null) {
        final double u0 = uv[0], v0 = uv[1];
        final double u1 = uv[2], v1 = uv[3];
        final double u2 = uv[4], v2 = uv[5];
        final double u3 = uv[6], v3 = uv[7];
        if (translucentFace) {
          waterPos
            ..add(x0)..add(y0)..add(x1)..add(y1)..add(x2)..add(y2)
            ..add(x0)..add(y0)..add(x2)..add(y2)..add(x3)..add(y3);
          waterUV
            ..add(u0)..add(v0)..add(u1)..add(v1)..add(u2)..add(v2)
            ..add(u0)..add(v0)..add(u2)..add(v2)..add(u3)..add(v3);
          waterCol..add(c)..add(c)..add(c)..add(c)..add(c)..add(c);
        } else {
          texPos
            ..add(x0)..add(y0)..add(x1)..add(y1)..add(x2)..add(y2)
            ..add(x0)..add(y0)..add(x2)..add(y2)..add(x3)..add(y3);
          texUV
            ..add(u0)..add(v0)..add(u1)..add(v1)..add(u2)..add(v2)
            ..add(u0)..add(v0)..add(u2)..add(v2)..add(u3)..add(v3);
          texCol..add(c)..add(c)..add(c)..add(c)..add(c)..add(c);
        }
      } else {
        plainPos
          ..add(x0)..add(y0)..add(x1)..add(y1)..add(x2)..add(y2)
          ..add(x0)..add(y0)..add(x2)..add(y2)..add(x3)..add(y3);
        plainCol..add(c)..add(c)..add(c)..add(c)..add(c)..add(c);
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
        final List<double> ebp = edgePosB[(depth / camera.far * 8)
            .floor()
            .clamp(0, 7)];
        final List<int> ebc = edgeColB[(depth / camera.far * 8)
            .floor()
            .clamp(0, 7)];
        for (int e = 0; e < 4; e++) {
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
    final double cosLimit = math.cos(math.min(math.pi, halfFovX + 0.35));
    // 视线水平分量长度（恒为 1，保留原判定以防未来改用含俯仰的前向）。
    final double horizLen = math.sqrt(hFwdX * hFwdX + hFwdZ * hFwdZ);
    final bool cullAzimuth = horizLen >= 0.3;

    // 雾距（fogStart = 40% 渲染距离）：远处在视距边缘 100% 融入天空雾色，
    // 像基岩版那样把 LOD 接缝"化"进地平线雾里，消除硬切 popping。
    final double fogStart = maxDist * 0.40;
    final double fogSpan = math.max(1.0, maxDist - fogStart);

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

        // R26f：水平视锥剔除——chunk 中心相对相机的方位角超出
        //（halfFovX + chunk 角余量）直接跳过整块。投影层只省"相机后方"面，
        // 这里把侧面 60°~90° 外的整块 chunk 挡在收集/投影之前，顶点转换 -30~50%。
        if (cullAzimuth) {
          final double dot = (ccx * hFwdX + ccz * hFwdZ) / cdist;
          final double chunkAng =
              math.atan(cs * 0.75 / math.max(1.0, cdist));
          if (dot < math.cos(halfFovX + chunkAng)) continue;
        }

        // LOD 级别（相机相关：决定采样步长，故计入缓存 key）。
        int lod = 0;
        if (cdist > lodStart) {
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
          if (cullAzimuth) {
            final double colX = cf.bx - b.eyeX;
            final double colZ = cf.bz - b.eyeZ;
            final double d2 = colX * colX + colZ * colZ;
            if (d2 > 4) {
              final double d = math.sqrt(d2);
              if ((colX * hFwdX + colZ * hFwdZ) / d < cosLimit) continue;
            }
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
          pushFace(xy, uv, argb, tint, cf.voxel.isTransparent, depth);
        }
      }
    }

    // 实体（如 AI 陪伴小人）：当作额外方块盒，与地形一起参与深度排序 / 预算裁剪。
    // R24c：实体面也并入同一全局桶（不再分 opaque/translucent 两 Pass），
    // 画家算法下所有面统一远→近排序，水/玻璃才能被正确遮挡。
    for (final VoxelEntity en in entities) {
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
    final VoxelMeshBatch? opaquePlain = plainPos.isEmpty
        ? null
        : VoxelMeshBatch(
            positions: Float32List.fromList(plainPos),
            colors: Int32List.fromList(plainCol),
          );
    final VoxelMeshBatch? opaqueTextured = texPos.isEmpty
        ? null
        : VoxelMeshBatch(
            positions: Float32List.fromList(texPos),
            colors: Int32List.fromList(texCol),
            uv: Float32List.fromList(texUV),
          );
    final VoxelMeshBatch? waterBatch = waterPos.isEmpty
        ? null
        : VoxelMeshBatch(
            positions: Float32List.fromList(waterPos),
            colors: Int32List.fromList(waterCol),
            uv: Float32List.fromList(waterUV),
          );
    final VoxelMeshBatch? edgesBatch = edgePos.isEmpty
        ? null
        : VoxelMeshBatch(
            positions: Float32List.fromList(edgePos),
            colors: Int32List.fromList(edgeCol),
          );
    // R26b：描边深度桶（远→近，绘制时正确遮挡，修「描边透视」）。
    final List<VoxelMeshBatch> edgeBatches = <VoxelMeshBatch>[
      for (int i = 0; i < 8; i++)
        if (edgePosB[i].isNotEmpty)
          VoxelMeshBatch(
            positions: Float32List.fromList(edgePosB[i]),
            colors: Int32List.fromList(edgeColB[i]),
          ),
    ];

    return VoxelFrame(
      sky: sky,
      opaque: allFaces,
      translucent: const <RenderFace>[],
      opaquePlain: opaquePlain,
      opaqueTextured: opaqueTextured,
      waterBatch: waterBatch,
      edges: edgesBatch,
      edgeBatches: edgeBatches,
      sunX: sd.x,
      sunY: sd.y,
      sunZ: sd.z,
      sunWeight: sunWeight,
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

  /// 面法线（单位向量，供方向光点乘）。
  static (double, double, double) normalOf(BlockFace f) => switch (f) {
        BlockFace.top => (0.0, 1.0, 0.0),
        BlockFace.bottom => (0.0, -1.0, 0.0),
        BlockFace.north => (0.0, 0.0, -1.0),
        BlockFace.south => (0.0, 0.0, 1.0),
        BlockFace.west => (-1.0, 0.0, 0.0),
        BlockFace.east => (1.0, 0.0, 0.0),
      };

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

  // ── 云（世界空间方块云，R26b）─────────────────────────────

  /// 生成一帧的世界空间方块云，并入统一批次/深度排序。
  ///
  /// 用户反馈旧云是「屏幕上固定的半透明椭圆」→ 重做为：**不透明方块云、
  /// 自北向南（+Z）漂移、在天上飘**（随相机位置铺开，昼夜时相驱动漂移）。
  /// 云层高 = 地形之上 12 格；云朵以相机为中心确定性排布，避免帧间跳变。
  static void _emitClouds(
    List<RenderFace> out,
    VoxelWorld world,
    ViewBasis b,
    ProjectionParams proj,
    double far,
    double timePhase,
    void Function(Float32List, Float32List?, int, int, bool, [double]) pushFace,
  ) {
    final double cloudY = world.maxY + 12;
    const double radius = 46.0;
    // 自北向南漂移：一个昼夜（timePhase 0→1，10 分钟）移动约 480 格。
    final double drift = timePhase * 480.0;
    final double cx = b.eyeX;
    final double cz = b.eyeZ;
    const int n = 10;
    for (int i = 0; i < n; i++) {
      // 黄金角排布 + 确定性半径（与 i 无关的状态 → 每帧稳定，只有漂移在动）。
      final double ang = i * 2.399963229728653;
      final double r = 7.0 + (i * 37.7) % (radius * 0.85);
      final double wx = cx + math.cos(ang) * r;
      final double wz = cz + math.sin(ang) * r + drift;
      // 主块 + 错落子块（固定 pattern，构出蓬松轮廓）。
      _cloudBlock(out, wx - 5, cloudY, wz - 2, wx + 5, cloudY + 1.5, wz + 2,
          b, proj, far, pushFace);
      _cloudBlock(out, wx - 2, cloudY, wz - 6, wx + 2, cloudY + 1.5, wz - 2, b,
          proj, far, pushFace);
      _cloudBlock(out, wx + 2, cloudY, wz + 1, wx + 7, cloudY + 1.5, wz + 4, b,
          proj, far, pushFace);
      _cloudBlock(out, wx - 8, cloudY, wz + 3, wx - 3, cloudY + 1.5, wz + 6, b,
          proj, far, pushFace);
      _cloudBlock(out, wx - 1, cloudY + 1.5, wz - 3, wx + 4, cloudY + 2.5, wz +
          1, b, proj, far, pushFace);
    }
  }

  /// 投影一个不透明白色方块（云），并入批次与深度排序。
  static void _cloudBlock(
    List<RenderFace> out,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    ViewBasis b,
    ProjectionParams proj,
    double far,
    void Function(Float32List, Float32List?, int, int, bool, [double]) pushFace,
  ) {
    const int argb = 0xFFF6F9FF; // 云白（不透明）
    final List<List<double>> quads = <List<double>>[
      <double>[x0, y1, z0, x1, y1, z0, x1, y1, z1, x0, y1, z1], // top
      <double>[x0, y0, z0, x0, y0, z1, x1, y0, z1, x1, y0, z0], // bottom
      <double>[x0, y0, z0, x1, y0, z0, x1, y1, z0, x0, y1, z0], // north
      <double>[x0, y0, z1, x0, y1, z1, x1, y1, z1, x1, y0, z1], // south
      <double>[x0, y0, z0, x0, y1, z0, x0, y1, z1, x0, y0, z1], // west
      <double>[x1, y0, z0, x1, y0, z1, x1, y1, z1, x1, y1, z0], // east
    ];
    for (final List<double> c in quads) {
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
      pushFace(xy, null, argb, argb, false, depth);
      out.add(RenderFace(
        xy: xy,
        argb: argb,
        depth: depth,
        voxel: Voxel.stone,
        face: BlockFace.top,
      ));
    }
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
  );

  /// 4 个世界顶点（12 个 double，按四边形环绕顺序）。
  final Float64List corners;

  final Voxel voxel;
  final BlockFace face;

  /// 面法线（backFaceCull 用，缓存省每帧重算）。
  final double nx, ny, nz;

  /// 所属方块中心（世界坐标；backFaceCull 判定与水面波纹基准）。
  final double bx, by, bz;
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
