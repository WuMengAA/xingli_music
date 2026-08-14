/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 · 空间音效开关（Phase 3 · AI 可控制）
/// ════════════════════════════════════════════════════════════════════════
///
/// 仅控制**世界内**空间音效（水 / 叶 / 鸟 / 风）的启停，不影响主音乐播放器。
/// AI 陪伴可通过 [CompanionActionKind.toggleWorldAudio] 翻转它。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 世界内空间音效是否启用（默认开）。
final StateProvider<bool> worldAudioEnabledProvider =
    StateProvider<bool>((Ref ref) => true);

/// H2：主页「游戏背景」开关——叠加体素取景背景（默认开）；关掉则回退
/// 到场景原有深色渐变背景。
final StateProvider<bool> voxelBgEnabledProvider =
    StateProvider<bool>((Ref ref) => true);

/// H2：主页游戏背景「实时渲染」强制开关（默认 false = 跟随全局性能模式）；
/// 长按背景开关开启后，即使省电/性能档也实时渲染（不再退化静态帧）。
final StateProvider<bool> voxelBgLiveProvider =
    StateProvider<bool>((Ref ref) => false);
