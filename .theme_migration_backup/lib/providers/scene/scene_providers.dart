import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scene.dart';
import '../session/session_providers.dart';
import 'scene_custom_providers.dart';

/// 内置场景（7 个，与 web 原型对齐）
const List<Scene> builtInScenes = <Scene>[
    Scene(
      id: 'starnight',
      name: '星夜',
      mood: '静默',
      desc: '远处有微光，呼吸缓慢',
      track: 'Lunar Drift',
      artist: 'Stelarith',
      soundscape: '无底噪 · 星光流动',
      icon: 'star',
      visual: SceneVisual(
        gradientColors: [Color(0xFF0D0B1A), Color(0xFF1F1838)],
        stops: [0.2, 1.0],
        accent: Color(0xFFF5D98F),
        glyph: '✦',
      ),
      visualWeight: 0.8,
      valence: 0.45,
      energy: 0.12,
    ),
    Scene(
      id: 'rain',
      name: '雨',
      mood: '湿润',
      desc: '窗玻璃上的水珠缓慢滑落',
      track: 'Rain Patterns',
      artist: 'Ambient Lab',
      soundscape: '雨声 · 低频嗡鸣',
      icon: 'rain',
      visual: SceneVisual(
        gradientColors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        stops: [0.2, 1.0],
        accent: Color(0xFF7B9BFF),
        glyph: '❖',
      ),
      visualWeight: 0.75,
      valence: 0.35,
      energy: 0.25,
    ),
    Scene(
      id: 'forest',
      name: '森林',
      mood: '呼吸',
      desc: '树影间的光斑轻轻晃动',
      track: 'Moss & Light',
      artist: 'Forest Echo',
      soundscape: '风声 · 鸟鸣（低频）',
      icon: 'forest',
      visual: SceneVisual(
        gradientColors: [Color(0xFF0F1A0F), Color(0xFF1A2E1A)],
        stops: [0.2, 1.0],
        accent: Color(0xFF7BFF9B),
        glyph: '☘',
      ),
      visualWeight: 0.85,
      valence: 0.60,
      energy: 0.35,
    ),
    Scene(
      id: 'fireplace',
      name: '壁炉',
      mood: '温暖',
      desc: '木柴在火中缓慢裂开',
      track: 'Ember Glow',
      artist: 'Hearth Tone',
      soundscape: '火焰噼啪声',
      icon: 'fire',
      visual: SceneVisual(
        gradientColors: [Color(0xFF2E1A0F), Color(0xFF5A2E1A)],
        stops: [0.2, 1.0],
        accent: Color(0xFFFF9B5A),
        glyph: '✦',
      ),
      visualWeight: 0.8,
      valence: 0.75,
      energy: 0.5,
    ),
    Scene(
      id: 'dusk',
      name: '黄昏',
      mood: '余晖',
      desc: '天边最后一道光缓缓沉入山脊',
      track: 'Dusk Chime',
      artist: 'Golden Hour',
      soundscape: '风声 · 远处蝉鸣',
      icon: 'sun',
      visual: SceneVisual(
        gradientColors: [Color(0xFF2E1A2E), Color(0xFF5A3A1A)],
        stops: [0.2, 1.0],
        accent: Color(0xFFFFB87B),
        glyph: '☀',
      ),
      visualWeight: 0.9,
      valence: 0.55,
      energy: 0.4,
    ),
    Scene(
      id: 'snow',
      name: '雪',
      mood: '寂静',
      desc: '白色的世界，声音被吸走了',
      track: 'Falling Slow',
      artist: 'Winter Drift',
      soundscape: '风 · 高频减弱',
      icon: 'snowflake',
      visual: SceneVisual(
        gradientColors: [Color(0xFF1A1A2E), Color(0xFF2E2E3E)],
        stops: [0.2, 1.0],
        accent: Color(0xFFE0E8F0),
        glyph: '❄',
      ),
      visualWeight: 0.7,
      valence: 0.4,
      energy: 0.1,
      musicSourceId: 'minecraft',
    ),
    Scene(
      id: 'ocean',
      name: '海底',
      mood: '深邃',
      desc: '光在水波中弯曲',
      track: 'Abyssal Glow',
      artist: 'Deep Current',
      soundscape: '水声 · 低频嗡鸣',
      icon: 'sea',
      visual: SceneVisual(
        gradientColors: [Color(0xFF0A1628), Color(0xFF0F2040)],
        stops: [0.2, 1.0],
        accent: Color(0xFF4A9BFF),
        glyph: '〰',
      ),
      visualWeight: 0.85,
      valence: 0.3,
      energy: 0.2,
      musicSourceId: 'minecraft',
    ),
];

/// 场景全集：内置场景 + 用户自定义/覆盖场景。
///
/// - 自定义场景（id 以 'custom_' 开头）追加到末尾
/// - 内置场景若有自定义覆盖（同 id），用覆盖副本替换原场景
final scenesProvider = Provider<List<Scene>>((ref) {
  final List<Scene> customs = ref.watch(customScenesProvider);
  if (customs.isEmpty) return builtInScenes;

  final Map<String, Scene> overrides = {
    for (final Scene c in customs)
      if (!c.isCustom) c.id: c,
  };
  final List<Scene> result = builtInScenes
      .map((s) => overrides.containsKey(s.id) ? overrides[s.id]! : s)
      .toList();
  // 追加纯新增的自定义场景
  result.addAll(customs.where((c) => c.isCustom));
  return result;
});

/// 当前场景索引
final currentSceneIndexProvider = StateProvider<int>((_) => 0);

/// 当前激活场景（由索引 + 会话顺序派生）
final activeSceneProvider = Provider<Scene>((ref) {
  final int index = ref.watch(currentSceneIndexProvider);
  final List<Scene> scenes = ref.watch(sceneOrderProvider);
  return scenes[index.clamp(0, scenes.length - 1)];
});
