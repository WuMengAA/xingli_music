import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers/audio/audio_providers.dart';
import '../providers/audio/playback_notifier.dart';
import 'app_icon.dart';

/// 底部控制区（dock 栏）
///
/// 官方控件：IconButton + 半透明容器，闲置 3s 自动淡隐。
class ControlBar extends ConsumerStatefulWidget {
  final VoidCallback onSwipeUp;

  const ControlBar({super.key, required this.onSwipeUp});

  @override
  ConsumerState<ControlBar> createState() => _ControlBarState();
}

class _ControlBarState extends ConsumerState<ControlBar> {
  // 音量按住拖动状态
  bool _dragged = false;
  double _volBase = 0.5;
  double _volAccum = 0;

  // 进度条拖动状态
  bool _seeking = false;
  double? _seekMs;

  /// 毫秒进度格式化：mm:ss.SSS
  String _fmtMs(Duration d) {
    final int ms = d.inMilliseconds;
    final int mm = ms ~/ 60000;
    final int ss = (ms % 60000) ~/ 1000;
    final int mmm = ms % 1000;
    return '${mm.toString().padLeft(2, '0')}:'
        '${ss.toString().padLeft(2, '0')}.'
        '${mmm.toString().padLeft(3, '0')}';
  }

  /// 记录一次音量交互（重置音量面板 3 秒无操作计时）
  void _volTick() {
    ref.read(volumeActivityProvider.notifier).state++;
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// dock 栏常驻，不淡隐；保留空实现兼容旧调用
  void _wake() {}

  /// 音量按钮：点按切换音乐声静音；按住上下划直接调音乐声音量（上划增大、下划减小）
  Widget _volumeButton(ThemeData theme) {
    final bool muted = ref.watch(musicMutedProvider);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _dragged = false;
        ref.read(volumeSliderOpenProvider.notifier).state = true;
      },
      onTapUp: (_) {
        // 纯点按（无拖动）：立即收起音量条，避免与静音一起闪条
        if (!_dragged) {
          ref.read(volumeSliderOpenProvider.notifier).state = false;
        }
      },
      onTap: () {
        _wake();
        _volTick();
        final bool m = !ref.read(musicMutedProvider);
        ref.read(musicMutedProvider.notifier).state = m;
        unawaited(ref.read(audioServiceProvider).setMusicMuted(m));
      },
      onVerticalDragStart: (_) {
        _wake();
        _dragged = true;
        _volBase = ref.read(musicVolumeProvider);
        _volAccum = 0;
        _volTick();
      },
      onVerticalDragUpdate: (d) {
        _wake();
        _volTick();
        // 上划（dy<0）音量增加；下划（dy>0）音量减少
        _volAccum -= d.delta.dy;
        final double nv = (_volBase + _volAccum / 100).clamp(0.0, 1.0);
        ref.read(musicVolumeProvider.notifier).state = nv;
        unawaited(ref.read(audioServiceProvider).setMusicVolume(nv));
        if (ref.read(musicMutedProvider)) {
          ref.read(musicMutedProvider.notifier).state = false;
          unawaited(ref.read(audioServiceProvider).setMusicMuted(false));
        }
      },
      onVerticalDragEnd: (_) => _volTick(),
      onVerticalDragCancel: _volTick,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: AppIcon(
          muted ? AppIcons.volumeMute : AppIcons.volume,
          size: 18,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  /// 可拖动进度条：拖动时放大加粗、显示毫秒进度，松手 seek 跳转
  Widget _buildSeekSlider(ThemeData theme, Duration? dur, Duration? pos) {
    final double durMs = dur?.inMilliseconds.toDouble() ?? 0;
    final double curMs = _seekMs ?? (pos?.inMilliseconds.toDouble() ?? 0);
    final bool enabled = durMs > 0;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: _seeking ? 12 : 3,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: _seeking ? 14 : 6,
        ),
        overlayShape: RoundSliderOverlayShape(
          overlayRadius: _seeking ? 26 : 14,
        ),
        activeTrackColor: theme.colorScheme.primary,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
        thumbColor: theme.colorScheme.primary,
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Slider(
              value: enabled ? curMs.clamp(0.0, durMs) : 0,
              max: enabled ? durMs : 1,
              onChanged: enabled
                  ? (v) => setState(() {
                        _seeking = true;
                        _seekMs = v;
                      })
                  : null,
              onChangeStart: enabled
                  ? (_) => setState(() => _seeking = true)
                  : null,
              onChangeEnd: enabled
                  ? (v) {
                      setState(() {
                        _seeking = false;
                        _seekMs = null;
                      });
                      unawaited(ref.read(audioServiceProvider).seek(
                        Duration(milliseconds: v.round()),
                      ));
                    }
                  : null,
            ),
          ),
          // 毫秒进度气泡：常驻结构 + Opacity/Transform 控制，
          // 不动态增删语义节点、不超出 Stack 边界（避免语义断言崩溃）
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: Opacity(
                  opacity: _seeking ? 1 : 0,
                  child: Transform.translate(
                    offset: Offset(0, _seeking ? 14 : 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        _fmtMs(Duration(
                            milliseconds: _seekMs?.round() ?? 0)),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 播放方式切换按钮：点击循环切换 顺序 → 倒叙 → 随机 → 单曲循环
  Widget _playModeButton(ThemeData theme) {
    const Map<PlayMode, String> labels = {
      PlayMode.order: '顺序',
      PlayMode.reverse: '倒叙',
      PlayMode.shuffle: '随机',
      PlayMode.loop: '单曲',
    };
    const Map<PlayMode, String> icons = {
      PlayMode.order: 'music',
      PlayMode.reverse: 'mountain',
      PlayMode.shuffle: 'refresh',
      PlayMode.loop: 'play',
    };
    final PlayMode mode = ref.watch(playModeProvider);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _wake();
        final PlayMode next = switch (mode) {
          PlayMode.order => PlayMode.reverse,
          PlayMode.reverse => PlayMode.shuffle,
          PlayMode.shuffle => PlayMode.loop,
          PlayMode.loop => PlayMode.order,
        };
        ref.read(playModeProvider.notifier).state = next;
      },
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(icons[mode] ?? 'refresh',
                size: 16, color: theme.colorScheme.onSurface),
            Text(
              labels[mode] ?? '',
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePlay() async {
    _wake();
    final String msg = await ref.read(playbackActionsProvider).toggle();
    if (msg.isNotEmpty) _toast(msg);
  }

  /// 轻提示（复用 Material SnackBar，避免静默失败）。
  /// 延迟到帧后弹出，避免在 Overlay 布局期间创建 SnackBar entry。
  void _toast(String msg) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext ctx = context;
      ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 13)),
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  Future<void> _switchTrack(int direction) async {
    _wake();
    final String msg =
        await ref.read(playbackActionsProvider).next(direction: direction);
    if (msg.isNotEmpty) _toast(msg);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;
    final Track? now = ref.watch(nowPlayingProvider);
    final Duration? pos = ref.watch(musicPositionProvider).valueOrNull;
    final Duration? dur = ref.watch(musicDurationProvider).valueOrNull;

    final double w = MediaQuery.of(context).size.width;
    final double h = MediaQuery.of(context).size.height;
    // 自适应：宽度约 92% 屏（最大 560），高度随屏高比例（104~150）
    final double barW = min(w * 0.92, 560);
    final double barH = (h * 0.12).clamp(104.0, 150.0);

    return Center(
      child: SizedBox(
        width: barW,
        height: barH,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x66101420),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上划手势只绑定到曲目名区域（进度条 Slider 独立，
              // 避免拖动进度条与外层手势在同一帧竞争触发语义断言）
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragEnd: (details) {
                  if (details.primaryVelocity != null &&
                      details.primaryVelocity! < -200) {
                    widget.onSwipeUp();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    now?.title ?? '星璃 · 无限音乐空间',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
                    // 可拖动进度条：压缩到 20px 高，避免 Slider 默认高度撑爆
                    SizedBox(height: 20, child: _buildSeekSlider(theme, dur, pos)),
                    const SizedBox(height: 0),
                // 控制按钮行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _volumeButton(theme),
                    IconButton(
                      icon: AppIcon(AppIcons.previous,
                          size: 18, color: theme.colorScheme.onSurface),
                      onPressed: () => _switchTrack(-1),
                      tooltip: '上一首',
                      iconSize: 18,
                    ),
                    // 播放/暂停主按钮
                    IconButton(
                      icon: AppIcon(
                        isPlaying ? AppIcons.pause : AppIcons.play,
                        size: 26,
                        color: theme.colorScheme.onPrimary,
                      ),
                      onPressed: _togglePlay,
                      tooltip: isPlaying ? '暂停' : '播放',
                      style: IconButton.styleFrom(
                        fixedSize: const Size(54, 54),
                        backgroundColor: theme.colorScheme.primary,
                        shape: const CircleBorder(),
                      ),
                    ),
                    IconButton(
                      icon: AppIcon(AppIcons.next,
                          size: 18, color: theme.colorScheme.onSurface),
                      onPressed: () => _switchTrack(1),
                      tooltip: '下一首',
                      iconSize: 18,
                    ),
                    _playModeButton(theme),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }
}
