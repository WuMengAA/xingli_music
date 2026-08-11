/// ════════════════════════════════════════════════════════════════════════
/// 主题皮肤表（R16：多套皮肤）
/// ════════════════════════════════════════════════════════════════════════
///
/// 每套皮肤定义品牌主色（浅色/深色主题的主强调色）。
/// 皮肤 id 持久化到 prefs（`themeSkin`）。
library;

import 'package:flutter/material.dart';
/// 一套皮肤。
@immutable
class ThemeSkin {
  const ThemeSkin({required this.id, required this.name, required this.primary});

  /// 持久化 id（英文小写）。
  final String id;

  /// 展示名。
  final String name;

  /// 主强调色。
  final Color primary;
}

/// 内置皮肤集合。
abstract final class ThemeSkins {
  /// 星璃紫（默认，对应 AppColors.accent #7C6BFF）
  static const ThemeSkin starlight = ThemeSkin(
    id: 'starlight',
    name: '星璃紫',
    primary: Color(0xFF7C6BFF),
  );

  /// 星夜蓝
  static const ThemeSkin night = ThemeSkin(
    id: 'night',
    name: '星夜蓝',
    primary: Color(0xFF4A7BFF),
  );

  /// 深海青
  static const ThemeSkin ocean = ThemeSkin(
    id: 'ocean',
    name: '深海青',
    primary: Color(0xFF2BA8A0),
  );

  /// 森林绿
  static const ThemeSkin forest = ThemeSkin(
    id: 'forest',
    name: '森林绿',
    primary: Color(0xFF3BA776),
  );

  /// 暖阳橙
  static const ThemeSkin sunset = ThemeSkin(
    id: 'sunset',
    name: '暖阳橙',
    primary: Color(0xFFE08A3C),
  );

  /// 玫红
  static const ThemeSkin rose = ThemeSkin(
    id: 'rose',
    name: '玫红',
    primary: Color(0xFFE05B8A),
  );

  /// 全部皮肤（设置页选择用）。
  static const List<ThemeSkin> all = <ThemeSkin>[
    starlight,
    night,
    ocean,
    forest,
    sunset,
    rose,
  ];

  /// 按 id 查找（找不到返回 null）。
  static ThemeSkin? byId(String id) {
    for (final ThemeSkin s in all) {
      if (s.id == id) return s;
    }
    return null;
  }
}
