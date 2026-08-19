import 'dart:convert';

import 'package:flutter/material.dart';

/// 2.5D 音效块类型（v2 M5-1 / M2-D 共享渲染基础）。
///
/// 每个块类型对应一个音效 key（sfxKey），`SoundBlockMixer` 用它查音效资源
/// 并按方块数量 / 位置混合；`baseVolume` 是单块的基准音量。
@immutable
class VoxelBlockType {
  const VoxelBlockType({
    required this.id,
    required this.name,
    required this.icon,
    required this.sfxKey,
    required this.baseVolume,
    required this.color,
    this.glyph = '◆',
    this.customPath,
  });

  /// 类型 id（也是序列化 key 的值）。
  final String id;

  /// 展示名（雨声 / 风声 / 壁炉 / 鸟鸣 …）。
  final String name;

  /// 面板图标（Material Icons）。
  final IconData icon;

  /// 音效资源 key（相对 minecraft_music/sfx 目录的路径段，见 [SoundBlockMixer]）。
  final String sfxKey;

  /// 单块基准音量（0.0~1.0）。
  final double baseVolume;

  /// 方块顶面色（画布绘制）。
  final Color color;

  /// 顶面纹理符号（小游戏收集品与编辑器顶面绘制用）。
  final String glyph;

  /// 用户自定义音效：直接指向音频文件路径（优先于 [sfxKey] 目录查找）。
  /// 为 null 表示预设块（走 sfxKey → 资源目录解析）。
  final String? customPath;
}

/// 2.5D 音效块预设库（数据驱动，P0-M5-1 / P1-M5-5）。
///
/// `sfxKey` 对应 `minecraft_music/sfx/sounds/...` 下的 ogg 文件，
/// 由 [SoundBlockMixer] 按 key 在基础目录内查找。
const List<VoxelBlockType> kVoxelBlockTypes = <VoxelBlockType>[
  VoxelBlockType(
    id: 'rain',
    name: '雨声',
    icon: Icons.water_drop_rounded,
    sfxKey: 'rain',
    baseVolume: 0.28,
    color: Color(0xFF7B9BFF),
    glyph: '❖',
  ),
  VoxelBlockType(
    id: 'wind',
    name: '风声',
    icon: Icons.air_rounded,
    sfxKey: 'wind',
    baseVolume: 0.22,
    color: Color(0xFF9BD9E8),
    glyph: '≈',
  ),
  VoxelBlockType(
    id: 'fire',
    name: '壁炉',
    icon: Icons.local_fire_department_rounded,
    sfxKey: 'fire',
    baseVolume: 0.30,
    color: Color(0xFFFF9B5A),
    glyph: '✦',
  ),
  VoxelBlockType(
    id: 'bird',
    name: '鸟鸣',
    icon: Icons.flutter_dash_rounded,
    sfxKey: 'bird',
    baseVolume: 0.18,
    color: Color(0xFF7BFF9B),
    glyph: '♫',
  ),
  VoxelBlockType(
    id: 'water',
    name: '水流',
    icon: Icons.waves_rounded,
    sfxKey: 'water',
    baseVolume: 0.24,
    color: Color(0xFF4A9BFF),
    glyph: '〰',
  ),
  VoxelBlockType(
    id: 'cricket',
    name: '虫鸣',
    icon: Icons.grass_rounded,
    sfxKey: 'cricket',
    baseVolume: 0.16,
    color: Color(0xFFB0D97B),
    glyph: '·',
  ),
];

/// 按 id 查找预设（找不到返回 [kVoxelBlockTypes] 第一个）。
VoxelBlockType voxelBlockTypeById(String id) {
  for (final VoxelBlockType t in kVoxelBlockTypes) {
    if (t.id == id) return t;
  }
  return kVoxelBlockTypes.first;
}

/// 统一解析：优先自定义（会话内），其次预设，兜底预设第一个。
///
/// 画布渲染 / 点击播放 / 可视化 pitch 计算一律走此入口，保证
/// 用户自定义音效块能被正确渲染与发声。
VoxelBlockType resolveBlockTypeById(String id) {
  final VoxelBlockType? custom = _customTypes[id];
  if (custom != null) return custom;
  return voxelBlockTypeById(id);
}

/// 会话内自定义音效块（用户 file_picker 添加，key 见 [kBiomeSoundIds]）。
///
/// 仅存于内存（编辑器打开期间），不落盘到 `kVoxelBlockTypes`——
/// 场景序列化只存类型 id；重新打开编辑器时由
/// [CustomSoundRegistry]（见编辑器页）按 id 重建类型定义。
final Map<String, VoxelBlockType> _customTypes = <String, VoxelBlockType>{};

/// 注册一个自定义音效块（覆盖同 id）。
void registerCustomBlockType(VoxelBlockType t) {
  _customTypes[t.id] = t;
}

/// 查询自定义音效块（无则 null）。
VoxelBlockType? customBlockTypeById(String id) => _customTypes[id];

/// 当前全部可用的自定义音效块（编辑面板展示用）。
List<VoxelBlockType> get customBlockTypes =>
    _customTypes.values.toList(growable: false);

