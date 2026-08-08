import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/storage/storage_providers.dart';
import '../../services/color_memory_service.dart';
import '../session/session_providers.dart';

export '../../providers/storage/storage_providers.dart';

/// 配色记忆服务（同步，可直接读取）
final colorMemoryServiceProvider = Provider<ColorMemoryService>(
  (ref) => ColorMemoryService(ref.watch(storageServiceProvider)),
);

/// 当前配色的总色相偏移（度）
///
/// = 记忆偏移（由使用行为决定，长期稳定）
///   + 会话抖动（每次打开不同，短期波动）
/// 结果：方向是"有记忆"的，量是"每次略有不同"的。
final colorShiftProvider = Provider<double>((ref) {
  final double bias = ref.watch(colorMemoryServiceProvider).biasDegrees;
  final int seed = ref.watch(sessionSeedProvider);

  // 会话抖动：-6 ~ +6 度，由会话种子派生
  final double jitter = (seed % 41) / 41.0 * 12.0 - 6.0;

  return (bias + jitter) % 360.0;
});
