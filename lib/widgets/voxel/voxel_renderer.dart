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

/// P6·R26r18：LOD 质量档位（替代原 bool lodEnabled）。
/// - off：所有距离满精度方阵（关闭 LOD，最重但最清晰）。
/// - balanced：原 2 档马赛克（cell 4 / 16）。
/// - high：P1 多档细 LOD（cell 4/8/16/32 连续降级 + 迟滞防闪烁）。
enum LodQuality { off, balanced, high }

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
    // R26r18·P6：LOD 质量档位（off=全满精度方阵 / balanced=原 2 档 / high=P1 多档细）。
    this.lodQuality = LodQuality.high,
    // R26r18·P3：LOD 通道区块级视锥剔除开关（默认开，FP/TP 下远景面数约减半）。
    this.lodFrustumCull = true,
    // R26fl：手电筒模式——FOV 不变，用「完整视线方向」的窄锥剔除（含俯视），
    // 锥内面按偏离视线中心衰减亮度（边界黑化）+ 画家层泛光。默认关。
    this.flashlight = false,
    // 手电筒光锥半角（度）：中心全亮，边界渐暗到剔除。
    this.flashlightHalfDeg = 22,
    // R26lod：LOD 参数体系（用户确认：开关/起始/步长格/采样2幂/最远区块）。
    this.lodMasterEnabled = true,
    this.lodStepBlocks = 16,
    this.lodSampleBase = 4,
    this.lodMaxChunks = 8,
    // 满精度带半径（区块）：perf/smooth=1（3×3 满精度，带外近处即 LOD——
    // 性能受限时近处也合成大方块）；standard/high=2（5×5 满精度）。
    this.fullBandChunks = 2,
    // 每帧最多新建的 LOD 单元数（分帧渐进；测试/诊断给大值取全量）。
    this.lodBuildBudget = 6,
    // R26fx：画面开关——环境光屏蔽 AO / 太阳投影阴影（默认开，可设置关闭）。
    this.aoEnabled = true,
    this.shadowRender = true,
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

  /// P6·R26r18：LOD 质量档位（替代原 bool lodEnabled）。
  /// off=所有距离满精度方阵；balanced=原 2 档马赛克；high=P1 多档细 LOD + 迟滞。
  final LodQuality lodQuality;

  /// 兼容旧调用点（buildFrame 满精度带判定）：off 时等价原 lodEnabled=false。
  bool get lodEnabled => lodQuality != LodQuality.off;

  /// P3·R26r18：LOD 通道区块级视锥剔除（camera 后半球单元粗剔除，面数约减半）。
  final bool lodFrustumCull;

  /// R26fl：手电筒模式——完整视线窄锥剔除 + 边界黑化 + 泛光（独立于 FOV）。
  final bool flashlight;

  /// 手电筒光锥半角（度）。
  final double flashlightHalfDeg;

  /// LOD 总开关（独立于 lodQuality 档位；false = 强制无远景 LOD）。
  final bool lodMasterEnabled;

  /// LOD 步长（格）：每档向外推的间距。
  final int lodStepBlocks;

  /// LOD 采样基数（最细大方块边长：2/4/8）。
  final int lodSampleBase;

  /// LOD 最远渲染距离（区块；可大于基础视距）。
  final int lodMaxChunks;

  /// 满精度带半径（区块）。
  final int fullBandChunks;

  /// 每帧最多新建的 LOD 单元数（分帧渐进，避免首帧卡顿）。
  final int lodBuildBudget;

  /// 环境光屏蔽（AO）：方块角落/缝隙变暗增强立体感；关 = 均匀亮度更省。
  final bool aoEnabled;

  /// 太阳投影阴影：顶面被太阳方向相邻方块遮挡时调暗。
  final bool shadowRender;

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
    LodQuality? lodQuality,
    bool? lodFrustumCull,
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
      lodQuality: lodQuality ?? this.lodQuality,
      lodFrustumCull: lodFrustumCull ?? this.lodFrustumCull,
      flashlight: flashlight ?? this.flashlight,
      flashlightHalfDeg: flashlightHalfDeg ?? this.flashlightHalfDeg,
      lodMasterEnabled: lodMasterEnabled ?? this.lodMasterEnabled,
      lodStepBlocks: lodStepBlocks ?? this.lodStepBlocks,
      lodSampleBase: lodSampleBase ?? this.lodSampleBase,
      lodMaxChunks: lodMaxChunks ?? this.lodMaxChunks,
      fullBandChunks: fullBandChunks ?? this.fullBandChunks,
      lodBuildBudget: lodBuildBudget ?? this.lodBuildBudget,
      aoEnabled: aoEnabled ?? this.aoEnabled,
      shadowRender: shadowRender ?? this.shadowRender,
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
    this.lodFaceCount = 0,
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

  /// 远景 LOD 大方块发射的面数（R26lod 诊断：验证 LOD 开关/采样/最远距离生效）。
  final int lodFaceCount;

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

  /// 批量网格（R25 GPU 加速）：非贴图/贴图不透明面 / 水面，各按相机深度
  /// 分 8 桶（远→近）。逐桶提交 → 画家算法正确，消除透视/穿墙。
  /// 桶为空 = null。空帧（[empty]）全部为空，画家回退逐面绘制。
  /// R26r8：描边并入 plain 桶（与地形同批次深度排序），无独立 edge 桶。
  final List<VoxelMeshBatch?> opaquePlainBuckets;
  final List<VoxelMeshBatch?> opaqueTexturedBuckets;
  final List<VoxelMeshBatch?> waterBuckets;

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
  // cl30：allowMask 面级 LOD 迟滞。方位 dot 在阈值 0 / 0.5 / 0.866 附近抖动时
  // 不应反复切级 → 升档/降档用不同阈值形成死区（hysteresis），旋转时侧面面
  // 不 popping。_lodHysteresis 为死区半宽（rad 量级的 cos 差）。
  static const double _lodHysteresis = 0.08;
  // 升档阈值：dot 递增越过才升一级。
  static int _lodLevelUp(double d) {
    if (d > 0.866 + _lodHysteresis) return 3; // 0~30°：主面
    if (d > 0.5 + _lodHysteresis) return 2; // 30~60°：主+侧
    if (d > _lodHysteresis) return 1; // 60~90°：侧
    return 0; // 身后：无侧
  }

  // 降档阈值：dot 递减越过才降一级（与升档错开 → 死区）。
  static int _lodLevelDown(double d) {
    if (d > 0.866 - _lodHysteresis) return 3;
    if (d > 0.5 - _lodHysteresis) return 2;
    if (d > -_lodHysteresis) return 1;
    return 0;
  }

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
    // cl30：allowMask 面级 LOD 持久化缓存。传入则跨帧复用上次计算的侧面
    // 可见面 mask（带迟滞），消除旋转时侧面面随方位阈值突变导致的 popping；
    // 不传则每帧重算（旧行为）。view 层持有并跨 buildFrame 调用维护。
    Map<(int, int), int>? allowMaskCache,
    Map<(int, int), double>? allowMaskDotCache,
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
    // R26q：每桶逐面深度（1 个 double/面），固化前在桶内做远→近排序，
    // 消除「单桶内 chunk 迭代顺序错序」导致的滑窗内透视（8 桶只切深度段，
    // 段内仍须排序才正确）。
    final List<List<double>> plainDepthB = newBuckets();
    final List<List<double>> texDepthB = newBuckets();
    final List<List<double>> waterDepthB = newBuckets();
    const int kOutline = 0x4D000000; // 描边色：~30% 黑，ARGB
    const int kOutlineA = 0x4D; // 描边基础 alpha（淡出时按比例缩放）
    // R27②：描边距离「跟随视距 + 末段淡出」。
    // 原实现是硬编码 `kEdgeMaxDepth = 15.0` 的二值截断：描边在离玩家 15 格处
    // 整齐地一刀切消失，玩家于是看到一圈环绕自身的「近似立方圆」边界，且无论
    // 视距设 2/4/6/8 chunks 都纹丝不动（用户反馈「描边视距严重不符」）。
    // 修复 A：上限由 camera.far（= 视距，世界格）派生，与视距档位联动；夹到
    //         [16,72]——每面描边要额外生成 8 个三角形，是面数黑洞，用户也认可
    //         「再往上意义不大而且很卡」，故保留上限护栏。
    // 修复 B：末段 30% 距离把 alpha 线性淡到 0，硬边界环变成察觉不到的渐隐。
    final double kEdgeMaxDepth = (camera.far * 0.5).clamp(16.0, 72.0);
    final double kEdgeFadeStart = kEdgeMaxDepth * 0.7;
    final double kEdgeFadeSpan = kEdgeMaxDepth - kEdgeFadeStart;

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
      // R26r5：不建中间 cols 列表，直接算 4 个角颜色（顶点布局 0/1/2/0/2/3）。
      final int cA = ao == null ? c : _modulate(c, ao[0] * aoScale);
      final int cB = ao == null ? c : _modulate(c, ao[1] * aoScale);
      final int cC = ao == null ? c : _modulate(c, ao[2] * aoScale);
      final int cD = ao == null ? c : _modulate(c, ao[3] * aoScale);
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
          waterColB[bkt]
            ..add(cA)..add(cB)..add(cC)
            ..add(cA)..add(cC)..add(cD);
          waterDepthB[bkt].add(depth);
        } else {
          texPosB[bkt]
            ..add(x0)..add(y0)..add(x1)..add(y1)..add(x2)..add(y2)
            ..add(x0)..add(y0)..add(x2)..add(y2)..add(x3)..add(y3);
          texUVB[bkt]
            ..add(u0)..add(v0)..add(u1)..add(v1)..add(u2)..add(v2)
            ..add(u0)..add(v0)..add(u2)..add(v2)..add(u3)..add(v3);
          texColB[bkt]
            ..add(cA)..add(cB)..add(cC)
            ..add(cA)..add(cC)..add(cD);
          texDepthB[bkt].add(depth);
        }
      } else {
        plainPosB[bkt]
          ..add(x0)..add(y0)..add(x1)..add(y1)..add(x2)..add(y2)
          ..add(x0)..add(y0)..add(x2)..add(y2)..add(x3)..add(y3);
        plainColB[bkt]
          ..add(cA)..add(cB)..add(cC)
          ..add(cA)..add(cC)..add(cD);
        plainDepthB[bkt].add(depth);
      }
      // 描边：仅不透明面。每条边画成一条细长方块（2 三角形），
      // drawVertices 无 line 模式，故用细长方块近似（R25 描边诉求）。
      // R26b：按 depth 落桶，绘制时远→近，前面面的描边盖住后面面的描边。
      // R26f：距离衰减——深度 > 15 格不画描边（1.1px 细线远处不可见，
      // 但每面要生成 8 个三角形，是面数黑洞，近距画、远距省）。
      if (!translucentFace && depth < kEdgeMaxDepth) {
        const double hw = 1.1; // 描边半宽（px）
        // R27②：末段淡出——alpha 随深度线性衰减到 0，消除硬截断的可见边界环。
        int outlineCol = kOutline;
        if (depth > kEdgeFadeStart) {
          final double f =
              (1.0 - (depth - kEdgeFadeStart) / kEdgeFadeSpan).clamp(0.0, 1.0);
          final int a = (kOutlineA * f).round().clamp(0, 255);
          // 已淡到不可见：直接跳过，省掉 8 个无效三角形（面数护栏）。
          if (a <= 1) return;
          outlineCol = a << 24;
        }
        // R26r8：描边并入地形面批次（plain）一起按深度排序——描边深度取面深度
        // −ε，保证「描边画在自己的面上、被更近的面盖住」，根治「远描边盖近面
        // = 描到看不见的方块 / 描边 X-ray」（原独立 edge 桶同桶内后画导致）。
        final List<double> ebp = plainPosB[bkt];
        final List<int> ebc = plainColB[bkt];
        final double eDepth = depth - 0.001;
        for (int e = 0; e < 4; e++) {
          // R26l：只描「我能看见的轮廓边」——内部边（两侧面都朝相机）跳过。
          if (edgeMask != null && !edgeMask[e]) continue;
          // R26r5：直接按 xy 下标取角（x0..y3 位于 [0..7]），不建 ec 中间列表。
          final double ax = xy[e * 2], ay = xy[e * 2 + 1];
          final int ne = (e + 1) % 4;
          final double bx = xy[ne * 2], by = xy[ne * 2 + 1];
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
            ..add(outlineCol)..add(outlineCol)..add(outlineCol)
            ..add(outlineCol)..add(outlineCol)..add(outlineCol);
          plainDepthB[bkt].add(eDepth);
        }
      }
    }

    // S1：把近平面裁剪出的多边形（n∈{3,5}）扇三角化后并入批量缓冲。缓冲格式
    // 固定 6 顶点(2 三角形)/面 → 每个扇三角形作为「2 三角形」单元写入（重复一
    // 次，近平面薄片的双倍绘制不可辨）。薄片用均匀色、不描边（面积极小、贴眼
    // 平面，人眼不可辨）。与 pushFace 共用同一套分桶 / 颜色逻辑。
    void pushPolygon(
      Float32List xy,
      Float32List? uv,
      int n,
      int argb,
      int tint,
      bool translucent,
      double depth,
    ) {
      final int bkt = (depth / camera.far * 8).floor().clamp(0, 7);
      for (int t = 1; t < n - 1; t++) {
        final double ax = xy[0], ay = xy[1];
        final double bx = xy[t * 2], by = xy[t * 2 + 1];
        final double cx = xy[(t + 1) * 2], cy = xy[(t + 1) * 2 + 1];
        if (uv != null) {
          final double au = uv[0], av = uv[1];
          final double bu = uv[t * 2], bv = uv[t * 2 + 1];
          final double cu = uv[(t + 1) * 2], cv = uv[(t + 1) * 2 + 1];
          if (translucent) {
            final int c = (tint & 0x00FFFFFF) |
                ((kWaterAlpha * 255).round().clamp(0, 255) << 24);
            waterPosB[bkt]
              ..add(ax)..add(ay)..add(bx)..add(by)..add(cx)..add(cy)
              ..add(ax)..add(ay)..add(bx)..add(by)..add(cx)..add(cy);
            waterUVB[bkt]
              ..add(au)..add(av)..add(bu)..add(bv)..add(cu)..add(cv)
              ..add(au)..add(av)..add(bu)..add(bv)..add(cu)..add(cv);
            waterColB[bkt]
              ..add(c)..add(c)..add(c)..add(c)..add(c)..add(c);
            waterDepthB[bkt].add(depth);
          } else {
            texPosB[bkt]
              ..add(ax)..add(ay)..add(bx)..add(by)..add(cx)..add(cy)
              ..add(ax)..add(ay)..add(bx)..add(by)..add(cx)..add(cy);
            texUVB[bkt]
              ..add(au)..add(av)..add(bu)..add(bv)..add(cu)..add(cv)
              ..add(au)..add(av)..add(bu)..add(bv)..add(cu)..add(cv);
            texColB[bkt]
              ..add(tint)..add(tint)..add(tint)..add(tint)..add(tint)..add(tint);
            texDepthB[bkt].add(depth);
          }
        } else {
          plainPosB[bkt]
            ..add(ax)..add(ay)..add(bx)..add(by)..add(cx)..add(cy)
            ..add(ax)..add(ay)..add(bx)..add(by)..add(cx)..add(cy);
          plainColB[bkt]
            ..add(argb)..add(argb)..add(argb)..add(argb)..add(argb)..add(argb);
          plainDepthB[bkt].add(depth);
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
    // R29cull：水平前向取真实视线前向的水平分量（含俯仰），而非仅 yaw。
    // 旧实现 hFwd=sin/cos(yaw) → 水平分量恒为 1 → cullAzimuth 永远为真，
    // 俯视/仰视时仍按水平 yaw 方向楔形剔除 → 看不见脚下/头顶整片地面（用户
    // "从空中向下看不见脚下、各档只看到 1/6 格"）。改用 b.fwdX/b.fwdZ（=cos(pitch)
    // 量级）：接近垂直俯视时水平分量→0 → cullAzimuth 自动关闭 → 全方向地面
    // 正常渲染；平视时与旧 sin/cos(yaw) 等价，行为不变。
    final double hFwdX = b.fwdX;
    final double hFwdZ = b.fwdZ;
    final double aspect = viewport.width / viewport.height;
    final double halfFovX = camera.fullWidth
        ? camera.fov / 2
        : math.atan(math.tan(camera.fov / 2) * aspect);
    // R26n：面级粗剔除阈值放宽——只剔「明显在身后」（cos < -0.5 ≈ 视角外 120°），
    // 朝下/朝上俯视时侧面的面不再被误剔（用户「lz<0.1 太保守」反馈）。
    // 用户确认（性能优化）：**只保留视锥内 + 5° 余量的面**，其余全部丢弃。
    // R26skel-fix：keepDeg 修正为 `halfFovX + 5°`——旧式 `180°−2·halfFovX+5°`
    // 在广角（halfFovX > 55°，如 fov=110°+ 超宽屏 aspect≈2 → 70.7°）时反而
    // 收窄到 < 视锥半角（45°<70.7°），把**可见面**整片剔除（用户「广角剔除
    // 完全反了」）。手电筒自带宽锥剔除（flashlightHalfDeg=22°，见列级剔除），
    // 不依赖本阈值——本修正只让正常视角广角不再误剔。
    final double halfDeg =
        halfFovX * 180 / math.pi; // 水平半视场角（度）
    final double keepDeg =
        (halfDeg + 5).clamp(5.0, 178.0); // 保留半角 = 半视场角 + 5° 余量
    final double cosLimit = math.cos(keepDeg * math.pi / 180);
    // 视线水平分量长度（=cos(pitch)：平视≈1，接近垂直→0）。cullAzimuth 随之在
    // 俯视/仰视时自动关闭，避免楔形方位剔除误删脚下/头顶地面（R29cull）。
    final double horizLen = math.sqrt(hFwdX * hFwdX + hFwdZ * hFwdZ);
    final bool cullAzimuth = horizLen >= 0.3;
    // R26fl：手电筒光锥 cos 阈值（半角 → 边界黑化 + 锥外剔除）。
    final double cosHalfFlash =
        math.cos(config.flashlightHalfDeg * math.pi / 180);

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
    // 组织遍历。R26r13：远景改由 3×3/9×9 LOD 马赛克覆盖（见 _emitLodPass），
    // 全精度带（2 区块）内满精度、带外跳过全精度（省面数）；不再圆形剔除。
    const int cs = RenderConfig.chunkSize;
    final int vd = config.viewDistanceChunks;
    final int camChunkX = (b.eyeX / cs).floor();
    final int camChunkZ = (b.eyeZ / cs).floor();
    final double chunkVd = vd * cs.toDouble();
    // S3：眼周封闭检测。封闭时（室内/洞穴/地下）远景全在墙后 → 收窄满精度带
    // 到 3×3（kFullBand=1），并跳过远景 LOD（见下方 _emitLodPass 守卫）。
    final bool enclosed = _eyeEnclosed(world, b.eyeX, b.eyeY, b.eyeZ);
    // R26r14：全精度带 = 以相机所在区块为中心的**正方形**方阵（去掉圆形剔除）。
    // kFullBand=2 → 5×5 区块满精度，带外由 3×3/9×9 LOD 马赛克覆盖；
    // S3 封闭态临时收窄为 3×3（kFullBand=1）。
    final int kFullBand = math.min(config.fullBandChunks, enclosed ? 1 : 2);
    // R26r20·D2：遍历半径与「满精度带」解耦——视距(vd)只决定满精度带切换阈值，
    // 遍历半径至少覆盖 kFullBand 满精度方阵（低视距 vd<2 时正前方不再一刀切）。
    final int loopVd = math.max(vd, kFullBand);
    // R26r20·D2：S2 可见集洪泛半径与视距解耦——必须覆盖到渲染最远（maxDist），
    // 否则低视距下 LOD 外环被 visible 守卫整片剔除 → 正前方最远一刀切。
    final int floodVd = math.max(vd, (maxDist / cs).ceil() + 1);

    // S2：区块级连通 flood-fill 可见集（cave culling）。仅当相机区块几何已缓存
    // （稳态）才启用——加载期相机区块未建好时退化为全方阵遍历，避免黑屏。
    // 封闭空间 BFS 几步即停 → 渲染区块 25 → 1~4；露天铺满方阵 → 与现状一致。
    final Set<(int, int)> visible = (cache != null &&
            cache.visGet(camChunkX, camChunkZ) != null)
        ? _floodVisibleChunks(cache, camChunkX, camChunkZ, floodVd, b, proj, cs,
            world.maxY)
        : const <(int, int)>{};

    // R26i/R26r：起雾点。原取 LOD 起始距离；LOD 关闭后改为视距的 80%，
    // 使雾与渲染距离挂钩、不再依赖 LOD 设置。
    fogStart = math.max(1.0, chunkVd * 0.8);
    fogSpan = math.max(1.0, maxDist - fogStart);

    // R23s 区块几何缓存：每个 (cx,cz,lod) 的"occlusion 可见面"集合是相机无关的，
    // 只与地形有关 → 缓存后跨帧 / 相机平移复用，每帧省掉百万级 world.get +
    // isFaceHidden（邻居查询嵌套）。每帧仅对缓存面做 backFaceCull（用缓存法线）
    // + 投影 + 着色；方位 / 距离剔除改由 project 返回 null（相机后方）自然处理，
    // 比列级方位剔除更正确（并修复 R23k "只渲染一角" 隐患）。
    for (int cz = camChunkZ - loopVd; cz <= camChunkZ + loopVd; cz++) {
      for (int cx = camChunkX - loopVd; cx <= camChunkX + loopVd; cx++) {
        final int cx0 = cx * cs;
        final int cz0 = cz * cs;
        // S2：非空气连通可见集内的区块整块跳过（封死在墙后的区块不渲染）。
        // 加载期 visible 为空集 → 不守卫，退化为全方阵。
        if (visible.isNotEmpty && !visible.contains((cx, cz))) continue;
        final double ccx = cx0 + cs * 0.5 - b.eyeX;
        final double ccz = cz0 + cs * 0.5 - b.eyeZ;
        final double cdist = math.sqrt(ccx * ccx + ccz * ccz);
        // R26r14：正方形全精度带（去掉圆形剔除，用户「渲染视线内所有区块」）。
        final int dxc = (cx - camChunkX).abs();
        final int dzc = (cz - camChunkZ).abs();
        if (config.lodEnabled) {
          if (dxc > kFullBand || dzc > kFullBand) continue;
        } else if (cdist > chunkVd + cs * 0.75) {
          continue;
        }

        // R26n：视锥剔除——只剔除「完全在视角外」的区块（AABB 8 角视锥测试，
        // 任一角落在视锥内即保留，含俯仰；比逐面/中心点判断更精确、不会漏掉
        // 脚下与视角边缘的方块）。玩家所在区块永不剔除。俯瞰/2.5D 保持水平剔除。
        // R26r：frustumCull 关闭时整段跳过（用户要求排查透视时全保留）。
        // R26fl：手电筒模式——「完整视线方向」窄锥剔除（含俯仰）。区块中心
        // 与视线 3D 夹角 > 半角 → 整块跳过。顺带修复「俯视正下方渲染所有
        // 方块」bug（原 cullAzimuth 依赖水平分量，俯视时自动关闭 → 全渲染）。
        // R26fix：手电筒自带窄锥剔除（不再依赖 frustumCull 开关）——之前
        // frustumCull 关闭时手电筒只做面级黑化、无列级剔除 → 全量渲染像「剔除反了」。
        final bool flashlightCull = config.flashlight;
        if (flashlightCull) {
          final double ddx = ccx;
          // R26fix：区块垂直中心用世界实际中高（旧 cs*0.5=8 是把世界当 16 格高；
          // G6 后 maxY=128 → 垂心错位到地面附近 → 手电筒光锥上下颠倒/「剔除反」）。
          final double ddy = (world.maxY * 0.5) - b.eyeY;
          final double ddz = ccz;
          final double dlen = math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz);
          if (dlen > 1e-6) {
            final double cosA =
                (ddx * b.fwdX + ddy * b.fwdY + ddz * b.fwdZ) / dlen;
            if (cosA < cosHalfFlash) continue;
          }
        } else if (cullAzimuth && config.frustumCull) {
          if (camera.fullWidth) {
            final double dot = (ccx * hFwdX + ccz * hFwdZ) / cdist;
            final double chunkAng =
                math.atan(cs * 0.75 / math.max(1.0, cdist));
            if (dot < math.cos(halfFovX + chunkAng)) continue;
          } else {
            // R26r20：玩家所在区块（及其紧邻 3×3）**永不视锥剔除**——贴脸区块
            // 8 角常以极陡角度落视锥外、区块边界附近易误剔（用户「干脆不剔」）。
            // 其余区块仍走 S5 膨胀 AABB 判据（各向外扩 max(near,0.8) 合法通过）。
            final bool nearCam =
                (cx - camChunkX).abs() <= 1 && (cz - camChunkZ).abs() <= 1;
            if (!nearCam &&
                !_chunkInFrustum(b, proj, cx0, cz0, cs, world.maxY,
                    // cl30：视锥 inflate 由 0.8 → 1.0（宽容延展），边缘区块
                    // 留余量，节流复用旧帧时不丢脚下/视角边缘方块。
                    inflate: math.max(proj.near, 1.0))) {
              continue;
            }
          }
        }

        // R26i：按区块朝向减面（LOD 面数）。整个区块只算一次「视角→可见面」
        // 规则，应用到本区块全部侧面（忽略顶/底面，地面不消失）；距相机 <
        // lodStart 的近区块不裁剪（保留全部侧面，避免近处建筑"穿帮"）；俯瞰
        // /2.5D 关闭（需全图）。bit: 0:+X 1:-X 2:+Z 3:-Z。
        // cl30：传入 allowMask 持久化缓存时，用迟滞(hysteresis)复用上次 mask——
        // 仅当方位 dot 跨过阈值 ±margin 死区才切换，否则沿用旧 mask → 旋转时
        // 侧面面不再随 0.5/0.866 阈值突变 popping（正视「刷新不持久」）。
        int allowMask = 0xF;
        if (config.lodFaceCull && !camera.fullWidth && (dxc > kFullBand || dzc > kFullBand)) {
          // 视角前向水平分量 (hFwdX,hFwdZ) 与「指向区块中心」水平方向的点积
          // = cos(夹角)：正对=1，正侧=0，身后<0。
          final double dot = (ccx * hFwdX + ccz * hFwdZ) / cdist;
          int liveMask;
          if (dot <= 0) {
            liveMask = 0; // >90° 身后：0 个侧面（顶/底面仍保留）
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
              liveMask = 1 << sideAxis; // 60~90°：只画侧边面
            } else if (dot < 0.866) {
              liveMask = (1 << mainAxis) | (1 << sideAxis); // 30~60°：主+侧
            } else {
              liveMask = 1 << mainAxis; // 0~30°：只画主面
            }
          }
          if (allowMaskCache != null && allowMaskDotCache != null) {
            final int? prevMask = allowMaskCache[(cx, cz)];
            final double? prevDot = allowMaskDotCache[(cx, cz)];
            if (prevMask != null && prevDot != null) {
              final int prevLevel = _lodLevelUp(prevDot);
              // 新 dot 落在以 prevLevel 为稳定点的迟滞死区内（down/up 阈值
              // 夹住 prevLevel）→ 沿用旧 mask，消除阈值附近的面 popping。
              if (prevLevel >= _lodLevelDown(dot) &&
                  prevLevel <= _lodLevelUp(dot)) {
                liveMask = prevMask;
              }
            }
            allowMaskCache[(cx, cz)] = liveMask;
            allowMaskDotCache[(cx, cz)] = dot;
          }
          allowMask = liveMask;
        }

        // R26r13：远景合并取代旧稀疏采样 LOD——全精度带内恒 step=1 满精度，
        // 带外由 _emitLodPass 的 3×3/9×9 马赛克覆盖（不再采样抽稀、无空洞）。
        const int lod = 0;
        const int step = 1;
        const int off = 0;

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
            mesh = _buildChunkMesh(world, cx0, cz0, step, off, config, cache);
            cache.put(cx, cz, lod, mesh);
          }
        } else {
          mesh = _buildChunkMesh(world, cx0, cz0, step, off, config, cache);
        }
        columns += mesh.columns;

        // 统一投影：backFaceCull（相机相关）+ 水波 + 透视 + 着色。
        for (final CachedFace cf in mesh.faces) {
          // 背面剔除：法线与"眼→面中心"同向即背面（用缓存法线，省重算）。
          if (config.backFaceCull) {
            final double ccx2 = cf.bx + cf.nx * 0.5 - b.eyeX;
            final double ccy2 = cf.by + cf.ny * 0.5 - b.eyeY;
            final double ccz2 = cf.bz + cf.nz * 0.5 - b.eyeZ;
            // S4：背面剔除加 epsilon —— 眼贴墙时点积趋近 0，浮点噪声会让同一面
            // 在帧间抖动（墙面闪烁）。放宽到 -1e-4 消除过零抖动。
            if (ccx2 * cf.nx + ccy2 * cf.ny + ccz2 * cf.nz >= -1e-4) continue;
          }

          // 方位粗剔除（每帧，相机相关）：只保留相机朝向半锥内的面，
          // 跳过侧后方 / 边缘面——否则这类面深度趋近近平面，投影坐标爆表
          // （数万）且永不入屏，纯属浪费。cf.bx/bz 即列中心，等价原列级剔除。
          // R26r34：与「区块级视锥剔除」解耦——后者（config.frustumCull）曾误删
          // 可见区块导致黑块/幽灵方块，故保持关闭；本逐面剔除仅移除远处屏外
          // 面、不涉及整块删除，安全回收 FPS。
          if (cullAzimuth) {
            final double colX = cf.bx - b.eyeX;
            final double colZ = cf.bz - b.eyeZ;
            if (camera.fullWidth) {
              final double d2 = colX * colX + colZ * colZ;
              if (d2 > 9) {
                final double d = math.sqrt(d2);
                if ((colX * hFwdX + colZ * hFwdZ) / d < cosLimit) continue;
              }
            } else {
              // 3D 视锥：用含俯仰的视线前向，避免看脚下时误剔近处下方块。
              final double colY = cf.by - b.eyeY;
              final double d2 = colX * colX + colY * colY + colZ * colZ;
              if (d2 > 9) {
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

          // S1：近平面多边形裁剪投影（根治小空间穿墙）。贴脸墙面跨过眼平面时
          // 不再整面硬丢，而是 clip 出 3~5 边形薄片；n==4 走原逐角 AO/描边快
          // 路径，n!=4（薄片）走 pushPolygon（均匀色、无描边，面积极小不可辨）。
          final Float32List? tileUv = config.textureEnabled
              ? VoxelTextureAtlas.tileUV(cf.voxel.index)
              : null;
          final ClippedFace? clippedFace =
              VoxelCamera.projectFaceClipped(corners, tileUv, b, proj);
          if (clippedFace == null) continue;

          final double depth = clippedFace.depth;
          if (depth > camera.far) continue;

          final (int argb0, int tint) = _colorOf(
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
          int argb = argb0;
          // R26fl：手电筒边界黑化——按面中心与视线夹角衰减亮度（中心全亮，
          // 边界 → 黑），形成「手电筒光锥」滤镜；锥外已由列级剔除跳过。
          if (config.flashlight) {
            argb = _flashlightShade(argb0, cf.bx + cf.nx * 0.5,
                cf.by + cf.ny * 0.5, cf.bz + cf.nz * 0.5, b, cosHalfFlash);
          }
          // R26fx：太阳投影阴影——顶面被太阳方向相邻不透明方块遮挡 → 调暗。
          if (config.shadowRender && cf.face == BlockFace.top) {
            argb = _sunShadowShade(argb, world, cf.bx + cf.nx * 0.5,
                cf.by + cf.ny * 0.5, cf.bz + cf.nz * 0.5, sd.x, sd.z);
          }
          // R26fx：AO 开关——关闭时所有 ao 因子置 1（均匀亮度更省）。
          if (!config.aoEnabled && cf.ao != null) {
            cf.ao![0] = 1;
            cf.ao![1] = 1;
            cf.ao![2] = 1;
            cf.ao![3] = 1;
          }
          if (clippedFace.n == 4) {
            final RenderFace rf = RenderFace(
              xy: clippedFace.xy,
              argb: argb,
              depth: depth,
              voxel: cf.voxel,
              face: cf.face,
              uv: tileUv,
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
            pushFace(clippedFace.xy, tileUv, argb, tint,
                cf.voxel.isTransparent, depth, cf.ao, cf.tilt, edgeMask);
          } else {
            // 近平面薄片：均匀 AO 着色 + 无描边（贴眼平面、亚像素级，不可辨）。
            final double avgAo =
                (cf.ao[0] + cf.ao[1] + cf.ao[2] + cf.ao[3]) * 0.25 * cf.tilt;
            final int cMod = _modulate(argb, avgAo);
            final RenderFace rf = RenderFace(
              xy: clippedFace.xy,
              argb: cMod,
              depth: depth,
              voxel: cf.voxel,
              face: cf.face,
              uv: clippedFace.uv,
              tint: tint,
            );
            allFaces.add(rf);
            pushPolygon(clippedFace.xy, clippedFace.uv, clippedFace.n, cMod,
                tint, cf.voxel.isTransparent, depth);
          }
        }
      }
    }

    // R26r13：远景 LOD 马赛克带（3×3/9×9 区块合并、多数方块填充）——全方块
    // 渲染、不做视锥/方位剔除（远处单元极少，成本可忽略），配合全精度带
    // 形成「近处精细、远处物理马赛克」的层级；面数远低于全距离开满精度。
    // R26lod：LOD 面计数——包一层 pushFace 统计远景大方块发射面数（诊断/测试）。
    int lodFaceCount = 0;
    if (config.lodEnabled && !enclosed) {
      void lodPush(Float32List xy, Float32List? uv, int argb, int tint,
          bool trans, [double depth = 0]) {
        lodFaceCount++;
        pushFace(xy, uv, argb, tint, trans, depth);
      }

      _emitLodPass(
        allFaces,
        world,
        cache,
        config,
        b,
        proj,
        sky,
        fogStart,
        fogSpan,
        camera.far,
        maxDist,
        b.eyeX,
        b.eyeZ,
        camera.fullWidth,
        sunWeight,
        sd.x,
        sd.y,
        sd.z,
        lights,
        lodPush,
        visible.isEmpty ? null : visible,
      );
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
    // S3：封闭空间内天空不可见，跳过云层发射（避免室内绘出飘云）。
    if (!enclosed) {
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
    }

    final int collected = allFaces.length;

    // 画家算法：远 → 近（单桶，水/地形/实体统一）。
    // R23q：128 桶桶排序替代全量 sort——按相机深度分桶（桶内保序），O(n)。
    _bucketSortByDepth(allFaces, camera.far);

    // 面数预算：超限时丢最远的（视觉损失被雾掩盖）。
    // R23o：预算随视距放大——固定上限在视距大时会把近处面也裁掉，
    // 按区块数线性扩容。
    // P0(性能合集)：预算下限 = 全精度带(5×5 区块)列数 × 每列保守 3 面——
    // 保证低档脚下/近处满精度不裁。原 perf 档 6000 面 < 6400 列地表所需面数
    // → 脚下地面被 _trimFarthest 从最远裁掉 →「看不见脚下/只有几个方块」根因。
    final int fullBandCols =
        (2 * kFullBand + 1) * (2 * kFullBand + 1) * cs * cs;
    final int faceBudget = math.max(
      config.maxFaces *
          math.max(1, (config.viewDistanceChunks + 2) ~/ 3),
      fullBandCols * 3,
    );
    _trimFarthest(allFaces, faceBudget);

    // R25：把累积的批量缓冲固化为类型化数组（空则 null，画家回退逐面绘制）。
    // R26p-camera：地形面按深度 8 桶固化（远→近），与描边桶交错绘制。
    // R26q：固化前先在桶内按深度远→近排序——画家算法正确性的关键。
    // R26r2：面数预算——超预算从最远桶往前裁（跳过 region 头），近处满精度。
    // R26r5：排序直接写入目标类型化缓冲（每材质一次分配），固化用 sublistView
    // 零拷贝——消除每帧每桶的临时数组与 fromList 复制。
    List<VoxelMeshBatch?> buildBuckets(
      List<List<double>> posB,
      List<List<int>> colB, {
      List<List<double>>? uvB,
      required List<List<double>> depthB,
      required int budget,
    }) {
      // 统计每桶面数 + 总面数。
      final List<int> count = List<int>.filled(8, 0);
      int total = 0;
      for (int i = 0; i < 8; i++) {
        final int n = posB[i].length ~/ 12;
        count[i] = n;
        total += n;
      }
      if (total == 0) return List<VoxelMeshBatch?>.filled(8, null);
      // 每材质一次分配：目标类型化缓冲（面数×12 / 面数×6）。
      final Float32List dstPos = Float32List(total * 12);
      final Int32List dstCol = Int32List(total * 6);
      final Float32List? dstUv =
          uvB != null ? Float32List(total * 12) : null;
      // Pass 1：每桶排序写入 region（远→近），region 起点 = 前序桶面数累计。
      final List<int> start = List<int>.filled(8, 0);
      int offset = 0;
      for (int i = 0; i < 8; i++) {
        start[i] = offset;
        final int n = count[i];
        if (n > 0) {
          _sortFacesTo(posB[i], colB[i], uvB != null ? uvB[i] : null,
              depthB[i], dstPos, dstCol, dstUv, offset);
        }
        offset += n;
      }
      // Pass 2：面数预算——从最远桶(7)往前「跳过 region 头」最远的面
      //（这些面在雾区=视距 80% 之后，视觉不可见），近处永远满精度。
      if (total > budget) {
        for (int i = 7; i >= 0 && total > budget; i--) {
          final int n = count[i];
          if (n == 0) continue;
          final int drop = math.min(n, total - budget);
          start[i] += drop;
          count[i] -= drop;
          total -= drop;
        }
      }
      // Pass 3：固化。定长 8 元素数组（空桶 null），画家按绝对桶号 7→0 索引；
      // sublistView 零拷贝视图，直接交给 ui.Vertices.raw（raw 不复制数据）。
      final List<VoxelMeshBatch?> out = List<VoxelMeshBatch?>.filled(8, null);
      for (int i = 0; i < 8; i++) {
        final int n = count[i];
        if (n == 0) continue;
        final int s = start[i];
        out[i] = VoxelMeshBatch(
          positions: Float32List.sublistView(dstPos, s * 12, (s + n) * 12),
          colors: Int32List.sublistView(dstCol, s * 6, (s + n) * 6),
          uv: dstUv != null
              ? Float32List.sublistView(dstUv, s * 12, (s + n) * 12)
              : null,
        );
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
    // R26r8：描边已并入 plain 批次（见 pushFace），不再有独立 edge 桶。

    return VoxelFrame(
      sky: sky,
      opaque: allFaces,
      translucent: const <RenderFace>[],
      opaquePlainBuckets: opaquePlainBuckets,
      opaqueTexturedBuckets: opaqueTexturedBuckets,
      waterBuckets: waterBuckets,
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
      lodFaceCount: lodFaceCount,
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
    // R27 地形遮挡剔除（隐藏面）+ cl28 修正：水平侧面被更高邻列埋住 → 不可见。
    // 邻列地形顶 >= 本面 y → 该面藏在后坡/山体内，安全跳过（仅移除非可见面、
    // 不删整块，配合背面/方位剔除共同降面数）。
    // cl28 关键修正：此规则只在**地表带**生效。深处/洞穴壁的邻列地形顶远高于
    // 本 y（nTop>=y 恒成立），若仍据其删面，玩家挖下去/进洞会见到虚空缺面。
    // 故仅当本面距地表 ≤8 格时才按邻列地形顶剔除；深处（洞穴/矿道）一律保留。
    if (f.index >= 2 && f.index <= 5) {
      final int selfTop = w.terrainHeightAt(x, z);
      if (y >= selfTop - 8) {
        final int nTop = w.terrainHeightAt(
          x + _normalX(f).toInt(),
          z + _normalZ(f).toInt(),
        );
        if (nTop >= y) return true;
      }
    }
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

  /// 单桶内逐面深度排序（R26q 语义）+ R26r5 零分配化：把同一深度桶里的面按
  /// 相机深度从远到近排序，**直接写入调用方提供的目标类型化缓冲**（[dstPos]/
  /// [dstCol]/[dstUv] 从 [dstOffset] 面起），不再每桶新建 np/nc/nu 临时数组、
  /// 不再 clear/addAll 回写源列表——消除每帧 ~24 次排序分配与复制。
  ///
  /// [pos] 每面 12 个 double（6 顶点）；[col] 每面 6 个 int；[uv] 每面 12 个
  /// double（可空）；[depth] 每面 1 个 double。远（depth 大）在前 → 先画。
  static void _sortFacesTo(
    List<double> pos,
    List<int> col,
    List<double>? uv,
    List<double> depth,
    Float32List dstPos,
    Int32List dstCol,
    Float32List? dstUv,
    int dstOffset,
  ) {
    final int n = depth.length; // 面数
    if (n <= 0) return;
    final int posOff = dstOffset * 12;
    final int colOff = dstOffset * 6;
    if (n == 1) {
      dstPos.setRange(posOff, posOff + 12, pos, 0);
      dstCol.setRange(colOff, colOff + 6, col, 0);
      if (dstUv != null && uv != null) {
        dstUv.setRange(posOff, posOff + 12, uv, 0);
      }
      return;
    }
    final List<int> order = List<int>.generate(n, (int i) => i);
    order.sort((int a, int b) => depth[b].compareTo(depth[a]));
    for (int k = 0; k < n; k++) {
      final int s = order[k];
      dstPos.setRange(posOff + k * 12, posOff + k * 12 + 12, pos, s * 12);
      dstCol.setRange(colOff + k * 6, colOff + k * 6 + 6, col, s * 6);
      if (dstUv != null && uv != null) {
        dstUv.setRange(posOff + k * 12, posOff + k * 12 + 12, uv, s * 12);
      }
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
  /// R26fl：手电筒黑化——面中心方向与视线夹角 → 亮度因子（中心 1 → 边界 0.08）。
  static int _flashlightShade(int argb, double fx, double fy, double fz,
      ViewBasis b, double cosHalf) {
    final double dx = fx - b.eyeX, dy = fy - b.eyeY, dz = fz - b.eyeZ;
    final double len = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (len < 1e-6) return argb;
    final double cosA = (dx * b.fwdX + dy * b.fwdY + dz * b.fwdZ) / len;
    if (cosA < cosHalf) return _modulate(argb, 0.02);
    final double t = ((cosA - cosHalf) / (1 - cosHalf)).clamp(0.0, 1.0);
    return _modulate(argb, 0.08 + 0.92 * t);
  }

  /// R26fx：太阳投影阴影——沿太阳水平方向 1~2 格采样，若相邻列更高且有
  /// 不透明方块遮挡本顶面 → 调暗（0.72），形成太阳方向硬阴影。
  static int _sunShadowShade(int argb, VoxelWorld world, double fx, double fy,
      double fz, double sunX, double sunZ) {
    final double len = math.sqrt(sunX * sunX + sunZ * sunZ);
    if (len < 1e-4) return argb;
    final double dx = sunX / len, dz = sunZ / len;
    for (int d = 1; d <= 2; d++) {
      final int xi = (fx + dx * d).floor().clamp(0, world.sizeX - 1);
      final int zi = (fz + dz * d).floor().clamp(0, world.sizeZ - 1);
      final int yi = (fy - 1).floor().clamp(0, world.maxY - 1);
      if (world.get(xi, yi, zi).occludes) return _modulate(argb, 0.72);
    }
    return argb;
  }

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
    // G2（用户确认）：云高基准 100 格；随地形起伏，但变化**微小**（±1 格内）。
    // 原固定 64 平面；现按每胞下方地形高度映射到 [-1,1] 格偏移（地形 0~128 →
    // (h-64)/64 ∈ [-1,1]），高地上云略高、低地云略低，肉眼几乎无感但打破
    // 呆板的水平云面。
    const double cloudBaseY = 100.0;
    // R26p2：覆盖半径由云层区块视距驱动（区块数 × 16 格），默认 3 = 48 格；
    // 重定心→无限（相机移动时云场始终以玩家为中心、铺满视野）。
    final double half = cloudChunks * 16.0;
    const double cell = 7.0; // 云胞间距（密度/性能平衡点）
    // ③：原硬剔除（eyeY >= cloudBaseY-1 直接 return）→ 创造模式飞行越过云层高度
    // 时整片云消失（「云视距也消失了」根因）。改为「越过云层后随高度平滑淡出
    // （无极过渡）」，贴着云层 / 仰视仍可见；远高于云层（>8 格）才彻底不画
    // （避免俯瞰把云面糊成白/黄滤镜）。
    final double aboveClouds = b.eyeY - cloudBaseY;
    if (aboveClouds > 8.0) return;
    final double cloudFade =
        aboveClouds > 0 ? (1.0 - aboveClouds / 8.0).clamp(0.0, 1.0) : 1.0;
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
        // R26n：云改为**半透明**（α≈0.62，摄像机可透过）单顶面（非方块）；
        // ③：α 再乘 cloudFade——越过云层高度后随高度平滑淡出（无极过渡）。
        final double a = 0.62 * cloudFade;
        final int argb = Color.fromRGBO(
          (244 * bright).round(),
          (247 * bright).round(),
          (255 * bright).round(),
          a,
        ).toARGB32();
        // G2：云高随下方地形起伏（微小 ±1 格），打破水平云面呆板感。
        final int th = world.terrainHeightAt(wx.floor(), wz.floor());
        final double cloudY = cloudBaseY + ((th - 64) / 64.0).clamp(-1.0, 1.0);
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

    // R26r12：MC 官方标准比例（16px = 1 格）——头 8×8×8、躯干 8×12×4、
    // 四肢 4×12×4、总高 2.0 格。与 64×64 皮肤纹理的 UV 区域严格 1:1 对应，
    // 贴图不拉伸不变形；此前比例（腿 0.9×0.16、躯干 0.8×0.7、手臂悬 ±0.435）
    // 与皮肤 UV 对不上，贴上去难看。
    final double leg = 0.75 * s; // 腿高（12px）
    final double torsoTop = 1.5 * s; // 肩 / 躯干顶（12+12px）
    final double headTop = 2.0 * s; // 头顶（+8px）
    final double bw = 0.25 * s; // 躯干半宽（8px）
    final double bd = 0.125 * s; // 躯干半深（4px）
    final double hw = 0.25 * s; // 头半宽/半深（8px）
    final double lw = 0.125 * s; // 四肢半宽（4px）
    final double ld = 0.125 * s; // 四肢半深（4px）

    // R26r14：模型整体绕垂直轴 yaw=en.lookYaw 旋转（pivot=(px,pz)），使
    // 「身体跟随头部 / 头部跟随视线」——躯干+四肢随相机朝向。四肢再叠加 rotX 摆动。
    final double pyYaw = px; // yaw 支点 X = 实体中心
    final double pzYaw = pz; // yaw 支点 Z = 实体中心
    // 双腿（R26r11：走路摇摆，绕髋支点 py+leg 前后摆动，交叉步态）。
    // swingPivotZ = 髋部经 yaw 旋转后的实际 Z，使腿绕**真髋点**摆动而非
    // 模型中心；否则侧身时腿会绕错轴小幅外飘（与躯干脱离）。
    // R26skel：旋转后髋 Z = pz - dx·sin(yawA) = pz + dx·sin(rotYaw)（yawA=-rotYaw）。
    // legL 髋 dx=-0.25 → +0.25·sin；legR dx=+0.25 → -0.25·sin（左右对称）。
    _emitBox(target, px - lw * 2, py, pz - ld, px, py + leg, pz + ld,
        limb, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'legL' : null,
        rotYaw: en.lookYaw, pivotX: pyYaw, pivotZ: pzYaw,
        rotX: -en.swing, pivotY: py + leg,
        swingPivotZ: pzYaw + 0.25 * math.sin(en.lookYaw));
    _emitBox(target, px, py, pz - ld, px + lw * 2, py + leg, pz + ld,
        limb, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'legR' : null,
        rotYaw: en.lookYaw, pivotX: pyYaw, pivotZ: pzYaw,
        rotX: en.swing, pivotY: py + leg,
        swingPivotZ: pzYaw - 0.25 * math.sin(en.lookYaw));
    // 躯干（8×12×4）—— 居中，swingPivot 与 yaw pivot 同点。
    _emitBox(target, px - bw, py + leg, pz - bd, px + bw, py + torsoTop,
        pz + bd, body, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'torso' : null,
        rotYaw: en.lookYaw, pivotX: pyYaw, pivotZ: pzYaw,
        swingPivotZ: pzYaw);
    // 头（8×8×8）：额外绕头部中心 X 轴倾斜跟随视线俯仰。
    // 旋转角 = -lookPitch：相机 pitch<0=俯视，头的正面对应朝下；
    // rotX=+pitch 会让头反过来倾斜（看地抬头、看天低头）。
    _emitBox(target, px - hw, py + torsoTop, pz - hw, px + hw, py + headTop,
        pz + hw, head, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'head' : null,
        rotYaw: en.lookYaw, pivotX: pyYaw, pivotZ: pzYaw,
        rotX: -en.lookPitch, pivotY: py + (torsoTop + headTop) * 0.5,
        swingPivotZ: pzYaw);
    // 双臂（R26r11：走路摇摆，绕肩支点 py+torsoTop 前后摆动，与腿交叉；
    // swingPivotZ 用旋转后的肩部 Z，与腿同处理）。
    // R26skel：armL 肩 dx=-0.375 → +0.375·sin；armR dx=+0.375 → -0.375·sin。
    _emitBox(target, px - lw * 4, py + leg, pz - ld, px - lw * 2, py + torsoTop,
        pz + ld, limb, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'armL' : null,
        rotYaw: en.lookYaw, pivotX: pyYaw, pivotZ: pzYaw,
        rotX: en.swing, pivotY: py + torsoTop,
        swingPivotZ: pzYaw + 0.375 * math.sin(en.lookYaw));
    _emitBox(target, px + lw * 2, py + leg, pz - ld, px + lw * 4, py + torsoTop,
        pz + ld, limb, alpha, sky, config, fogStart, fogSpan, far, b, proj, vmat,
        pushFace: pushFace, skinPart: skin ? 'armR' : null,
        rotYaw: en.lookYaw, pivotX: pyYaw, pivotZ: pzYaw,
        rotX: -en.swing, pivotY: py + torsoTop,
        swingPivotZ: pzYaw - 0.375 * math.sin(en.lookYaw));
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
    double rotX = 0, // R26r11：绕 X 轴摆动角（走路）
    double rotYaw = 0, // R26r14：绕垂直轴（Y）朝向（模型整体 lookYaw）
    double pivotX = 0, // R26r14：yaw 旋转支点 X（实体中心 x）
    double pivotY = 0,
    double pivotZ = 0,
    // R26skel：摆动（绕 X 轴）支点 Z。yaw 后肢体的髋/肩已偏离模型中心，
    // 必须用旋转后的实际 Z 作摆动轴心，否则侧身时腿/臂绕错轴、与躯干脱开。
    // 默认 = pivotZ（地形块 rotYaw=0 时无差别）。
    double swingPivotZ = 0,
  }) {
    // R26r14：先绕垂直轴（Y）作 yaw 朝向旋转（模型整体 lookYaw），再绕支点
    // (pivotY,swingPivotZ) 旋转 Y/Z（X 不变）做四肢摆动（R26r11）。
    // R26skel：yawA = -rotYaw 使模型正面 +Z 对齐相机视线方向（之前用
    // π-rotYaw 反向——让模型朝相机转，导致第三人称月亮步：背对移动方向，
    // 一直把脸对着相机；yaw=0 时又因 rotYaw==0 守卫不旋转形成 0/非 0 跳变）。
    final double yawA = -rotYaw;
    final double cosY = math.cos(yawA);
    final double sinY = math.sin(yawA);
    final double cosR = math.cos(rotX);
    final double sinR = math.sin(rotX);
    // 对任一点 (x,y,z) 依次做：①绕 (pivotX,pivotZ) 垂直轴 yaw ②绕
    // (pivotY, swingPivotZ) X 轴摆动。
    List<double> _rot(double x, double y, double z) {
      final double x1 =
          rotYaw == 0 ? x : pivotX + (x - pivotX) * cosY - (z - pivotZ) * sinY;
      final double z1 =
          rotYaw == 0 ? z : pivotZ + (x - pivotX) * sinY + (z - pivotZ) * cosY;
      final double y2 = rotX == 0
          ? y
          : pivotY + (y - pivotY) * cosR - (z1 - swingPivotZ) * sinR;
      final double z2 = rotX == 0
          ? z1
          : swingPivotZ + (y - pivotY) * sinR + (z1 - swingPivotZ) * cosR;
      return <double>[x1, y2, z2];
    }
    // 实体取包围盒中心做点光采样（体积小，逐面精算没有收益）。
    final double cxm = (x0 + x1) * 0.5;
    final double cym = (y0 + y1) * 0.5;
    final double czm = (z0 + z1) * 0.5;
    // 八个角（yaw + 摆动后的世界坐标）。
    final List<List<double>> C = <List<double>>[
      _rot(x0, y0, z0), _rot(x1, y0, z0), _rot(x1, y0, z1), _rot(x0, y0, z1),
      _rot(x0, y1, z0), _rot(x1, y1, z0), _rot(x1, y1, z1), _rot(x0, y1, z1),
    ];
    // 六面顶点（环绕顺序 0-1-2-3：top/bottom/north/south/west/east）。
    final List<List<double>> quads = <List<double>>[
      <double>[...C[4], ...C[5], ...C[6], ...C[7]], // top
      <double>[...C[0], ...C[1], ...C[2], ...C[3]], // bottom
      <double>[...C[0], ...C[1], ...C[5], ...C[4]], // north
      <double>[...C[3], ...C[2], ...C[6], ...C[7]], // south
      <double>[...C[0], ...C[3], ...C[7], ...C[4]], // west
      <double>[...C[1], ...C[2], ...C[6], ...C[5]], // east
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
    int maxY, {
    double inflate = 0,
  }) {
    // 由投影参数反推视锥半角正切：tanHalfX = halfW / scaleX，tanHalfY = halfH / scaleY。
    final double tanX = p.halfW / p.scaleX;
    final double tanY = p.halfH / p.scaleY;
    // S5：inflation 各向外扩 AABB（贴脸区块以极陡角度落视锥外时凭判据合法通过）。
    final double xMin = x0 - inflate;
    final double xMax = x0 + cs + inflate;
    final double yMin = -inflate;
    final double yMax = maxY + inflate;
    final double zMin = z0 - inflate;
    final double zMax = z0 + cs + inflate;
    for (int i = 0; i < 8; i++) {
      final double wx = (i & 1) == 0 ? xMin : xMax;
      final double wy = (i & 2) == 0 ? yMin : yMax;
      final double wz = (i & 4) == 0 ? zMin : zMax;
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

  /// S3：眼睛是否被实心封闭——10 向射线（6 轴向 + 4 水平对角），每向最多
  /// [maxStep] 格；**全部命中 `occludes` 才判封闭**。成本 ≈ 数十次 `world.get`
  /// /帧，完全可忽略。误判（射线全被挡但仍有缝漏光）只影响远景 LOD，近景满
  /// 精度带仍在 → 安全。
  static bool _eyeEnclosed(
    VoxelWorld w,
    double ex,
    double ey,
    double ez, {
    int maxStep = 6,
  }) {
    // 单位方向向量：±X ±Y ±Z + 4 条水平对角（45°）。
    const List<(double, double, double)> dirs = <(double, double, double)>[
      (1, 0, 0),
      (-1, 0, 0),
      (0, 1, 0),
      (0, -1, 0),
      (0, 0, 1),
      (0, 0, -1),
      (0.70710678, 0, 0.70710678),
      (-0.70710678, 0, 0.70710678),
      (0.70710678, 0, -0.70710678),
      (-0.70710678, 0, -0.70710678),
    ];
    for (final (double dx, double dy, double dz) in dirs) {
      bool blocked = false;
      for (int i = 1; i <= maxStep; i++) {
        final double d = i.toDouble();
        final Voxel v = w.get(
          (ex + dx * d).floor(),
          (ey + dy * d).floor(),
          (ez + dz * d).floor(),
        );
        if (v.occludes) {
          blocked = true;
          break;
        }
      }
      if (!blocked) return false; // 有一向透风 → 不封闭
    }
    return true;
  }

  /// S2：从相机区块出发 BFS，只经「空气连通面」扩散，返回可见区块集
  /// （key = (cx,cz)）。仅用**已缓存**的 [ChunkVisibility]；未缓存区块保守视为
  /// 可见（加入集合但不扩散），避免加载期黑屏。相机区块恒可见、全向扩散。
  ///
  /// 出队规则：相机区块 `enterFace=6`(ALL) 全向；其余只向 `connMask` 连通的
  /// 出口面扩散；出口 `faceOpen` 为 0 → 不扩散（封死）；邻块需过视锥 + 距离上限。
  static Set<(int, int)> _floodVisibleChunks(
    VoxelChunkCache? cache,
    int camChunkX,
    int camChunkZ,
    int vd,
    ViewBasis b,
    ProjectionParams p,
    int cs,
    int maxY,
  ) {
    final Set<(int, int)> visible = <(int, int)>{};
    // 队列元素：(cx, cz, enterFace)。enterFace=6 表相机区块（ALL）。
    final List<(int, int, int)> queue = <(int, int, int)>[
      (camChunkX, camChunkZ, 6)
    ];
    visible.add((camChunkX, camChunkZ));
    // 4 水平邻块偏移 + 对应出口 face bit（0:+X 1:-X 4:+Z 5:-Z）。
    const List<(int, int, int)> nb = <(int, int, int)>[
      (1, 0, 0), // +X
      (-1, 0, 1), // -X
      (0, 1, 4), // +Z
      (0, -1, 5), // -Z
    ];
    while (queue.isNotEmpty) {
      final (int cx, int cz, int enterFace) = queue.removeLast();
      final ChunkVisibility? vis = cache?.visGet(cx, cz);
      if (vis == null) continue; // 未缓存：本块已入集，不扩散（等下帧）
      for (final (int ddx, int ddz, int ef) in nb) {
        if ((vis.faceOpen & (1 << ef)) == 0) continue; // 该面封死
        if (enterFace != 6) {
          final int lo = enterFace < ef ? enterFace : ef;
          final int hi = enterFace + ef - lo;
          if ((vis.connMask & (1 << _pairBit(lo, hi))) == 0) continue;
        }
        final int ncx = cx + ddx;
        final int ncz = cz + ddz;
        if ((ncx - camChunkX).abs() > vd || (ncz - camChunkZ).abs() > vd) {
          continue; // 超视距方阵
        }
        final (int, int) nkey = (ncx, ncz);
        if (visible.contains(nkey)) continue;
        // 视锥剔除：邻块 AABB 在视锥外则不扩散（保守：只多不少）。
        if (!_chunkInFrustum(b, p, ncx * cs, ncz * cs, cs, maxY)) continue;
        visible.add(nkey);
        queue.add((ncx, ncz, ef));
      }
    }
    return visible;
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
    VoxelChunkCache? cache,
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
        // cl28 地下渲染：覆盖整列（y=0 到地表 + 树冠缓冲），挖下去不再见虚空。
        // 此前只遍历地表 ±6~10 格 → 地下深处未建网格，下挖即见虚空。
        final int yStart = 0;
        final int yEnd = (hBase + 12).clamp(0, world.maxY - 1);
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
    // S2：空气连通性（cave culling 用）。无缓存时跳过构建（避免每帧全高度扫描）。
    final ChunkVisibility vis = cache != null
        ? _buildChunkVisibility(world, cx0, cz0, cs, world.maxY)
        : const ChunkVisibility(0, 0);
    return ChunkMesh(faces, columns, vis);
  }

  /// S2：无序面对 {a,b}(a<b, 0:+X 1:-X 2:+Y 3:-Y 4:+Z 5:-Z) 在 15 bit
  /// connMask 中的 bit 索引 = C(6,2) 的字典序位置。
  static int _pairBit(int a, int b) => a * (11 - a) ~/ 2 + (b - a - 1);

  /// S2：全高度空气连通性扫描 → [ChunkVisibility]。相机无关，随 chunk 几何
  /// 缓存复用（一次构建）。对区块内空气格跑并查集求连通分量，记录每个分量
  /// 触及的边界面 → 同分量内任意两面互相置位 connMask。复杂度 O(cs²·maxY)，
  /// 已缓存，仅首建付费（maxY=256 → 每区块 65536 格，一次性）。
  static ChunkVisibility _buildChunkVisibility(
    VoxelWorld w,
    int cx0,
    int cz0,
    int cs,
    int maxY,
  ) {
    final int sx = cs, sz = cs, sy = maxY;
    final int n = sx * sy * sz;
    // 空气格标记（含水：transparent → occludes=false → 视为可穿视空气）。
    final Uint8List air = Uint8List(n);
    for (int lx = 0; lx < sx; lx++) {
      for (int lz = 0; lz < sz; lz++) {
        for (int ly = 0; ly < sy; ly++) {
          if (!w.get(cx0 + lx, ly, cz0 + lz).occludes) {
            air[(ly * sz + lz) * sx + lx] = 1;
          }
        }
      }
    }
    // 并查集（路径压缩）。
    final Int32List parent = Int32List(n);
    for (int i = 0; i < n; i++) {
      parent[i] = i;
    }
    int find(int a) {
      while (parent[a] != a) {
        parent[a] = parent[parent[a]];
        a = parent[a];
      }
      return a;
    }

    void union(int a, int b) {
      final int ra = find(a);
      final int rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    // 边界面 bit：0:+X 1:-X 2:+Y 3:-Y 4:+Z 5:-Z。
    final Int32List faceBits = Int32List(n);
    for (int lx = 0; lx < sx; lx++) {
      for (int lz = 0; lz < sz; lz++) {
        for (int ly = 0; ly < sy; ly++) {
          final int idx = (ly * sz + lz) * sx + lx;
          if (air[idx] == 0) continue;
          int f = 0;
          if (lx == sx - 1) f |= 1 << 0; // +X
          if (lx == 0) f |= 1 << 1; // -X
          if (ly == sy - 1) f |= 1 << 2; // +Y
          if (ly == 0) f |= 1 << 3; // -Y
          if (lz == sz - 1) f |= 1 << 4; // +Z
          if (lz == 0) f |= 1 << 5; // -Z
          if (f != 0) faceBits[idx] = f;
          // 6 邻并查集（仅前向，避免重复）。
          if (lx + 1 < sx && air[idx + 1] != 0) {
            union(idx, idx + 1);
          }
          if (lz + 1 < sz && air[idx + sx] != 0) {
            union(idx + sx, idx);
          }
          if (ly + 1 < sy && air[idx + sx * sz] != 0) {
            union(idx + sx * sz, idx);
          }
        }
      }
    }
    // 汇总：边界格归并到根。
    for (int i = 0; i < n; i++) {
      if (faceBits[i] == 0) continue;
      faceBits[find(i)] |= faceBits[i];
    }
    // 每个根分量 → faceOpen + connMask。
    int faceOpen = 0;
    int connMask = 0;
    for (int i = 0; i < n; i++) {
      if (faceBits[i] == 0 || parent[i] != i) continue; // 只处理根
      final int fs = faceBits[i];
      faceOpen |= fs;
      for (int a = 0; a < 6; a++) {
        if ((fs & (1 << a)) == 0) continue;
        for (int bb = a + 1; bb < 6; bb++) {
          if ((fs & (1 << bb)) == 0) continue;
          connMask |= 1 << _pairBit(a, bb);
        }
      }
    }
    return ChunkVisibility(faceOpen, connMask);
  }

  // ═══════════════════ R26r13：远景 LOD 马赛克（3×3 / 9×9 区块合并）═══════════════════

  /// 返回 (x,z) 列最高的**非空**方块顶面 y（世界坐标；0 = 全空气）。
  /// 含水面——海洋顶部显示水面而非海床。越界钳制（世界边缘列重复采样）。
  static double _topNonAirAt(VoxelWorld world, double x, double z) {
    final int xi = x.floor().clamp(0, world.sizeX - 1);
    final int zi = z.floor().clamp(0, world.sizeZ - 1);
    for (int y = world.maxY - 1; y >= 0; y--) {
      if (!world.get(xi, y, zi).isEmpty) return y + 1.0;
    }
    return 0;
  }

  /// R26r20：构建一个 LOD 马赛克单元（相机无关 → 缓存）——DH 风格逐列立方体数据。
  /// 恒定列宽 [step]=2 采样 (g+2)² 网格（含外环 1 格）：内 g×g = 每列顶高 hGrid +
  /// 顶部方块 vGrid + 侧方块 vSide（顶下 1 格：草地顶绿侧棕）；外环 hPad 提供
  /// 边界列 4 邻高度 → 逐列发顶面 + 暴露侧面（块状剪影、侧壁实心、多色）。
  /// 成本 = O((size/2)²·maxY + 4·size/2) 列采样，一次性、缓存复用。
  static _LodCell _buildLodCell(
    VoxelWorld world,
    double cx0,
    double cz0,
    double size,
  ) {
    // R26lod：列宽随 cell 缩放（2 幂对齐：cell4→step2, 8→4, 16→8, 32→16），
    // 每单元恒定 2×2 列 → cell 越大总列数越少 = 大方块越粗越省面（采样参数真正
    // 生效，不再是恒定 2 格列采样）；2 幂对齐跨档共享采样格、无接缝（P5）。
    final double step = math.max(2.0, size / 2.0);
    final int g = math.max(1, (size / step).round()); // 每轴列数（恒定 2）
    final int gg = g * g;
    final int gp = g + 2; // 含外环
    final Float32List hGrid = Float32List(gg);
    final List<Voxel> vGrid = List<Voxel>.filled(gg, Voxel.stone);
    final List<Voxel> vSide = List<Voxel>.filled(gg, Voxel.stone);
    final Float32List hPad = Float32List(gp * gp);
    double topY = 0;
    final Map<Voxel, int> tally = <Voxel, int>{};
    for (int j = -1; j <= g; j++) {
      for (int i = -1; i <= g; i++) {
        final double x = cx0 + (i + 0.5) * step;
        final double z = cz0 + (j + 0.5) * step;
        final double t = _topNonAirAt(world, x, z);
        final int pi = i + 1, pj = j + 1;
        hPad[pj * gp + pi] = t;
        if (i < 0 || j < 0 || i >= g || j >= g) continue; // 外环仅填 hPad
        final int k = j * g + i;
        hGrid[k] = t;
        if (t > topY) topY = t;
        if (t > 0) {
          final int xi = x.floor().clamp(0, world.sizeX - 1);
          final int zi = z.floor().clamp(0, world.sizeZ - 1);
          final int yiTop = (t - 1).floor().clamp(0, world.maxY - 1);
          final Voxel vt = world.get(xi, yiTop, zi);
          vGrid[k] = vt;
          tally[vt] = (tally[vt] ?? 0) + 1;
          // 侧方块 = 顶下 1 格（草→土/石）；空则回退顶方块。
          final int yiSide = (t - 2).floor().clamp(0, world.maxY - 1);
          final Voxel vs = world.get(xi, yiSide, zi);
          vSide[k] = vs.isEmpty ? vt : vs;
        }
      }
    }
    // 多数方块（平坦快路径侧裙边 / 退路用；并列取先扫到的，确定性）。
    Voxel majority = Voxel.stone;
    int best = 0;
    tally.forEach((Voxel v, int c) {
      if (c > best) {
        best = c;
        majority = v;
      }
    });
    // 平坦判定：全部列等高且同色（平原 → 快路径单顶面+边界裙边，零开销）。
    bool flat = true;
    final double h0 = hGrid[0];
    final Voxel v0 = vGrid[0];
    for (int k = 1; k < gg; k++) {
      if (hGrid[k] != h0 || vGrid[k] != v0) {
        flat = false;
        break;
      }
    }
    return _LodCell(
      g: g,
      topY: topY,
      majority: majority,
      hGrid: hGrid,
      vGrid: vGrid,
      vSide: vSide,
      hPad: hPad,
      flat: flat,
    );
  }

  /// R26imp：地平线 Impostor——最外档（cell≥32）合成 flat 单元（复用
  /// _emitLodCell 的平坦快路径：单顶面 + 4 边界裙边 = 山形剪影）。
  /// 5×5 网格采样平均高度 + 多数方块色；外环取平均（邻单元无缝）。
  static _LodCell _buildHorizonImpostor(
    VoxelWorld world,
    double cx0,
    double cz0,
    double size,
  ) {
    const int S = 5;
    double sum = 0;
    int n = 0;
    final Map<Voxel, int> tally = <Voxel, int>{};
    for (int j = 0; j < S; j++) {
      for (int i = 0; i < S; i++) {
        final double x = cx0 + (i + 0.5) * size / S;
        final double z = cz0 + (j + 0.5) * size / S;
        final double t = _topNonAirAt(world, x, z);
        sum += t;
        n++;
        if (t > 0) {
          final int xi = x.floor().clamp(0, world.sizeX - 1);
          final int zi = z.floor().clamp(0, world.sizeZ - 1);
          final int yi = (t - 1).floor().clamp(0, world.maxY - 1);
          final Voxel v = world.get(xi, yi, zi);
          tally[v] = (tally[v] ?? 0) + 1;
        }
      }
    }
    if (n == 0) {
      return _LodCell(
        g: 1,
        topY: 0,
        majority: Voxel.stone,
        hGrid: Float32List.fromList(<double>[0]),
        vGrid: <Voxel>[Voxel.stone],
        vSide: <Voxel>[Voxel.stone],
        hPad: Float32List(9)..fillRange(0, 9, 0),
        flat: true,
      );
    }
    final double avg = sum / n;
    Voxel majority = Voxel.stone;
    int best = 0;
    tally.forEach((Voxel v, int c) {
      if (c > best) {
        best = c;
        majority = v;
      }
    });
    return _LodCell(
      g: 1,
      topY: avg,
      majority: majority,
      hGrid: Float32List.fromList(<double>[avg]),
      vGrid: <Voxel>[majority],
      vSide: <Voxel>[majority],
      hPad: Float32List(9)..fillRange(0, 9, avg), // 外环平均 → 邻单元无缝
      flat: true,
    );
  }

  /// 遍历远景 LOD 马赛克带并发射。R26r18·P1/P3：以最细基础格（cell=4）遍历，
  /// 每基础格按距相机距离选「coarsest-matching」档（= 含该距离、cell 最大的档），
  /// 映射到对齐粗格发射——无缝、无重叠、跨档高度一致（恒定采样步长，P5 无接缝）。
  /// P3 区块级视锥剔除（FP/TP 下远景面数约减半）。迟滞（1.15× 升 / 0.87× 降）防移动闪烁。
  static void _emitLodPass(
    List<RenderFace> allFaces,
    VoxelWorld world,
    VoxelChunkCache? cache,
    RenderConfig config,
    ViewBasis b,
    ProjectionParams proj,
    SkyPalette sky,
    double fogStart,
    double fogSpan,
    double far,
    double maxDist,
    double eyeX,
    double eyeZ,
    bool fullWidth,
    double sunWeight,
    double sunX,
    double sunY,
    double sunZ,
    List<PointLight> lights,
    void Function(Float32List, Float32List?, int, int, bool, [double]) pushFace,
    Set<(int, int)>? visible,
  ) {
    final List<_LodTier> tiers = _lodTiers(config);
    if (tiers.isEmpty) return; // LOD 关闭：无远景大方块
    const double baseCell = 4.0;
    // R26lod：LOD 视距独立于基础视距——遍历半径 = lodMaxChunks×16（可更大）。
    final double lodMaxDist =
        config.lodMaxChunks * RenderConfig.chunkSize.toDouble();
    final double effMax = math.max(lodMaxDist, maxDist);
    final int c0 = ((eyeX - effMax) / baseCell).floor();
    final int c1 = ((eyeX + effMax) / baseCell).floor();
    final int d0 = ((eyeZ - effMax) / baseCell).floor();
    final int d1 = ((eyeZ + effMax) / baseCell).floor();
    int built = 0; // 分帧：每帧最多建若干单元（远处渐进出现，避免首帧卡顿）
    final int budget = config.lodBuildBudget;
    for (int bi = c0; bi <= c1; bi++) {
      for (int bj = d0; bj <= d1; bj++) {
        final double cx0 = bi * baseCell;
        final double cz0 = bj * baseCell;
        final double ccx = cx0 + baseCell * 0.5 - eyeX;
        final double ccz = cz0 + baseCell * 0.5 - eyeZ;
        final double cdist = math.sqrt(ccx * ccx + ccz * ccz);
        // 内圈满精度带内不走 LOD（由 buildFrame 满精度正方形方阵覆盖）。
        if (cdist <= tiers.first.ring0) continue;
        // coarsest-matching：取 ring1 >= cdist 的最小档（cell 最大、最省面）。
        int desired = tiers.length - 1;
        for (int t = 0; t < tiers.length; t++) {
          if (cdist < tiers[t].ring1) {
            desired = t;
            break;
          }
        }
        // P1 迟滞：沿用旧档，除非越过 1.15× 升档 / 0.87× 降档边界（防移动闪烁）。
        final int prev = cache?.lodTierGet(bi, bj) ?? desired;
        int tier;
        if (desired > prev && cdist > tiers[prev].ring1 * 1.15) {
          tier = desired;
        } else if (desired < prev && cdist < tiers[prev].ring0 * 0.87) {
          tier = desired;
        } else {
          tier = prev;
        }
        cache?.lodTierPut(bi, bj, tier);
        final _LodTier T = tiers[tier];
        // 把基础格对齐到本档网格；仅当本基础格是该粗格锚点才发射（去重，每粗格一次）。
        final int gci = (bi * baseCell / T.cell).round();
        final int gcj = (bj * baseCell / T.cell).round();
        final double gx0 = gci * T.cell;
        final double gz0 = gcj * T.cell;
        if ((cx0 - gx0).abs() > 1e-6 || (cz0 - gz0).abs() > 1e-6) continue;
        // S2：远景 LOD 单元仅当其中心区块在可见集内才发射（封死墙后的远景不渲染）。
        if (visible != null) {
          final int chCx = (gx0 / RenderConfig.chunkSize).floor();
          final int chCz = (gz0 / RenderConfig.chunkSize).floor();
          if (!visible.contains((chCx, chCz))) continue;
        }
        // P3：区块级视锥剔除（FP/TP 下丢弃 camera 后半球粗格，面数约减半）。
        // R26r20：与全精度同规则——相机区块及紧邻 3×3 永不剔除（防御性；该邻域
        // 常规已由 kFullBand 满精度带覆盖，这里保证任何配置下近相机粗格不消失）。
        if (config.lodFrustumCull && !fullWidth) {
          final int cellCx = (gx0 / RenderConfig.chunkSize).floor();
          final int cellCz = (gz0 / RenderConfig.chunkSize).floor();
          final int camCx = (b.eyeX / RenderConfig.chunkSize).floor();
          final int camCz = (b.eyeZ / RenderConfig.chunkSize).floor();
          final bool nearCam =
              (cellCx - camCx).abs() <= 1 && (cellCz - camCz).abs() <= 1;
          if (!nearCam &&
              !_cellInFrustum(b, proj, gx0, gz0, T.cell, world.maxY.toDouble())) {
            continue;
          }
        }
        // ⑤：向下看平行面剔除——相机俯视（fwdY 明显朝下）时，剔除远处「脚下地面」
        // 粗格（中心远低于视线且距相机较远），降低俯视时的远景面数（开放世界方案）。
        // 近处 / 紧贴相机保留，避免脚下出现空洞。概率生效、不伤正确性。
        if (b.fwdY < -0.6) {
          final double tH = world
              .terrainHeightAt(
                (gx0 + T.cell / 2).round(),
                (gz0 + T.cell / 2).round(),
              )
              .toDouble();
          if ((b.eyeY - tH) > 20 && cdist > 48) continue;
        }
        _LodCell? cell = cache?.lodCellGet(tier, gci, gcj);
        if (cell == null) {
          if (built >= budget) continue; // 本帧预算用完 → 下帧补建
          built++;
          // R26imp：地平线 Impostor——最外档（cell≥32）不再细分列，直接合成
          // 「平均高度 + 多数色」的 flat 大平面（2 交叉山形剪影由顶面+裙边
          // 呈现），远景面数从「列数」降到「单元数」，贴天边极省。
          cell = T.cell >= 32
              ? _buildHorizonImpostor(world, gx0, gz0, T.cell)
              : _buildLodCell(world, gx0, gz0, T.cell);
          cache?.lodCellPut(tier, gci, gcj, cell);
        }
        _emitLodCell(allFaces, cell, gx0, gz0, T.cell, b, proj, sky, config,
            fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights,
            pushFace);
      }
    }
  }

  /// R26r20：发射一个 LOD 马赛克单元——DH 风格逐列立方体。
  /// 平坦快路径：单顶面 + 4 边界裙边（平原零开销）。
  /// 逐列路径：顶面按「同行同高同色」RLE 合并（平原大幅省面），暴露侧面按列发
  /// （邻列/外环更低才露，法线指向较低侧）→ 块状剪影、侧壁实心、多色、云上无
  /// 漂浮平板。geomorph：displayH 每帧朝 hGrid lerp（邻列同步缓动，不撕裂）。
  static void _emitLodCell(
    List<RenderFace> allFaces,
    _LodCell cell,
    double cx0,
    double cz0,
    double size,
    ViewBasis b,
    ProjectionParams proj,
    SkyPalette sky,
    RenderConfig config,
    double fogStart,
    double fogSpan,
    double far,
    double sunWeight,
    double sunX,
    double sunY,
    double sunZ,
    List<PointLight> lights,
    void Function(Float32List, Float32List?, int, int, bool, [double]) pushFace,
  ) {
    if (cell.topY <= 0) return;
    final int g = cell.g;
    final int gp = g + 2;
    const double step = 2.0;

    // ── 平坦快路径：单顶面 + 4 边界裙边（语义同 R26r18 单顶单元）──
    if (cell.flat) {
      cell.displayH[0] += (cell.hGrid[0] - cell.displayH[0]) * 0.25;
      if ((cell.hGrid[0] - cell.displayH[0]).abs() < 0.01) {
        cell.displayH[0] = cell.hGrid[0];
      }
      final double yT = cell.displayH[0];
      final double x0 = cx0, z0 = cz0;
      final double x1 = cx0 + size, z1 = cz0 + size;
      _emitLodQuad(allFaces, Float64List.fromList(<double>[
        x0, yT, z0, x1, yT, z0, x1, yT, z1, x0, yT, z1,
      ]), 0, 1, 0, cell.vGrid[0], BlockFace.top, b, proj, sky, config,
          fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights, pushFace);
      // 边界裙边（外环最高侧；邻更低才露）。
      double nTop = 0, sTop = 0, wTop = 0, eTop = 0;
      for (int i = 0; i < g; i++) {
        final double nt = cell.hPad[i + 1];
        if (nt > nTop) nTop = nt;
        final double st = cell.hPad[(g + 1) * gp + i + 1];
        if (st > sTop) sTop = st;
        final double wt = cell.hPad[(i + 1) * gp];
        if (wt > wTop) wTop = wt;
        final double et = cell.hPad[(i + 1) * gp + g + 1];
        if (et > eTop) eTop = et;
      }
      if (nTop < yT) {
        _emitLodQuad(allFaces, Float64List.fromList(<double>[
          x0, nTop, z0, x1, nTop, z0, x1, yT, z0, x0, yT, z0,
        ]), 0, 0, -1, cell.majority, BlockFace.north, b, proj, sky, config,
            fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights, pushFace);
      }
      if (sTop < yT) {
        _emitLodQuad(allFaces, Float64List.fromList(<double>[
          x0, sTop, z1, x0, yT, z1, x1, yT, z1, x1, sTop, z1,
        ]), 0, 0, 1, cell.majority, BlockFace.south, b, proj, sky, config,
            fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights, pushFace);
      }
      if (wTop < yT) {
        _emitLodQuad(allFaces, Float64List.fromList(<double>[
          x0, wTop, z0, x0, yT, z0, x0, yT, z1, x0, wTop, z1,
        ]), -1, 0, 0, cell.majority, BlockFace.west, b, proj, sky, config,
            fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights, pushFace);
      }
      if (eTop < yT) {
        _emitLodQuad(allFaces, Float64List.fromList(<double>[
          x1, eTop, z0, x1, eTop, z1, x1, yT, z1, x1, yT, z0,
        ]), 1, 0, 0, cell.majority, BlockFace.east, b, proj, sky, config,
            fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights, pushFace);
      }
      return;
    }

    // ── 逐列路径：先整网格 geomorph lerp（邻列同步缓动，不撕裂）──
    final int gg = g * g;
    for (int k = 0; k < gg; k++) {
      cell.displayH[k] += (cell.hGrid[k] - cell.displayH[k]) * 0.25;
      if ((cell.hGrid[k] - cell.displayH[k]).abs() < 0.01) {
        cell.displayH[k] = cell.hGrid[k];
      }
    }
    for (int j = 0; j < g; j++) {
      int i = 0;
      while (i < g) {
        final int k = j * g + i;
        final double h = cell.displayH[k];
        if (h <= 0.001) {
          i++;
          continue;
        }
        final Voxel vTop = cell.vGrid[k];
        // 同行同高同色连续列 → RLE 合并顶面（平原大幅省面）。
        int i1 = i + 1;
        while (i1 < g &&
            cell.displayH[j * g + i1] == h &&
            cell.vGrid[j * g + i1] == vTop) {
          i1++;
        }
        final double cx = cx0 + i * step;
        final double cx2 = cx0 + i1 * step;
        final double cz = cz0 + j * step;
        final double cz2 = cz + step;
        _emitLodQuad(allFaces, Float64List.fromList(<double>[
          cx, h, cz, cx2, h, cz, cx2, h, cz2, cx, h, cz2,
        ]), 0, 1, 0, vTop, BlockFace.top, b, proj, sky, config,
            fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights, pushFace);
        // 侧面：每列独立（暴露处才发，法线指向较低侧）。
        for (int ci = i; ci < i1; ci++) {
          final int ck = j * g + ci;
          final Voxel vSide = cell.vSide[ck];
          final double ccx = cx0 + ci * step;
          final double ccx2 = ccx + step;
          // 西（邻列 i-1）
          final double hw = cell.hPad[(j + 1) * gp + ci];
          if (hw < h) {
            _emitLodQuad(allFaces, Float64List.fromList(<double>[
              ccx, hw, cz, ccx, h, cz, ccx, h, cz2, ccx, hw, cz2,
            ]), -1, 0, 0, vSide, BlockFace.west, b, proj, sky, config,
                fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights, pushFace);
          }
          // 东（邻列 i+1）
          final double he = cell.hPad[(j + 1) * gp + ci + 2];
          if (he < h) {
            _emitLodQuad(allFaces, Float64List.fromList(<double>[
              ccx2, he, cz, ccx2, he, cz2, ccx2, h, cz2, ccx2, h, cz,
            ]), 1, 0, 0, vSide, BlockFace.east, b, proj, sky, config,
                fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights, pushFace);
          }
          // 北（邻行 j-1）
          final double hn = cell.hPad[j * gp + ci + 1];
          if (hn < h) {
            _emitLodQuad(allFaces, Float64List.fromList(<double>[
              ccx, hn, cz, ccx2, hn, cz, ccx2, h, cz, ccx, h, cz,
            ]), 0, 0, -1, vSide, BlockFace.north, b, proj, sky, config,
                fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights, pushFace);
          }
          // 南（邻行 j+1）
          final double hs = cell.hPad[(j + 2) * gp + ci + 1];
          if (hs < h) {
            _emitLodQuad(allFaces, Float64List.fromList(<double>[
              ccx, hs, cz2, ccx, h, cz2, ccx2, h, cz2, ccx2, hs, cz2,
            ]), 0, 0, 1, vSide, BlockFace.south, b, proj, sky, config,
                fogStart, fogSpan, far, sunWeight, sunX, sunY, sunZ, lights, pushFace);
          }
        }
        i = i1;
      }
    }
  }

  /// 投影并发射单个 LOD 面（顶面或台阶）：背面剔除 + 地形着色 + 雾 +
  /// 并入统一画家桶（与全精度地形同深度排序，正确遮挡）。
  static void _emitLodQuad(
    List<RenderFace> allFaces,
    Float64List c,
    double nx,
    double ny,
    double nz,
    Voxel voxel,
    BlockFace face,
    ViewBasis b,
    ProjectionParams proj,
    SkyPalette sky,
    RenderConfig config,
    double fogStart,
    double fogSpan,
    double far,
    double sunWeight,
    double sunX,
    double sunY,
    double sunZ,
    List<PointLight> lights,
    void Function(Float32List, Float32List?, int, int, bool, [double]) pushFace,
  ) {
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
    // 背面剔除（法线朝外；眼在面内侧 → 剔除）
    if (config.backFaceCull) {
      final double mx = (c[0] + c[3] + c[6] + c[9]) * 0.25 - b.eyeX;
      final double my = (c[1] + c[4] + c[7] + c[10]) * 0.25 - b.eyeY;
      final double mz = (c[2] + c[5] + c[8] + c[11]) * 0.25 - b.eyeZ;
      // S4：背面剔除加 epsilon（见 S1 区块循环同款处理），消除贴墙闪烁。
      if (mx * nx + my * ny + mz * nz >= -1e-4) return;
    }
    final (int argb, int tint) = _colorOf(
      voxel: voxel,
      face: face,
      depth: depth,
      sky: sky,
      config: config,
      fogStart: fogStart,
      fogSpan: fogSpan,
      lights: lights,
      sunWeight: sunWeight,
      sunX: sunX,
      sunY: sunY,
      sunZ: sunZ,
      fx: (c[0] + c[3] + c[6] + c[9]) * 0.25,
      fy: (c[1] + c[4] + c[7] + c[10]) * 0.25,
      fz: (c[2] + c[5] + c[8] + c[11]) * 0.25,
    );
    final Float32List? uv =
        config.textureEnabled ? VoxelTextureAtlas.tileUV(voxel.index) : null;
    allFaces.add(RenderFace(
      xy: xy,
      argb: argb,
      depth: depth,
      voxel: voxel,
      face: face,
      uv: uv,
      tint: tint,
    ));
    pushFace(xy, uv, argb, tint, voxel.isTransparent, depth);
  }
}

/// P1·R26r18：单个 LOD 档（由相机距离推导 cell 尺寸 + 降级环）。
class _LodTier {
  const _LodTier(this.cell, this.ring0, this.ring1);
  /// 该档单元格边长（格）。
  final double cell;
  /// 该档内环半径（格，>= 此距离才用本档）。
  final double ring0;
  /// 该档外环半径（格，< 此距离仍用本档，>= 升档）。
  final double ring1;
}

/// R26lod：按 RenderConfig 参数生成 LOD 档位表（用户体系：起始区块 → 步长格 →
/// 采样 2 幂 → 最远区块）。
///
/// 每档 = (cell 大方块边长, ring0 内环, ring1 外环)：
///   · 起始内环 = lodStartChunks×16（满精度带外第一档起点）；
///   · 每档间距 = lodStepBlocks（格），cell 翻倍（2 幂：sampleBase, ×2, ×4…）；
///   · 最外档 ring1 = lodMaxChunks×16（LOD 视距可大于基础视距 → 远景大方块看得更远）。
/// lodEnabled=false → 空表（_emitLodPass 直接跳过，无远景 LOD）。
List<_LodTier> _lodTiers(RenderConfig config) {
  if (!config.lodMasterEnabled) return const <_LodTier>[];
  final double start = config.lodStartChunks * RenderConfig.chunkSize.toDouble();
  final double maxLod = config.lodMaxChunks * RenderConfig.chunkSize.toDouble();
  final int step = config.lodStepBlocks <= 0 ? 16 : config.lodStepBlocks;
  double ring0 = math.max(1.0, start);
  double cell = math.max(2, config.lodSampleBase).toDouble();
  final List<_LodTier> tiers = <_LodTier>[];
  int guard = 0;
  while (ring0 < maxLod && guard++ < 12) {
    double ring1 = ring0 + step;
    if (ring1 > maxLod) ring1 = maxLod;
    tiers.add(_LodTier(cell, ring0, ring1));
    cell *= 2;
    ring0 = ring1;
  }
  if (tiers.isEmpty) return const <_LodTier>[];
  return tiers;
}

/// P3·R26r18：复用 _chunkInFrustum 思路，参数化任意 size/topY 的区块级视锥测试。
/// 8 角（x0/x1 × z0/z1 × 0/topY）各做相机空间视锥判定；任一角落在视锥内即保留
/// （保守判定：只会多渲染、绝不漏渲染，与 _chunkInFrustum 同语义）。
bool _cellInFrustum(
  ViewBasis b,
  ProjectionParams p,
  double x0,
  double z0,
  double size,
  double topY,
) {
  final double tanX = p.halfW / p.scaleX;
  final double tanY = p.halfH / p.scaleY;
  final double xMin = x0, xMax = x0 + size;
  final double yMin = 0, yMax = topY;
  final double zMin = z0, zMax = z0 + size;
  for (int i = 0; i < 8; i++) {
    final double wx = (i & 1) == 0 ? xMin : xMax;
    final double wy = (i & 2) == 0 ? yMin : yMax;
    final double wz = (i & 4) == 0 ? zMin : zMax;
    final double dx = wx - b.eyeX;
    final double dy = wy - b.eyeY;
    final double dz = wz - b.eyeZ;
    final double vz = dx * b.fwdX + dy * b.fwdY + dz * b.fwdZ;
    if (vz < 0.02 || vz > 8192) continue;
    final double vx = dx * b.rightX + dy * b.rightY + dz * b.rightZ;
    final double vy = dx * b.upX + dy * b.upY + dz * b.upZ;
    if (vx.abs() <= vz * tanX && vy.abs() <= vz * tanY) return true;
  }
  return false;
}

/// R26r20：远景 LOD 马赛克单元（缓存，相机无关）——DH 风格逐列立方体。
/// 内 g×g 列（列宽 2）：顶高 hGrid + 顶方块 vGrid + 侧方块 vSide；外环 (g+2)²
/// hPad 供边界列 4 邻高度（无缝接邻单元）。按 tier 键入缓存（VoxelChunkCache.lodCellGet）。
class _LodCell {
  _LodCell({
    required this.g,
    required this.topY,
    required this.majority,
    required this.hGrid,
    required this.vGrid,
    required this.vSide,
    required this.hPad,
    required this.flat,
  }) : displayH = Float32List.fromList(hGrid);

  /// 每轴列数（g = size/2；总列数 g*g）。
  final int g;

  /// 最高非空方块的顶面 y（世界坐标；0 = 全空气不渲染）。= 恒定列宽采样真峰。
  final double topY;

  /// 多数方块（平坦快路径侧裙边用）。
  final Voxel majority;

  /// 每列顶高（g*g，行优先 j*g+i；0 = 该列无方块）。
  final Float32List hGrid;

  /// 每列顶部方块（顶面上色）。
  final List<Voxel> vGrid;

  /// 每列侧方块（顶下 1 格；暴露侧面上色——顶绿侧棕，贴近 MC）。
  final List<Voxel> vSide;

  /// 外扩 1 环列顶高 (g+2)*(g+2)，行优先；边界列 4 邻高度取自这里（无缝接邻单元）。
  final Float32List hPad;

  /// 平坦（全部列等高且同色）→ 快路径：单顶面 + 4 边界裙边（平原零开销）。
  final bool flat;

  /// P5 geomorph：每列当前显示顶高（每帧朝 [hGrid] lerp，消除档切换 snap；非 final）。
  final Float32List displayH;
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
/// S2：单区块「面—面空气连通性」摘要（相机无关，随几何缓存同期失效）。
/// 用于区块级连通 flood-fill 可见集（cave culling）：可见性沿空气连通传播，
/// 被实心封死的方向不再扩散。
class ChunkVisibility {
  /// 6 bit：该侧面是否存在空气格（0 = 完全封死，不可能透光）。
  /// bit 0:+X 1:-X 2:+Y(top) 3:-Y 4:+Z 5:-Z
  final int faceOpen;

  /// 15 bit：C(6,2) 面对是否通过区块内空气互相连通（[ _pairBit] 索引）。
  final int connMask;

  const ChunkVisibility(this.faceOpen, this.connMask);
}

class ChunkMesh {
  ChunkMesh(this.faces, this.columns, this.visibility);

  final List<CachedFace> faces;

  /// 本区块遍历的列数（调试统计）。
  final int columns;

  /// S2：本区块空气连通性（供 flood-fill 可见集；无缓存时为占位 0）。
  final ChunkVisibility visibility;
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
  VoxelChunkCache({this.maxChunks = 256, this.maxLodCells = 64});

  /// 最大缓存区块数（LRU 近似：超限删最老插入项）。
  /// 默认 256 覆盖 64 格半径窗口（9×9=81 区块）绰绰有余，玩家移动时
  /// 仅窗口边缘少数区块进出，远小于每帧全窗口重建。
  final int maxChunks;

  /// R26r13：远景 LOD 马赛克单元缓存上限（3×3/9×9 大块，数量极少）。
  final int maxLodCells;

  final Map<(int, int, int), ChunkMesh> _chunks =
      <(int, int, int), ChunkMesh>{};

  /// R26r13：LOD 马赛克单元缓存。key = (band, 单元网格 ci, cj)。
  final Map<(int, int, int), _LodCell> _lodCells =
      <(int, int, int), _LodCell>{};

  /// S2：区块空气连通性缓存。key = (cx, cz)，随几何缓存同期失效。
  final Map<(int, int), ChunkVisibility> _vis =
      <(int, int), ChunkVisibility>{};

  /// 命中 / 未命中计数（调试诊断）。
  int hits = 0;
  int misses = 0;

  // key = (cx, cz, lod)。用记录类型做**无碰撞**键——早期用 XOR 哈希会
  // 在小坐标对上发生碰撞，导致首帧就误命中（缓存串台）。记录键值相等、零碰撞。
  static (int, int, int) _key(int cx, int cz, int lod) => (cx, cz, lod);

  static (int, int, int) _lodKey(int tier, int ci, int cj) => (tier, ci, cj);

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

  /// R26r18·P1：取 / 存 LOD 马赛克单元（tier: 0..3 档；ci/cj 为该档粗格索引）。
  _LodCell? lodCellGet(int tier, int ci, int cj) =>
      _lodCells[_lodKey(tier, ci, cj)];

  void lodCellPut(int tier, int ci, int cj, _LodCell cell) {
    final (int, int, int) k = _lodKey(tier, ci, cj);
    if (_lodCells.length >= maxLodCells && !_lodCells.containsKey(k)) {
      _lodCells.remove(_lodCells.keys.first);
    }
    _lodCells[k] = cell;
  }

  /// R26r18·P1：迟滞状态表——记录每个基础格（cell=4）当前所用档，跨帧沿用以
  /// 实现 1.15×/0.87× 迟滞（防移动闪烁）。key = (baseI, baseJ)。
  final Map<(int, int), int> _lodTierMap = <(int, int), int>{};

  int? lodTierGet(int bi, int bj) => _lodTierMap[(bi, bj)];
  void lodTierPut(int bi, int bj, int t) => _lodTierMap[(bi, bj)] = t;

  /// S2：取 / 存区块空气连通性（key = (cx, cz)）。
  ChunkVisibility? visGet(int cx, int cz) => _vis[(cx, cz)];

  void visPut(int cx, int cz, ChunkVisibility vis) {
    _vis[(cx, cz)] = vis;
  }

  /// 使 (cx,cz) 区块的所有 LOD 版本失效（编辑后调用）。
  void invalidate(int cx, int cz) {
    for (int lod = 0; lod <= 3; lod++) {
      _chunks.remove(_key(cx, cz, lod));
    }
    _vis.remove((cx, cz));
    // 编辑改变遮挡 → 全部 LOD 马赛克 + 迟滞状态失效（重建惰性且便宜）。
    _lodCells.clear();
    _lodTierMap.clear();
  }

  void clear() {
    _chunks.clear();
    _lodCells.clear();
    _vis.clear();
    _lodTierMap.clear();
  }
}
