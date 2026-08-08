import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 星璃音乐空间统一图标集
///
/// 来源：game-icon-pack（CC0 公有领域，可自由使用）
/// 全部为单色 `currentColor` SVG，可任意着色。
class AppIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;

  const AppIcon(this.name, {super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}

/// 图标名常量（避免字符串魔法值）
abstract final class AppIcons {
  // 播放控制
  static const String play = 'play';
  static const String pause = 'pause';
  static const String previous = 'previous';
  static const String next = 'next';

  // 面板功能
  static const String music = 'music';
  static const String bookmark = 'bookmark';
  static const String refresh = 'refresh';
  static const String clock = 'clock';
  static const String settings = 'settings';
  static const String volume = 'volume';
  static const String volumeMute = 'volume_mute';
  static const String block = 'block';

  // 场景
  static const String star = 'star';
  static const String rain = 'rain';
  static const String forest = 'forest';
  static const String fire = 'fire';
  static const String sun = 'sun';
  static const String snowflake = 'snowflake';
  static const String sea = 'sea';
  static const String mountain = 'mountain';
}
