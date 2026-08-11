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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HUD 布局持久化键（设置仓库同区）。
const String kHudLayoutKey = 'voxel_hud_layout';

/// 当前 HUD 自定义位置表：elementId → 归一化位置（x,y ∈ 0~1）。
/// 未在表内的元素用代码里的默认位置。
final hudLayoutProvider =
    StateProvider<Map<String, Offset>>((ref) => <String, Offset>{});

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

/// HUD 元素 id 常量（避免散字符串）。
abstract final class HudIds {
  /// 第一人称坐标 HUD（可拖动）。
  static const String coords = 'coords';

  /// 摇杆 / LiftPad（可拖动）。
  static const String joystick = 'joystick';

  /// 右侧动作按钮（攻击/放置/跳，可拖动）。
  static const String actions = 'actions';
}
