library;

/// ════════════════════════════════════════════════════════════════════════
/// AI 陪伴 · 可执行动作模型（L 域）
/// ════════════════════════════════════════════════════════════════════════
///
/// 这是"AI 小人接入 AI、AI 可以理解并快速操作"的核心数据契约：
/// 陪伴内核把用户的自然语言**离线**派生出一组 [CompanionAction]，
/// 由体素世界视图逐帧落地（走位、转镜头、控音效）。
///
/// 刻意保持"小事"边界（符合陌生人设定）：只做世界中无关紧要的动作，
/// 不构成控制欲、不替用户做破坏性决定。

import 'package:flutter/foundation.dart';

/// 动作类型。
enum CompanionActionKind {
  /// 把体素小人走到某地标。
  moveFigure,

  /// 转动世界镜头，对准某地标。
  focusCamera,

  /// 让镜头缓缓转一圈（看一圈风景）。
  orbitCamera,

  /// 开 / 关世界内空间音效（不碰主播放器）。
  toggleWorldAudio,
}

/// 世界中可抵达 / 可对准的地标。
enum CompanionLandmark {
  /// 世界中心（小人初始站位，也是"回去"的目标）。
  center,

  /// 水面（湖 / 河）。
  water,

  /// 树林 / 树下。
  tree,

  /// 山顶（最高点）。
  mountain,

  /// 篝火（Phase 3 预留地物；当前世界未生成时回落到中心）。
  fire,
}

/// 单条可执行动作。
@immutable
class CompanionAction {
  const CompanionAction({
    required this.kind,
    this.landmark,
    this.enabled,
    this.label,
  });

  /// 动作类型。
  final CompanionActionKind kind;

  /// 地标类动作的目标（[moveFigure] / [focusCamera] 用）。
  final CompanionLandmark? landmark;

  /// [toggleWorldAudio] 的目标状态（true 开 / false 关）。
  final bool? enabled;

  /// 人类可读说明（用于 UI 快捷指令、系统旁白）。
  final String? label;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        if (landmark != null) 'landmark': landmark!.name,
        if (enabled != null) 'enabled': enabled,
        if (label != null) 'label': label,
      };

  factory CompanionAction.fromJson(Map<String, dynamic> json) {
    final CompanionLandmark? lm = json['landmark'] == null
        ? null
        : CompanionLandmark.values.firstWhere(
            (CompanionLandmark e) => e.name == json['landmark'],
            orElse: () => CompanionLandmark.center,
          );
    return CompanionAction(
      kind: CompanionActionKind.values.firstWhere(
        (CompanionActionKind e) => e.name == json['kind'],
        orElse: () => CompanionActionKind.moveFigure,
      ),
      landmark: lm,
      enabled: json['enabled'] as bool?,
      label: json['label'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanionAction &&
          other.kind == kind &&
          other.landmark == landmark &&
          other.enabled == enabled &&
          other.label == label;

  @override
  int get hashCode =>
      Object.hash(kind, landmark, enabled, label);

  /// 地标中文名（用于系统旁白 / 快捷指令标签）。
  static String labelOf(CompanionLandmark lm) => switch (lm) {
        CompanionLandmark.center => '中心',
        CompanionLandmark.water => '水边',
        CompanionLandmark.tree => '树下',
        CompanionLandmark.mountain => '山顶',
        CompanionLandmark.fire => '篝火旁',
      };
}
