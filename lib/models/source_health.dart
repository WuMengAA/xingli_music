/// 音源健康状态（v2 M4 · P1-M4-4）。
enum SourceHealthStatus {
  /// 连接中（测试请求已发出，未返回）。
  connecting,

  /// 连接正常。
  ok,

  /// 连接失败。
  failed,

  /// 未知（未测试过）。
  unknown,
}

/// 单个音源的健康状态（测试结果 + 上次测试时间 + 错误详情）。
///
/// 架构 §3.1：`sourceHealthProvider` 为 `Map<String, SourceHealth>`，
/// key = 音源配置名（本地目录用 path，服务器用 name）。
class SourceHealth {
  const SourceHealth({
    this.status = SourceHealthStatus.unknown,
    this.lastTestedAt,
    this.errorDetail,
  });

  final SourceHealthStatus status;
  final DateTime? lastTestedAt;
  final String? errorDetail;

  SourceHealth copyWith({
    SourceHealthStatus? status,
    DateTime? lastTestedAt,
    String? errorDetail,
    bool clearError = false,
  }) {
    return SourceHealth(
      status: status ?? this.status,
      lastTestedAt: lastTestedAt ?? this.lastTestedAt,
      errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
    );
  }

  /// 状态 → 文案。
  String get statusLabel => switch (status) {
        SourceHealthStatus.connecting => '连接中',
        SourceHealthStatus.ok => '正常',
        SourceHealthStatus.failed => '失败',
        SourceHealthStatus.unknown => '未测试',
      };

  /// 上次测试时间的展示文案（`--` 表示从未测试）。
  String get lastTestedLabel {
    final DateTime? t = lastTestedAt;
    if (t == null) return '--';
    final String hh = t.hour.toString().padLeft(2, '0');
    final String mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
