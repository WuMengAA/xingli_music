/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 · 取景快照（Phase 4 · 拍照取景 → 场景背景）
/// ════════════════════════════════════════════════════════════════════════
///
/// 在体素世界里「拍照 / 选区域」，把当前视角作为音乐播放器**场景的背景**。
///
/// 关键设计：**只存机位 + 世界种子，不存像素**。
/// - 同 `seed` + 同尺寸 ⇒ [VoxelWorld] 逐格相同（拍照复现的技术前提）；
/// - 背景相机固定，几何只算一次、每 tick 只动水波 / 叶摇 / 天光相位；
///   18fps 下 CPU 仅占个位数百分比（见 `docs/体素世界技术方案.md` §G-3）。
/// - 省电模式退化为静态单帧，不重绘动画。
library;

import 'voxel_camera.dart';
import 'voxel_world.dart';

/// 一张取景快照里的一个空间音效源（H2：玩家中心 16×16 的音效原封不动复用）。
///
/// 由 `WorldAudioEngine.scanSources` 扫描世界得到（水/叶/鸟/风/篝火簇），
/// 只存 类型 + 位置 + 响度；主页背景用同 seed 世界 + 同机位重放 → 听感一致。
class VoxelSoundscapeSource {
  const VoxelSoundscapeSource({
    required this.kind,
    required this.x,
    required this.y,
    required this.z,
    this.strength = 1.0,
  });

  /// 音效类型名（WorldSfx.name：water/leaves/birds/wind/campfire）。
  final String kind;

  /// 发声点世界坐标（方块单位，簇质心）。
  final double x, y, z;

  /// 簇规模折算的响度系数（0~1）。
  final double strength;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'x': x,
        'y': y,
        'z': z,
        'strength': strength,
      };

  factory VoxelSoundscapeSource.fromJson(Map<String, dynamic> json) =>
      VoxelSoundscapeSource(
        kind: json['kind'] as String? ?? 'wind',
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        z: (json['z'] as num?)?.toDouble() ?? 0,
        strength: (json['strength'] as num?)?.toDouble() ?? 1.0,
      );
}

/// 一张体素世界取景快照。
class VoxelSceneCapture {
  const VoxelSceneCapture({
    required this.seed,
    required this.cameraX,
    required this.cameraY,
    required this.cameraZ,
    required this.yaw,
    required this.pitch,
    required this.fov,
    this.aspect = 1.0,
    this.timePhase = 0.25,
    this.sounds = const <VoxelSoundscapeSource>[],
  });

  /// 世界种子（决定地形）。
  final int seed;

  /// 相机世界坐标（方块为单位，可小数）。
  final double cameraX, cameraY, cameraZ;

  /// 偏航 / 俯仰 / 垂直视场角（弧度）。
  final double yaw, pitch, fov;

  /// 取景视口宽高比（仅作保存时比例提示；背景渲染用真实容器尺寸）。
  final double aspect;

  /// 时相 [0,1)：0 黎明 / 0.25 正午 / 0.5 黄昏 / 0.75 夜。
  final double timePhase;

  /// H2：取景时玩家中心 16×16 内的空间音效源（主页背景重放）。
  final List<VoxelSoundscapeSource> sounds;

  /// 由当前世界 + 相机生成快照。
  factory VoxelSceneCapture.fromCamera(
    VoxelWorld world,
    VoxelCamera camera, {
    double aspect = 1.0,
    double timePhase = 0.25,
    List<VoxelSoundscapeSource> sounds = const <VoxelSoundscapeSource>[],
  }) =>
      VoxelSceneCapture(
        seed: world.seed,
        cameraX: camera.position.x,
        cameraY: camera.position.y,
        cameraZ: camera.position.z,
        yaw: camera.yaw,
        pitch: camera.pitch,
        fov: camera.fov,
        aspect: aspect,
        timePhase: timePhase,
        sounds: sounds,
      );

  /// H2：带音效副本（不改原快照）。
  VoxelSceneCapture withSounds(List<VoxelSoundscapeSource> sounds) =>
      VoxelSceneCapture(
        seed: seed,
        cameraX: cameraX,
        cameraY: cameraY,
        cameraZ: cameraZ,
        yaw: yaw,
        pitch: pitch,
        fov: fov,
        aspect: aspect,
        timePhase: timePhase,
        sounds: sounds,
      );

  /// 重建相机（按记录的机位）。
  VoxelCamera toCamera() => VoxelCamera(
        position: Vec3(cameraX, cameraY, cameraZ),
        yaw: yaw,
        pitch: pitch,
        fov: fov,
      );

  /// 重建世界（确定性：同 seed ⇒ 同地形）。
  VoxelWorld toWorld() => VoxelWorld(seed: seed);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'seed': seed,
        'cx': cameraX,
        'cy': cameraY,
        'cz': cameraZ,
        'yaw': yaw,
        'pitch': pitch,
        'fov': fov,
        'aspect': aspect,
        'timePhase': timePhase,
        'sounds': sounds.map((VoxelSoundscapeSource s) => s.toJson()).toList(),
      };

  factory VoxelSceneCapture.fromJson(Map<String, dynamic> json) =>
      VoxelSceneCapture(
        seed: json['seed'] as int? ?? VoxelWorld.defaultSeed,
        cameraX: (json['cx'] as num?)?.toDouble() ?? 0,
        cameraY: (json['cy'] as num?)?.toDouble() ?? 0,
        cameraZ: (json['cz'] as num?)?.toDouble() ?? 0,
        yaw: (json['yaw'] as num?)?.toDouble() ?? 0,
        pitch: (json['pitch'] as num?)?.toDouble() ?? 0,
        fov: (json['fov'] as num?)?.toDouble() ?? 1.0472,
        aspect: (json['aspect'] as num?)?.toDouble() ?? 1.0,
        timePhase: (json['timePhase'] as num?)?.toDouble() ?? 0.25,
        sounds: (json['sounds'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) =>
                VoxelSoundscapeSource.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
