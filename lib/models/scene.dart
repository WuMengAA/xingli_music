import 'package:flutter/material.dart';

/// 场景的视觉配置
class SceneVisual {
  final List<Color> gradientColors;
  final List<double> stops;
  final Color accent;
  final String glyph;

  const SceneVisual({
    required this.gradientColors,
    required this.stops,
    required this.accent,
    required this.glyph,
  });

  SceneVisual copyWith({
    List<Color>? gradientColors,
    List<double>? stops,
    Color? accent,
    String? glyph,
  }) {
    return SceneVisual(
      gradientColors: gradientColors ?? this.gradientColors,
      stops: stops ?? this.stops,
      accent: accent ?? this.accent,
      glyph: glyph ?? this.glyph,
    );
  }

  Map<String, dynamic> toJson() => {
        'gradientColors': gradientColors.map((c) => c.toARGB32()).toList(),
        'stops': stops,
        'accent': accent.toARGB32(),
        'glyph': glyph,
      };

  factory SceneVisual.fromJson(Map<String, dynamic> json) {
    return SceneVisual(
      gradientColors: (json['gradientColors'] as List<dynamic>? ?? [])
          .map((e) => Color(e as int))
          .toList(),
      stops: (json['stops'] as List<dynamic>? ?? []).cast<double>(),
      accent: Color(json['accent'] as int? ?? 0xFF9B7BFF),
      glyph: json['glyph'] as String? ?? '✦',
    );
  }
}

/// 音乐空间中的一个场景。
class Scene {
  final String id;
  final String name;
  final String mood;
  final String desc;
  final String track;
  final String artist;
  final String soundscape;

  /// 场景图标（assets/icons 下的文件名，见 [AppIcon]）
  final String icon;

  final SceneVisual visual;
  final double visualWeight;

  /// 情绪坐标（情绪梯度 / 漫游用）
  final double valence;
  final double energy;

  /// 专属音源 id；非空时该场景只播此源的曲（如 snow -> 'minecraft'）
  final String? musicSourceId;

  /// 自定义音景音频文件路径（非空时优先于程序合成）
  final String? soundscapePath;

  /// 自定义粒子颜色（非空时覆盖按 id 派生的粒子色）
  final Color? particleColor;

  /// 自定义粒子运动风格（rain/snow/fireplace/ocean/starnight/dust）
  final String? particleMotion;

  /// 自定义背景渐变色（非空时覆盖背景顶部颜色）
  final Color? bgTop;
  final Color? bgBottom;

  const Scene({
    required this.id,
    required this.name,
    required this.mood,
    required this.desc,
    required this.track,
    required this.artist,
    required this.soundscape,
    required this.icon,
    required this.visual,
    required this.visualWeight,
    required this.valence,
    required this.energy,
    this.musicSourceId,
    this.soundscapePath,
    this.particleColor,
    this.particleMotion,
    this.bgTop,
    this.bgBottom,
  });

  /// 是否为用户自定义场景（内置场景 id 无前缀，自定义以 'custom_' 开头）
  bool get isCustom => id.startsWith('custom_');

  Scene copyWith({
    String? id,
    String? name,
    String? mood,
    String? desc,
    String? track,
    String? artist,
    String? soundscape,
    String? icon,
    SceneVisual? visual,
    double? visualWeight,
    double? valence,
    double? energy,
    String? musicSourceId,
    String? soundscapePath,
    Color? particleColor,
    String? particleMotion,
    Color? bgTop,
    Color? bgBottom,
    bool clearMusicSourceId = false,
    bool clearSoundscapePath = false,
    bool clearParticleColor = false,
    bool clearBg = false,
  }) {
    return Scene(
      id: id ?? this.id,
      name: name ?? this.name,
      mood: mood ?? this.mood,
      desc: desc ?? this.desc,
      track: track ?? this.track,
      artist: artist ?? this.artist,
      soundscape: soundscape ?? this.soundscape,
      icon: icon ?? this.icon,
      visual: visual ?? this.visual,
      visualWeight: visualWeight ?? this.visualWeight,
      valence: valence ?? this.valence,
      energy: energy ?? this.energy,
      musicSourceId: clearMusicSourceId ? null : (musicSourceId ?? this.musicSourceId),
      soundscapePath: clearSoundscapePath ? null : (soundscapePath ?? this.soundscapePath),
      particleColor: clearParticleColor ? null : (particleColor ?? this.particleColor),
      particleMotion: particleMotion ?? this.particleMotion,
      bgTop: clearBg ? null : (bgTop ?? this.bgTop),
      bgBottom: clearBg ? null : (bgBottom ?? this.bgBottom),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mood': mood,
        'desc': desc,
        'track': track,
        'artist': artist,
        'soundscape': soundscape,
        'icon': icon,
        'visual': visual.toJson(),
        'visualWeight': visualWeight,
        'valence': valence,
        'energy': energy,
        'musicSourceId': musicSourceId,
        'soundscapePath': soundscapePath,
        'particleColor': particleColor?.toARGB32(),
        'particleMotion': particleMotion,
        'bgTop': bgTop?.toARGB32(),
        'bgBottom': bgBottom?.toARGB32(),
      };

  factory Scene.fromJson(Map<String, dynamic> json) {
    return Scene(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      mood: json['mood'] as String? ?? '',
      desc: json['desc'] as String? ?? '',
      track: json['track'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      soundscape: json['soundscape'] as String? ?? '',
      icon: json['icon'] as String? ?? 'star',
      visual: SceneVisual.fromJson(
          json['visual'] as Map<String, dynamic>? ?? {}),
      visualWeight: (json['visualWeight'] as num?)?.toDouble() ?? 0.8,
      valence: (json['valence'] as num?)?.toDouble() ?? 0.5,
      energy: (json['energy'] as num?)?.toDouble() ?? 0.5,
      musicSourceId: json['musicSourceId'] as String?,
      soundscapePath: json['soundscapePath'] as String?,
      particleColor: json['particleColor'] != null
          ? Color(json['particleColor'] as int)
          : null,
      particleMotion: json['particleMotion'] as String?,
      bgTop: json['bgTop'] != null ? Color(json['bgTop'] as int) : null,
      bgBottom: json['bgBottom'] != null ? Color(json['bgBottom'] as int) : null,
    );
  }
}
