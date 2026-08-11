import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/source_health.dart';

/// 音源健康状态表（v2 M4 · P1-M4-4）。
///
/// key = 音源配置名（本地目录用 path，服务器用 name）。
/// 测试时置 `connecting` → 结果 `ok/failed` + `lastTestedAt`。
final StateNotifierProvider<SourceHealthNotifier, Map<String, SourceHealth>>
    sourceHealthProvider =
    StateNotifierProvider<SourceHealthNotifier, Map<String, SourceHealth>>(
  (Ref ref) => SourceHealthNotifier(),
);

class SourceHealthNotifier extends StateNotifier<Map<String, SourceHealth>> {
  SourceHealthNotifier() : super(const <String, SourceHealth>{});

  /// 标记开始测试（connecting）。
  void startTest(String key) {
    state = Map<String, SourceHealth>.of(state)
      ..[key] = SourceHealth(status: SourceHealthStatus.connecting);
  }

  /// 标记成功。
  void markOk(String key) {
    state = Map<String, SourceHealth>.of(state)
      ..[key] = SourceHealth(
        status: SourceHealthStatus.ok,
        lastTestedAt: DateTime.now(),
      );
  }

  /// 标记失败（附错误详情，P2-M4-5）。
  void markFailed(String key, {String? detail}) {
    state = Map<String, SourceHealth>.of(state)
      ..[key] = SourceHealth(
        status: SourceHealthStatus.failed,
        lastTestedAt: DateTime.now(),
        errorDetail: detail,
      );
  }

  /// 清除某个条目的健康状态（如删除音源后）。
  void remove(String key) {
    final Map<String, SourceHealth> next = Map<String, SourceHealth>.of(state)
      ..remove(key);
    state = next;
  }

  /// 查询单个状态。
  SourceHealth healthOf(String key) =>
      state[key] ?? const SourceHealth(status: SourceHealthStatus.unknown);
}
