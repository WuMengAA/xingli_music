import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../providers/audio/audio_providers.dart';

/// 上滑音量按钮后出现的独立声音设置条：音乐声 / 背景声 分离。
/// 打开后 3 秒无操作自动收起；任何音量交互都会重置计时。
class VolumeSlider extends ConsumerStatefulWidget {
  final double safeBottom;
  const VolumeSlider({super.key, required this.safeBottom});

  @override
  ConsumerState<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends ConsumerState<VolumeSlider> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        ref.read(volumeSliderOpenProvider.notifier).state = false;
      }
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// 记录一次音量交互（重置 3 秒计时）
  void _tick() {
    ref.read(volumeActivityProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final bool open = ref.watch(volumeSliderOpenProvider);
    // 打开时启动计时；关闭时取消
    ref.listen(volumeSliderOpenProvider, (prev, next) {
      if (next) {
        _restart();
      } else {
        _cancel();
      }
    });
    // 任意音量交互重置计时
    ref.listen(volumeActivityProvider, (prev, next) {
      if (open) _restart();
    });

    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    const double barH = 128.0;
    const double panelH = barH + 30;
    // 面板宽度随屏幕自适应：宽屏更宽，窄屏不溢出
    final double screenW = MediaQuery.of(context).size.width;
    final double panelW = (screenW * 0.5).clamp(220.0, 360.0);
    // 音量按钮中心：随 dock 自适应高度推算（与 control_bar 的 barH 公式一致）
    final double screenH = MediaQuery.of(context).size.height;
    final double dockH = (screenH * 0.12).clamp(104.0, 150.0);
    final double buttonCenter = 16 + dockH * 0.45 + widget.safeBottom;
    // 面板底部不超出屏幕底边（距底边至少 safeBottom + 6）
    final double bottom = (buttonCenter - panelH / 2)
        .clamp(widget.safeBottom + 6, double.infinity)
        .toDouble();

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedOpacity(
          opacity: open ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Center(
            child: Container(
              width: panelW,
              height: barH + 30,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: onSurface.withValues(alpha: 0.12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 背景声（音景）
                  _SoundColumn(
                    label: '背景',
                    height: barH,
                    value: ref.watch(soundscapeVolumeProvider),
                    muted: ref.watch(soundscapeMutedProvider),
                    color: theme.colorScheme.secondary,
                    onChanged: (nv) {
                      _tick();
                      ref.read(soundscapeVolumeProvider.notifier).state = nv;
                      unawaited(ref
                          .read(audioServiceProvider)
                          .setSoundscapeVolume(nv));
                      if (ref.read(soundscapeMutedProvider)) {
                        ref.read(soundscapeMutedProvider.notifier).state = false;
                        unawaited(ref
                            .read(audioServiceProvider)
                            .setSoundscapeMuted(false));
                      }
                    },
                    onMute: () {
                      _tick();
                      final bool m = !ref.read(soundscapeMutedProvider);
                      ref.read(soundscapeMutedProvider.notifier).state = m;
                      unawaited(
                          ref.read(audioServiceProvider).setSoundscapeMuted(m));
                    },
                  ),
                  // 音乐声
                  _SoundColumn(
                    label: '音乐',
                    height: barH,
                    value: ref.watch(musicVolumeProvider),
                    muted: ref.watch(musicMutedProvider),
                    color: theme.colorScheme.primary,
                    onChanged: (nv) {
                      _tick();
                      ref.read(musicVolumeProvider.notifier).state = nv;
                      unawaited(
                          ref.read(audioServiceProvider).setMusicVolume(nv));
                      if (ref.read(musicMutedProvider)) {
                        ref.read(musicMutedProvider.notifier).state = false;
                        unawaited(
                            ref.read(audioServiceProvider).setMusicMuted(false));
                      }
                    },
                    onMute: () {
                      _tick();
                      final bool m = !ref.read(musicMutedProvider);
                      ref.read(musicMutedProvider.notifier).state = m;
                      unawaited(
                          ref.read(audioServiceProvider).setMusicMuted(m));
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一个带标签 + 静音按钮的竖滑杆
class _SoundColumn extends StatelessWidget {
  final String label;
  final double height;
  final double value;
  final bool muted;
  final Color color;
  final ValueChanged<double> onChanged;
  final VoidCallback onMute;

  const _SoundColumn({
    required this.label,
    required this.height,
    required this.value,
    required this.muted,
    required this.color,
    required this.onChanged,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 11)),
        const SizedBox(height: 4),
        _VolumeTrack(
          height: height,
          value: muted ? 0 : value,
          color: muted ? Colors.white24 : color,
          onChanged: onChanged,
        ),
        const SizedBox(height: 4),
        // 静音切换点
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onMute,
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: muted
                  ? Colors.white.withValues(alpha: 0.25)
                  : color.withValues(alpha: 0.25),
            ),
            child: Text(
              muted ? '✕' : '♪',
              style: TextStyle(
                fontSize: 12,
                color: muted ? Colors.white54 : color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VolumeTrack extends StatefulWidget {
  final double height;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;
  const _VolumeTrack({
    required this.height,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_VolumeTrack> createState() => _VolumeTrackState();
}

class _VolumeTrackState extends State<_VolumeTrack> {
  final GlobalKey _key = GlobalKey();

  void _update(DragUpdateDetails d) {
    final RenderBox? box =
        _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final Offset local = box.globalToLocal(d.globalPosition);
    // 顶部 = 100%，底部 = 0%，按 1% 整数步进
    final double ratio = (1 - local.dy / box.size.height).clamp(0.0, 1.0);
    final int pct = (ratio * 100).round();
    widget.onChanged(pct / 100.0);
  }

  @override
  Widget build(BuildContext context) {
    final double fillH = widget.value.clamp(0.0, 1.0) * widget.height;
    return GestureDetector(
      onVerticalDragUpdate: _update,
      child: Container(
        key: _key,
        width: 56,
        height: widget.height,
        alignment: Alignment.bottomCenter,
        child: Container(
          width: 20,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 20,
              height: fillH,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
