import 'package:flutter/material.dart';

/// 实验项状态（v2 M2 · P0-M2-2 / P0-M2-4）。
enum ExperimentStatus {
  /// 实验中：可进入，标注不稳定。
  experimenting,

  /// 稳定：可进入。
  stable,

  /// 已下线：置灰 + 禁止进入（P0-M2-4）。
  retired,
}

/// 实验清单中的单个实验项（数据驱动配置，不硬编码在 UI）。
///
/// 依据架构 §3.1 / §7.6：`experimentsProvider` 静态配置表，
/// 每项 = id / 名称 / 简介 / 图标 / 状态 / 默认启用 / 页面构造器。
class ExperimentItem {
  const ExperimentItem({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.status,
    required this.builder,
    this.enabledByDefault = true,
  });

  /// 唯一 id（设置「逐项启停」与持久化 enabled 表的 key）。
  final String id;

  /// 展示名称。
  final String name;

  /// 一句话简介。
  final String description;

  /// 图标（Material Icons）。
  final IconData icon;

  /// 状态徽标来源。
  final ExperimentStatus status;

  /// 是否默认启用（首次同意后默认开；可在设置实验管理中关闭）。
  final bool enabledByDefault;

  /// 实验页构造器（全屏路由进入）。
  final Widget Function() builder;

  /// 状态 → 文案（与 [StateChip] 语义一致）。
  String get statusLabel => switch (status) {
        ExperimentStatus.experimenting => '实验中',
        ExperimentStatus.stable => '稳定',
        ExperimentStatus.retired => '已下线',
      };
}

/// 实验同意状态（持久化 JSON：`{agreed, enabled:{id: bool}}`）。
///
/// - `agreed`：是否同意进入实验场所（P0-M2-1）。
/// - `enabled`：逐项启停表（P1-M2-5）；未列出的项取 `enabledByDefault`。
class ExperimentConsent {
  const ExperimentConsent({required this.agreed, required this.enabled});

  /// 是否同意（`false` 时永不渲染实验项列表）。
  final bool agreed;

  /// 逐项启停表（key = 实验 id）。
  final Map<String, bool> enabled;

  const ExperimentConsent.initial()
      : agreed = false,
        enabled = const <String, bool>{};

  ExperimentConsent copyWith({bool? agreed, Map<String, bool>? enabled}) {
    return ExperimentConsent(
      agreed: agreed ?? this.agreed,
      enabled: enabled ?? this.enabled,
    );
  }

  /// 查询某个实验是否启用：显式配置优先，否则用默认值。
  bool isEnabled(ExperimentItem item) =>
      enabled[item.id] ?? item.enabledByDefault;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'agreed': agreed,
        'enabled': enabled,
      };

  factory ExperimentConsent.fromJson(Map<String, dynamic> json) {
    return ExperimentConsent(
      agreed: json['agreed'] as bool? ?? false,
      enabled: (json['enabled'] as Map<String, dynamic>?)
              ?.map((String k, dynamic v) => MapEntry(k, v as bool)) ??
          const <String, bool>{},
    );
  }
}
