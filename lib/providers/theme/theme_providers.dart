import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/theme_skins.dart';
import '../mood/mood_providers.dart';

/// 用户主色（默认星夜 #4A3A8A）
final primaryColorProvider = StateProvider<Color>(
  (ref) => const Color(0xFF4A3A8A),
);

/// 是否自定义主色（false 表示用预设色块）
final customColorProvider = StateProvider<Color?>((ref) => null);

/// 调色盘面板开合
final paletteOpenProvider = StateProvider<bool>((ref) => false);

/// 当前生效主色（预设或自定义）
final effectivePrimaryProvider = Provider<Color>((ref) {
  return ref.watch(customColorProvider) ?? ref.watch(primaryColorProvider);
});

/// 完整派生配色（含心情叠加）
final derivedPaletteProvider = Provider<DerivedPalette>((ref) {
  final Color primary = ref.watch(effectivePrimaryProvider);
  final String mood = ref.watch(moodKindProvider);
  return DerivedPalette.from(primary).withMood(mood);
});

// ════════════════════════════════════════════════════════════════════════
// R16 主题系统：浅色 / 深色 / 跟随系统 + 多套皮肤
// ════════════════════════════════════════════════════════════════════════

/// 主题模式（字符串持久化：light / dark / system）。
/// 默认「清新·浅色」（启动即浅色，画布观感对应 starlight 皮肤）。
final themeModeNameProvider = StateProvider<String>((ref) => 'light');

/// 当前主题模式（映射为 Material ThemeMode）。
final themeModeProvider = Provider<ThemeMode>((ref) {
  return switch (ref.watch(themeModeNameProvider)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

/// 皮肤 id（字符串持久化）。见 [ThemeSkins] 常量表。
final themeSkinProvider = StateProvider<String>((ref) => 'starlight');

/// 当前皮肤主色（找不到回退星璃紫）。
final themeSkinColorProvider = Provider<Color>((ref) {
  final String id = ref.watch(themeSkinProvider);
  return ThemeSkins.byId(id)?.primary ?? ThemeSkins.starlight.primary;
});
