/// ════════════════════════════════════════════════════════════════════════
/// 空间音效引擎 · 核心模型（SpatialAudio）
/// ════════════════════════════════════════════════════════════════════════
///
/// 设计（用户需求）：
///  - **统一噪音合成模式**：以 2.5D 编辑器为基础，所有音效由算法合成
///  - **4 音轨**：每个音效最多 4 条音轨（Track 0..3），可独立设音量/声道
///  - **声道空间化**：几何中心为起点，前后左右对应不同空间声道；
///    声道数按设备适配（单声道设备降级为单声道，立体声 2 声道，
///    环绕设备按可用声道映射）
///  - **物体动能**：水方块（放置静止水源，四周无障碍物时以方块为单位
///    最远可流动至以自身为中心 9 格远）；篝火/熔炉（持久音效 + 随机
///    柴噼啪/熔炉咕噜）
///  - **材料隔音**：石/金属/木/泥土/羊毛/玻璃 6 类，各有隔音 Rw 与
///    吸音系数 α，声音跨方块传播按材料衰减
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 空间声道（几何方向）。
enum SpatialChannel {
  /// 中心（几何起点，作为所有声道的基准）。
  center,

  /// 前。
  front,

  /// 后。
  back,

  /// 左。
  left,

  /// 右。
  right,
}

/// 声道布局（按设备能力适配）。
enum ChannelLayout {
  /// 单声道设备：全部混为 1 路。
  mono,

  /// 立体声：center/front → L+R，back/left/right 做声像。
  stereo,

  /// 环绕（5.1 及以上）：按方向映射。
  surround,
}

/// 声像参数：某音轨在声道布局中的电平（0~1）。
class ChannelGains {
  const ChannelGains({
    required this.left,
    required this.right,
    this.center = 0,
    this.surroundBack = 0,
  });

  final double left;
  final double right;
  final double center;
  final double surroundBack;

  /// 双声道输出（left, right）。
  (double, double) toStereo() => (left, right);

  static const ChannelGains kCenter = ChannelGains(left: 0.7, right: 0.7, center: 1);
  static const ChannelGains kFront = ChannelGains(left: 0.85, right: 0.85);
  static const ChannelGains kBack = ChannelGains(left: 0.5, right: 0.5, surroundBack: 1);
  static const ChannelGains kLeft = ChannelGains(left: 1, right: 0.15);
  static const ChannelGains kRight = ChannelGains(left: 0.15, right: 1);
}

/// 单条音轨。
@immutable
class SpatialTrack {
  const SpatialTrack({
    required this.id,
    required this.channel,
    this.volume = 1.0,
    this.loop = true,
    this.synthesisId,
    this.audioPath,
  });

  final String id;

  /// 空间声道（几何方向）。
  final SpatialChannel channel;

  /// 音量（0~1）。
  final double volume;

  /// 是否循环。
  final bool loop;

  /// 合成参数 id（程序合成时用，见 SpatialSynth）。
  final String? synthesisId;

  /// 音频文件路径（有则优先于合成）。
  final String? audioPath;

  /// 按设备声道布局计算双声道增益。
  ChannelGains gainsFor(ChannelLayout layout) {
    if (layout == ChannelLayout.mono) {
      return const ChannelGains(left: 1, right: 1);
    }
    return switch (channel) {
      SpatialChannel.center => ChannelGains.kCenter,
      SpatialChannel.front => ChannelGains.kFront,
      SpatialChannel.back => ChannelGains.kBack,
      SpatialChannel.left => ChannelGains.kLeft,
      SpatialChannel.right => ChannelGains.kRight,
    };
  }
}

/// 空间音效：由 1~4 条音轨构成。
@immutable
class SpatialSound {
  const SpatialSound({
    required this.id,
    required this.name,
    required this.tracks,
    this.material = SoundMaterial.stone,
  });

  final String id;
  final String name;

  /// 音轨（1~4 条）。
  final List<SpatialTrack> tracks;

  /// 承载该音效的方块材料（决定跨方块隔音）。
  final SoundMaterial material;

  static const int maxTracks = 4;

  bool get valid => tracks.isNotEmpty && tracks.length <= maxTracks;

  /// 复制并把所有音轨音量统一缩放 factor（R23i：全局音量接入）。
  SpatialSound scaled(double factor) {
    if (factor <= 0) {
      return SpatialSound(
        id: id,
        name: name,
        material: material,
        tracks: <SpatialTrack>[
          for (final SpatialTrack t in tracks)
            SpatialTrack(
              id: t.id,
              channel: t.channel,
              volume: 0,
              audioPath: t.audioPath,
              synthesisId: t.synthesisId,
            ),
        ],
      );
    }
    return SpatialSound(
      id: id,
      name: name,
      material: material,
      tracks: <SpatialTrack>[
        for (final SpatialTrack t in tracks)
          SpatialTrack(
            id: t.id,
            channel: t.channel,
            volume: (t.volume * factor).clamp(0.0, 1.0),
            audioPath: t.audioPath,
            synthesisId: t.synthesisId,
          ),
      ],
    );
  }
}

