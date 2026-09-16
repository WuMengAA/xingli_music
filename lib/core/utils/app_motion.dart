import 'package:flutter/material.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 全局动效令牌（R32 批2 · 丝滑可被打断的过渡动画框架）
/// ════════════════════════════════════════════════════════════════════════
///
/// 统一收口过渡动画的时长与曲线，避免各处魔法数字；所有页面/组件转场
/// 复用 [AppMotion]，保证「同一套手感」。
///
/// **可被打断**：基于 [PageRouteBuilder] / [Hero] 的框架级动画，pop 中途
/// 触发新交互时，动画会平滑反向/接管（原生支持），无需手写中断逻辑。
class AppMotion {
  AppMotion._();

  /// 进入动画时长：播放栏 → 正在播放，略长以铺陈「上展 + 缩放 + 淡入」。
  static const Duration pageEnter = Duration(milliseconds: 440);

  /// 退出动画时长：稍短，回退更利落。
  static const Duration pageExit = Duration(milliseconds: 340);

  static const Curve pageCurve = Curves.easeOutExpo;
  static const Curve reverseCurve = Curves.easeInExpo;
}

/// 播放栏 ↔ 沉浸播放器 的共享 Hero tag 常量。
///
/// 封面与标题各自独立 tag，避免 [Hero] 误配；见 [UnifiedPlayer] 与主页
/// [HomeImmersivePlayer] 的包裹点。整页 [NowPlayingPage] 已于 2026-09-16
/// 彻底移除，Hero 目标页不复存在——tag 仅作占位，点击信息区不再触发转场。
class NpHeroTags {
  NpHeroTags._();
  static const String cover = 'npCover';
  static const String title = 'npCoverTitle';

  /// 整卡放大过渡 tag：包住播放栏**整张卡片**（[UnifiedPlayer] 紧凑态）与
  /// 正在播放页**整页主体**，使点开播放页时整卡随封面一起放大（而非仅封面
  /// 位移、其余硬切）。与封面/标题 Hero 并存，各 tag 独立飞行。
  static const String card = 'npCard';
}
