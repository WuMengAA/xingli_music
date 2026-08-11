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
  });

  final String id;
  final String name;
  final int cols;
  final int rows;

  /// 方块表：网格 key `"$col,$row"` → 类型 id。
  final Map<String, String> blocks;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'cols': cols,
        'rows': rows,
        'blocks': blocks,
      };

  factory VoxelSoundScene.fromJson(Map<String, dynamic> json) {
    return VoxelSoundScene(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      cols: (json['cols'] as num?)?.toInt() ?? 8,
      rows: (json['rows'] as num?)?.toInt() ?? 8,
      blocks: (json['blocks'] as Map<String, dynamic>?)
              ?.map((String k, dynamic v) => MapEntry(k, v as String)) ??
          const <String, String>{},
    );
  }

  String encode() => jsonEncode(toJson());

  static VoxelSoundScene decode(String raw) =>
      VoxelSoundScene.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
