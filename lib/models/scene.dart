import 'package:flutter/material.dart';

import '../widgets/voxel/voxel_capture_models.dart';

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

  /// v2 M5-2：是否在场景列表中显示（默认 true；false = 隐藏）。
  ///
  /// 向后兼容：旧 JSON 缺失该字段时默认 true。
  final bool visible;

  /// v2 M5-3：默认背景音乐（BGM，从曲库选曲）。三个字段均为可空，
  /// 缺失即 null —— 旧数据不受影响（R-02 已缓解）。
  final String? bgmUri;
  final String? bgmTitle;
  final String? bgmArtist;

  /// P-2：本场景由分享包导入时，记录**分享方的原始 id**（仅溯源用）。
  ///
  /// 导入时本地 id 一律重新分配（见 `Scenes.decodePack`），此字段不参与
  /// 任何查找/覆盖逻辑，纯粹便于用户与日志辨认来源。自建场景为 null。
  final String? sourceShareId;

  /// Phase 4：体素世界取景快照（作为场景背景实时渲染）。
  /// 非空时场景页背景用体素世界取代渐变 + 粒子。
  final VoxelSceneCapture? voxelCapture;

  /// #167：本场景的**白噪音**开关（规范名「白噪音」）。
  ///
  /// 「跟随场景」模式（[whiteNoiseFollowsSceneProvider] = true，默认）下白噪音
  /// 取此值；「全局播放」模式下忽略本字段，改用全局开关。
  /// 向后兼容：旧 JSON 缺失该字段时默认 true（与全局默认一致）。
  final bool whiteNoise;

  /// #167：本场景的白噪音音量（0.0~1.0，缺失默认 0.15，与全局默认一致）。
  final double whiteNoiseVolume;

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
    this.visible = true,
    this.bgmUri,
    this.bgmTitle,
    this.bgmArtist,
    this.sourceShareId,
    this.voxelCapture,
    this.whiteNoise = false,
    this.whiteNoiseVolume = 0.25,
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
    bool? visible,
    String? bgmUri,
    String? bgmTitle,
    String? bgmArtist,
    String? sourceShareId,
    VoxelSceneCapture? voxelCapture,
    bool? whiteNoise,
    double? whiteNoiseVolume,
    bool clearVoxelCapture = false,
    bool clearMusicSourceId = false,
    bool clearSoundscapePath = false,
    bool clearParticleColor = false,
    bool clearBg = false,
    bool clearBgm = false,
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
      visible: visible ?? this.visible,
      bgmUri: clearBgm ? null : (bgmUri ?? this.bgmUri),
      bgmTitle: clearBgm ? null : (bgmTitle ?? this.bgmTitle),
      bgmArtist: clearBgm ? null : (bgmArtist ?? this.bgmArtist),
      sourceShareId: sourceShareId ?? this.sourceShareId,
      voxelCapture: clearVoxelCapture ? null : (voxelCapture ?? this.voxelCapture),
      whiteNoise: whiteNoise ?? this.whiteNoise,
      whiteNoiseVolume: whiteNoiseVolume ?? this.whiteNoiseVolume,
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
        'visible': visible,
        'bgmUri': bgmUri,
        'bgmTitle': bgmTitle,
        'bgmArtist': bgmArtist,
        'sourceShareId': sourceShareId,
        'voxelCapture': voxelCapture?.toJson(),
        // #167：场景专属白噪音（规范名「白噪音」）
        'whiteNoise': whiteNoise,
        'whiteNoiseVolume': whiteNoiseVolume,
      };

  // ── P-2 分享隐私 ──────────────────────────────────
  //
  // [toJson] 是**本机持久化**用的全量快照，必须保留绝对路径（否则重启后
  // 自定义音景失效）。分享/打包走 [toShareJson]：分享包会被复制到剪贴板、
  // 发给他人，绝不能带出 `C:\Users\<真实用户名>\...` 这类本机信息。

  /// 判断字符串是否像**本机绝对路径**（Windows 盘符 / UNC / POSIX 绝对路径）。
  static bool isLocalPathLike(String? v) {
    if (v == null || v.isEmpty) return false;
    if (v.startsWith('/') || v.startsWith(r'\\')) return true;
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(v)) return true;
    return v.contains(r'\');
  }

  /// 分享/打包专用序列化：剥离一切本机路径信息。
  ///
  /// 处理规则：
  /// - `soundscapePath`：**始终置空**。它按定义就是本机音频文件绝对路径，
  ///   对接收方也无意义（对方机器上不存在该文件）。
  /// - `musicSourceId`：若形如 `dir:<绝对路径>`（自定义目录曲库源 id）则置空，
  ///   内置源 id（如 `minecraft`）保留。
  /// - `bgmUri`：本机路径直接置空；远端 URL 剥离 query/fragment 与 userInfo
  ///   （避免把 `?token=...` 一起分享出去）。`bgmTitle`/`bgmArtist` 是用户
  ///   可见的展示文案，不含路径，予以保留。
  /// - `sourceShareId`：不外传，避免多次转发形成溯源链。
  Map<String, dynamic> toShareJson() {
    final Map<String, dynamic> json = toJson();
    json['soundscapePath'] = null;
    json['sourceShareId'] = null;
    if (isLocalPathLike(musicSourceId) || (musicSourceId?.startsWith('dir:') ?? false)) {
      json['musicSourceId'] = null;
    }
    json['bgmUri'] = _shareSafeUri(bgmUri);
    return json;
  }

  /// 远端 URL 去凭据；本机路径一律丢弃。
  static String? _shareSafeUri(String? uri) {
    if (uri == null || uri.isEmpty) return null;
    if (isLocalPathLike(uri)) return null;
    try {
      final Uri u = Uri.parse(uri);
      if (!u.hasScheme || u.scheme == 'file') return null;
      return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null, path: u.path)
          .toString();
    } catch (_) {
      return null;
    }
  }

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
      // v2 新字段：缺失即默认（向后兼容 R-02）
      visible: json['visible'] as bool? ?? true,
      bgmUri: json['bgmUri'] as String?,
      bgmTitle: json['bgmTitle'] as String?,
      bgmArtist: json['bgmArtist'] as String?,
      sourceShareId: json['sourceShareId'] as String?,
      voxelCapture: json['voxelCapture'] != null
          ? VoxelSceneCapture.fromJson(json['voxelCapture'] as Map<String, dynamic>)
          : null,
      // #167：场景专属白噪音（缺失即全局默认，向后兼容 R-02）
      whiteNoise: json['whiteNoise'] as bool? ?? false,
      whiteNoiseVolume:
          (json['whiteNoiseVolume'] as num?)?.toDouble() ?? 0.15,
    );
  }
}
