import 'dart:math';

import 'package:flutter/material.dart';

import '../models/scene.dart';
import 'app_icon.dart';

/// 灵动小球：所有交互围绕它展开。
///
/// - 点击：播放/暂停
/// - 左右滑动（小球区域）：切换歌曲
/// - 上划：调出「更多面板」
/// - 播放中脉动，颜色受心情影响
///
/// 长按拖拽吸附暂未实现（需要全局坐标追踪，后续版本）。
class StelarithOrb extends StatefulWidget {
  final Scene currentScene;
  final bool isPlaying;
  final String activeMood;
  final VoidCallback onTap;
  final VoidCallback onSwipeNext;
  final VoidCallback onSwipePrev;
  final VoidCallback onSwipeUp;

  const StelarithOrb({
    super.key,
    required this.currentScene,
    required this.isPlaying,
    required this.activeMood,
    required this.onTap,
    required this.onSwipeNext,
    required this.onSwipePrev,
    required this.onSwipeUp,
  });

  @override
  State<StelarithOrb> createState() => _StelarithOrbState();
}

class _StelarithOrbState extends State<StelarithOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isPlaying) _pulseCtrl.repeat();
  }

  @override
  void didUpdateWidget(covariant StelarithOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _pulseCtrl.repeat();
      } else {
        _pulseCtrl.stop();
        _pulseCtrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color _moodColor() {
    return switch (widget.activeMood) {
      '愉悦' => const Color(0xFFFFB05A),
      '平静' => const Color(0xFF9B7BFF),
      '低落' => const Color(0xFF4A7BFF),
      '兴奋' => const Color(0xFFFF7BFF),
      _ => widget.currentScene.visual.accent,
    };
  }

  @override
  Widget build(BuildContext context) {
    final Color orbColor = _moodColor();

    return GestureDetector(
      onTap: widget.onTap,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -200) {
          widget.onSwipeNext();
        } else if (details.primaryVelocity! > 200) {
          widget.onSwipePrev();
        }
      },
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < -300) {
          widget.onSwipeUp();
        }
      },
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, child) {
          final double pulse = widget.isPlaying
              ? 1.0 + sin(_pulseCtrl.value * 2 * pi) * 0.06
              : 1.0;

          return Transform.scale(
            scale: pulse,
            child: child,
          );
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.2, -0.2),
              colors: [
                Colors.white.withValues(alpha: 0.15),
                orbColor.withValues(alpha: 0.15),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: orbColor.withValues(alpha: widget.isPlaying ? 0.15 : 0.08),
                blurRadius: widget.isPlaying ? 50 : 30,
              ),
            ],
          ),
          child: Center(
            child: AppIcon(
              widget.isPlaying ? AppIcons.pause : AppIcons.play,
              size: 20,
              color: Colors.white.withValues(
                alpha: widget.isPlaying ? 0.7 : 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
