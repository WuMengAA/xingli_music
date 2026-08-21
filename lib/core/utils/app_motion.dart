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

/// 播放栏 → 正在播放 的共享元素转场路由。
///
/// 进入：页面自底部微微上展（slideUp）+ 轻微放大（scale 0.94→1.0）+ 淡入，
/// 营造「背景微向上展开至全屏、模糊过渡进入」的观感；封面/文字的曲线位移
/// 由 [Hero]（见 [UnifiedPlayer.heroTag] / [NowPlayingPage] 的 tag）负责。
///
/// 退出（pop）反向平滑动画；动画进行中再次触发会被新动画平滑接管
/// （[PageRouteBuilder] 原生支持，故天然可打断）。
class NowPlayingRoute extends PageRouteBuilder<Widget> {
  NowPlayingRoute({required this.page})
      : super(
          opaque: true,
          fullscreenDialog: false,
          transitionDuration: AppMotion.pageEnter,
          reverseTransitionDuration: AppMotion.pageExit,
          pageBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) =>
              page,
          transitionsBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            final CurvedAnimation curved = CurvedAnimation(
              parent: animation,
              curve: AppMotion.pageCurve,
            );
            final Animation<Offset> slide = Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).chain(CurveTween(curve: AppMotion.pageCurve)).animate(curved);
            final Animation<double> scale =
                Tween<double>(begin: 0.94, end: 1.0).animate(curved);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: slide,
                child: ScaleTransition(
                  scale: scale,
                  child: child,
                ),
              ),
            );
          },
        );

  final Widget page;
}

/// 播放栏 ↔ 正在播放 的共享 Hero tag 常量。
///
/// 封面与标题各自独立 tag，避免 [Hero] 误配；见 [UnifiedPlayer] 与
/// [NowPlayingPage] 的包裹点。
class NpHeroTags {
  NpHeroTags._();
  static const String cover = 'npCover';
  static const String title = 'npCoverTitle';
}
