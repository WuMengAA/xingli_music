/// R26d：HUD 元素自定义位置（布局编辑）。
///
/// 3D 世界内部分浮动 HUD（坐标 / 摇杆 / 右侧动作按钮）的位置可自定义，
/// 以**归一化坐标（0~1 相对视口）**存储，随视口大小缩放，竖屏/横屏都稳。
/// 核心元素（顶部控制条 / 底部物品栏 / 退出 / 标题）锁定不参与。
///
/// 持久化：Settings 的 SharedPreferences（键 [kHudLayoutKey]），JSON 结构
/// `{ "<elementId>": {"x": 0.1, "y": 0.8}, ... }`。
library;

import 'dart:convert' show JsonDecoder, JsonEncoder;
import 'dart:ui' show Offset;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HUD 布局持久化键（设置仓库同区）。
const String kHudLayoutKey = 'voxel_hud_layout';

/// HUD 缩放持久化键（摇杆 / 动作键整体放大倍率）。
const String kHudScaleKey = 'voxel_hud_scale';

/// HUD 缩放允许范围（0.8~1.4）。
const double kHudScaleMin = 0.8;
const double kHudScaleMax = 1.4;

/// 当前 HUD 自定义位置表：elementId → 归一化位置（x,y ∈ 0~1）。
/// 未在表内的元素用代码里的默认位置。
final hudLayoutProvider =
    StateProvider<Map<String, Offset>>((ref) => <String, Offset>{});

/// HUD 缩放倍率（摇杆 / 动作键整体大小；默认 1.0，允许 0.8~1.4）。
final hudScaleProvider = StateProvider<double>((ref) => 1.0);

/// 屏幕自适应基准缩放：基于视口短边相对参考尺寸（420dp）的比例，
/// 让游戏 HUD 控件在手机 / 平板、竖屏 / 横屏下都保持合适大小
/// （与手动档位 [hudScaleProvider] 叠加，共同决定实际缩放）。
///
/// - 平板（短边 >700）→ 放大；小屏手机（<360）→ 缩小；范围夹紧 [0.8, 1.35]。
double hudResponsiveScale(BuildContext context) {
  final double shortest = MediaQuery.of(context).size.shortestSide;
  final double s = shortest / 420; // 参考 420dp（典型手机宽）
  return s.clamp(0.8, 1.35);
}

/// HUD 布局编辑模式（开启后浮动元素显示边框、可拖动；关闭自动保存）。
final hudEditProvider = StateProvider<bool>((ref) => false);

/// 从 prefs 加载 HUD 布局（App 启动 / 视图 init 时调用）。
Future<void> loadHudLayout(SharedPreferences prefs) async {
  // 由 prefsProvider 持有者调用，这里不直接 getInstance
}

/// 把 HUD 布局写回 prefs。
Future<void> saveHudLayout(
  SharedPreferences prefs,
  Map<String, Offset> layout,
) async {
  final Map<String, dynamic> json = <String, dynamic>{
    for (final MapEntry<String, Offset> e in layout.entries)
      e.key: <String, dynamic>{'x': e.value.dx, 'y': e.value.dy},
  };
  await prefs.setString(kHudLayoutKey, const JsonEncoder().convert(json));
}

/// 从 prefs 读 HUD 布局（返回空表 = 未自定义）。
Map<String, Offset> readHudLayout(SharedPreferences prefs) {
  final String? raw = prefs.getString(kHudLayoutKey);
  if (raw == null || raw.isEmpty) return <String, Offset>{};
  try {
    final dynamic parsed = const JsonDecoder().convert(raw);
    if (parsed is! Map<String, dynamic>) return <String, Offset>{};
    return <String, Offset>{
      for (final MapEntry<String, dynamic> e in parsed.entries)
        if (e.value is Map<String, dynamic> &&
            (e.value['x'] is num) &&
            (e.value['y'] is num))
          e.key: Offset(
            ((e.value['x'] as num).toDouble()).clamp(0.0, 1.0),
            ((e.value['y'] as num).toDouble()).clamp(0.0, 1.0),
          ),
    };
  } catch (_) {
    return <String, Offset>{};
  }
}

/// 把 HUD 缩放写回 prefs。
Future<void> saveHudScale(SharedPreferences prefs, double scale) async {
  await prefs.setDouble(
    kHudScaleKey,
    scale.clamp(kHudScaleMin, kHudScaleMax),
  );
}

/// 从 prefs 读 HUD 缩放（缺省 1.0，越界夹紧到允许范围）。
double readHudScale(SharedPreferences prefs) {
  final double? v = prefs.getDouble(kHudScaleKey);
  if (v == null) return 1.0;
  return v.clamp(kHudScaleMin, kHudScaleMax);
}

/// HUD 元素 id 常量（避免散字符串）。
abstract final class HudIds {
  /// 第一人称坐标 HUD（可拖动）。
  static const String coords = 'coords';

  /// 摇杆 / LiftPad（可拖动）。
  static const String joystick = 'joystick';

  /// 右侧动作按钮（攻击/放置/跳，可拖动）。
  /// R26skel-b3：动作键拆成 4 个独立元素（各自可拖拽调位），
  /// 旧「actions」整体簇 id 保留仅供旧布局迁移读取，不再渲染。
  static const String actions = 'actions';

  /// 动作键 · 攻击/挖掘（独立可拖动）。
  static const String actBreak = 'actBreak';

  /// 动作键 · 放置/使用（独立可拖动）。
  static const String actPlace = 'actPlace';

  /// 动作键 · 蹲/降（独立可拖动）。
  static const String actDuck = 'actDuck';

  /// 动作键 · 跳/升（独立可拖动）。
  static const String actJump = 'actJump';

  /// P2：折叠面板（坐标/模式等次级控制）——可拖拽防与顶栏重叠。
  static const String foldPanel = 'foldPanel';

  /// R26h：左上「信息显示」面板（存档名/种子/坐标/群系/时间/累计游玩时长）。
  /// 可拖拽防与顶栏/音乐卡重叠。
  static const String worldInfo = 'worldInfo';

  /// R26c：疾跑按钮（触屏切换 _sprinting；键盘 Ctrl 仍可用）。
  /// 可拖拽，默认置于左下摇杆旁。
  static const String sprint = 'sprint';
}
