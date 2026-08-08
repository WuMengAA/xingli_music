import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前情绪权重（0..1）
///
/// 决定背景色与场景基础色的混合程度。
/// 第一版：默认平静（0.4），后续由心情选择联动。
final moodWeightProvider = StateProvider<double>((ref) => 0.4);

/// 当前情绪类型（对应 [DesignTokens.moodColors] 的键）
final moodKindProvider = StateProvider<String>((ref) => 'calm');
