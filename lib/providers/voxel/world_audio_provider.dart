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
