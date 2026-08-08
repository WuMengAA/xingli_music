import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/palette.dart';
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