/// 群系 → 推荐音效块 id 集（2.5D 画布「音效随群系刷新」）。
///
/// 用户在 2.5D 画布/编辑器顶部选群系时，按此表把该群系的自然音效
/// 置顶/突出显示，其余预设仍可手动添加（不锁死）。
/// 键为 [Biome] 枚举名（见 `widgets/voxel/voxel_world_types.dart`）。
const Map<String, List<String>> kBiomeSoundIds = <String, List<String>>{
  // 平原：风声 + 虫鸣（开阔草地）。
  'plains': <String>['wind', 'cricket', 'bird'],
  // 森林：鸟鸣 + 风声 + 虫鸣（树影层叠）。
  'forest': <String>['bird', 'wind', 'cricket'],
  // 沙漠：风声 + 虫鸣（干燥少水）。
  'desert': <String>['wind', 'cricket'],
  // 高山：风声（开阔高海拔）。
  'mountain': <String>['wind', 'bird'],
  // 雪山：风声（低温空旷）。
  'snowMountain': <String>['wind'],
  // 河流：水流 + 鸟鸣（水岸）。
  'river': <String>['water', 'bird'],
  // 海洋：水流 + 风声（海浪感）。
  'ocean': <String>['water', 'wind'],
};

/// 2.5D 可视化可调参数（Module "MusicViz-2.5D" · Phase 2：viz 编辑态持久化）。
///
/// 用户在画布页「可视化」面板调的 3 个滑块，随场景一起持久化；
/// 旧场景无此字段 → [defaults]，打开即恢复中性观感。
@immutable
class VoxelVizSettings {
  const VoxelVizSettings({
    this.amplitude = 0.9,
    this.ripplePosWeight = 0.55,
    this.beatPulse = 0.15,
  });

  /// 频段能量推动方块挤出高度的幅度（0~1.5；原写死 0.9）。
  final double amplitude;

  /// 频段绑定混合里「位置涟漪」权重（0~1；其余归音色音高；原 0.55）。
  final double ripplePosWeight;

  /// 节拍驱动顶面菱形缩放强度（0~0.4；原 0.15 → 顶面 1.0~1.15）。
  final double beatPulse;

  /// 中性默认值（与 Phase 1 原始观感一致）。
  static const VoxelVizSettings defaults = VoxelVizSettings();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'amplitude': amplitude,
        'ripplePosWeight': ripplePosWeight,
        'beatPulse': beatPulse,
      };

  factory VoxelVizSettings.fromJson(Map<String, dynamic> json) {
    double d(num? v, double fallback) =>
        (v is num) ? v.toDouble().clamp(0.0, 2.0) : fallback;
    return VoxelVizSettings(
      amplitude: d(json['amplitude'] as num?, 0.9),
      ripplePosWeight: d(json['ripplePosWeight'] as num?, 0.55),
      beatPulse: d(json['beatPulse'] as num?, 0.15),
    );
  }

  VoxelVizSettings copyWith({
    double? amplitude,
    double? ripplePosWeight,
    double? beatPulse,
  }) =>
      VoxelVizSettings(
        amplitude: amplitude ?? this.amplitude,
        ripplePosWeight: ripplePosWeight ?? this.ripplePosWeight,
        beatPulse: beatPulse ?? this.beatPulse,
      );
}

/// 2.5D 音效场景保存模型（v2 M5-1 · P0-M5-1）。
///
/// JSON 格式（架构 §3.2.3 / §7.7）：
/// `{'id','name','cols','rows','blocks': {'x,y': typeId}}`
@immutable
class VoxelSoundScene {
  const VoxelSoundScene({
    required this.id,
    required this.name,
    required this.cols,
    required this.rows,
    required this.blocks,
    this.heights = const <String, double>{},
    this.viz,
  });

  final String id;
  final String name;
  final int cols;
  final int rows;

  /// 方块表：网格 key `"$col,$row"` → 类型 id。
  final Map<String, String> blocks;

  /// 每格高度比（0~1，来自 3D 世界提取；缺省的不参与可视化起伏，回落 0.5）。
  /// 向后兼容：旧场景无此字段 → 空 map。
  final Map<String, double> heights;

  /// 可视化可调参数（振幅 / 涟漪权重 / 节拍脉冲）；null → [VoxelVizSettings.defaults]。
  /// 向后兼容：旧场景无此字段 → null。
  final VoxelVizSettings? viz;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'cols': cols,
        'rows': rows,
        'blocks': blocks,
        if (heights.isNotEmpty) 'heights': heights,
        if (viz != null) 'viz': viz!.toJson(),
      };

  factory VoxelSoundScene.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? vizJson =
        json['viz'] as Map<String, dynamic>?;
    return VoxelSoundScene(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      cols: (json['cols'] as num?)?.toInt() ?? 8,
      rows: (json['rows'] as num?)?.toInt() ?? 8,
      blocks: (json['blocks'] as Map<String, dynamic>?)
              ?.map((String k, dynamic v) => MapEntry(k, v as String)) ??
          const <String, String>{},
      heights: (json['heights'] as Map<String, dynamic>?)?.map(
            (String k, dynamic v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          const <String, double>{},
      viz: vizJson == null ? null : VoxelVizSettings.fromJson(vizJson),
    );
  }

  String encode() => jsonEncode(toJson());

  static VoxelSoundScene decode(String raw) =>
      VoxelSoundScene.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// 拷贝并覆盖部分字段（导入场景时分配新 id / 重命名用）。
  VoxelSoundScene copyWith({
    String? id,
    String? name,
    int? cols,
    int? rows,
    Map<String, String>? blocks,
    Map<String, double>? heights,
    VoxelVizSettings? viz,
  }) =>
      VoxelSoundScene(
        id: id ?? this.id,
        name: name ?? this.name,
        cols: cols ?? this.cols,
        rows: rows ?? this.rows,
        blocks: blocks ?? this.blocks,
        heights: heights ?? this.heights,
        viz: viz ?? this.viz,
      );
}