/// 6 类方块材料（用户给定参数）。
enum SoundMaterial {
  /// 石质类（圆石/深板岩/混凝土）：隔音极佳，吸音极差。
  stone,

  /// 金属块（铁/金/铜）：隔音好，吸音极差，易刺耳回声。
  metal,

  /// 木质类（木板/原木）：隔音中等，吸音中等偏低。
  wood,

  /// 泥土/沙砾（松软）：隔音一般，吸音中等。
  dirt,

  /// 羊毛/地毯/雪：隔音极差，吸音极佳。
  wool,

  /// 玻璃/冰/水：隔音中等，吸音极低，水导声极好。
  glass,
}

/// 材料声学参数。
class MaterialAcoustics {
  const MaterialAcoustics({
    required this.name,
    required this.rwDb,
    required this.absorption,
    required this.reflection,
    this.description = '',
  });

  final String name;

  /// 隔音量 Rw（dB）：越高越隔音。
  final double rwDb;

  /// 吸音系数 α（0~1）：越高吸收越多。
  final double absorption;

  /// 反射系数（≈ 1-α）。
  final double reflection;

  final String description;

  static const Map<SoundMaterial, MaterialAcoustics> all = <SoundMaterial, MaterialAcoustics>{
    SoundMaterial.stone: MaterialAcoustics(
      name: '石质',
      rwDb: 50,
      absorption: 0.03,
      reflection: 0.97,
      description: '隔音极佳 · 吸音极差（表面光滑全反射）',
    ),
    SoundMaterial.metal: MaterialAcoustics(
      name: '金属',
      rwDb: 42,
      absorption: 0.015,
      reflection: 0.985,
      description: '隔音好（质量定律）· 吸音极差 · 易刺耳回声',
    ),
    SoundMaterial.wood: MaterialAcoustics(
      name: '木质',
      rwDb: 35,
      absorption: 0.2,
      reflection: 0.8,
      description: '隔音中等 · 吸音中等偏低（实木低频几乎无吸收）',
    ),
    SoundMaterial.dirt: MaterialAcoustics(
      name: '泥土',
      rwDb: 30,
      absorption: 0.4,
      reflection: 0.6,
      description: '隔音一般 · 吸音中等（松散颗粒消耗声能）',
    ),
    SoundMaterial.wool: MaterialAcoustics(
      name: '羊毛',
      rwDb: 18,
      absorption: 0.8,
      reflection: 0.2,
      description: '隔音极差 · 吸音极佳（多孔纤维，录音棚同款）',
    ),
    SoundMaterial.glass: MaterialAcoustics(
      name: '玻璃',
      rwDb: 30,
      absorption: 0.025,
      reflection: 0.975,
      description: '隔音中等受厚度制约 · 吸音极低 · 水是极好导声介质',
    ),
  };

  static MaterialAcoustics of(SoundMaterial m) => all[m]!;
}

/// 声音经过 N 格 [material] 方块后的透射衰减（线性插值到 Rw 上限）。
///
/// 单格按 Rw/10 衰减（每 10dB 音量减半感知），多格近似叠加，
/// 但羊毛等吸音材料额外叠加吸收。
double transmissionLoss(SoundMaterial material, int walls) {
  if (walls <= 0) return 0;
  final MaterialAcoustics a = MaterialAcoustics.of(material);
  // 基础隔音：每格 Rw 的 15%（简化物理，避免一堵墙就全静音）
  final double iso = a.rwDb * 0.15 * walls;
  // 吸收附加：α 越高，多格衰减越强（指数）
  final double absorb = -math.log(1 - a.absorption.clamp(0.0, 0.99)) * walls * 1.5;
  return iso + absorb;
}

/// 把 dB 衰减换算为音量倍率（0~1）。
double dbToGain(double db) => math.pow(10.0, -db / 20.0).toDouble();

/// 水方块流动：以自身为中心，向四周无障碍物方向最远流动 9 格（曼哈顿距离）。
///
/// 返回可流到的坐标集合（相对偏移）。`isBlocked` 判定某格是否有障碍。
/// 语义：从起点向上下左右四方向 BFS，每步距离 +1，遇障碍或超过
/// [maxDistance] 停止；无障碍时覆盖曼哈顿距离 ≤ 9 的整个菱形区域。
Set<(int, int)> waterFlow(
  int originX,
  int originY,
  bool Function(int x, int y) isBlocked, {
  int maxDistance = 9,
}) {
  final Set<(int, int)> reachable = <(int, int)>{};
  if (isBlocked(originX, originY)) return reachable;

  // BFS：dist 按曼哈顿距离递增
  final List<(int, int, int)> queue = <(int, int, int)>[(originX, originY, 0)];
  reachable.add((originX, originY));
  int head = 0;
  while (head < queue.length) {
    final (int x, int y, int d) = queue[head++];
    if (d >= maxDistance) continue;
    for (final (int nx, int ny) in <(int, int)>[
      (x + 1, y),
      (x - 1, y),
      (x, y + 1),
      (x, y - 1),
    ]) {
      if (isBlocked(nx, ny)) continue;
      if (reachable.add((nx, ny))) {
        queue.add((nx, ny, d + 1));
      }
    }
  }
  return reachable;
}
