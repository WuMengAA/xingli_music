/// ════════════════════════════════════════════════════════════════════════
/// 沉浸播放器共享视觉（主页沉浸播放器 / 整页正在播放 统一使用）
/// ════════════════════════════════════════════════════════════════════════
///
/// 目标：消除「主页播放器」与「整页正在播放」之间的**换页换皮**——
/// 统一为「深色沉浸面」（两种主题下都用深色底 + 浅色前景），封面统一为
/// **旋转黑胶唱片**，横屏阈值 / 空态文案一致。
///
/// 关键机制 —— [ImmersiveSurface]：用一层局部 `Theme` 把 `AppThemeColors`
/// 扩展覆盖为**深色变体**。由于全仓库的语义取色都走
/// `context.appColors`（= `Theme.of(context).extension<AppThemeColors>()`）
/// 与派生的 `context.appText`，所以其内**所有**消费者（曲名、歌词
/// [LyricsView]、播放控件 [PlaybackIconButton]、进度条、音量面板…）会
/// **自动切成浅色**，无需逐个控件加 `onDark` 参数。
///
/// 背景统一为「封面提色 + 深色基座 + 上下 scrim」；主页另有 B站视频透出，
/// 故 [ImmersiveBackground.videoThrough] 控制是否需要「模糊封面底衬」。
library;

import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/utils/palette_extractor.dart';
import '../../models/track.dart';
import '../../providers/audio/playback_error_provider.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../widgets/common/track_cover.dart';

/// 沉浸播放器前景文字投影：保证曲名/歌手/顶栏文字在任意视频画面或提色渐变
/// 上都保持可读。
const List<Shadow> kImmersiveTextShadow = <Shadow>[
  Shadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 1)),
];

/// 深色沉浸面主题包装：把 [AppThemeColors] 覆盖为深色变体（保留当前皮肤主色）。
///
/// 不改变 `Theme.of(context).brightness`（避免与 colorScheme 不一致的断言）——
/// 本仓库的取色一律走 `context.appColors`，覆盖扩展即可让前景整体变浅色。
class ImmersiveSurface extends StatelessWidget {
  const ImmersiveSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors base = context.appColors;
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: <ThemeExtension<dynamic>>[
          AppThemeColors.dark.withSkin(base.accent, Brightness.dark),
        ],
      ),
      child: child,
    );
  }
}

/// 沉浸播放器动态背景：封面提色渐变 + 固定深色基座 + 上下 scrim。
///
/// - [videoThrough] = true（主页）：半透明，**让下层 B站视频 / 几何透出**，
///   不铺模糊封面底衬。
/// - [videoThrough] = false（整页正在播放）：叠加一层模糊封面作底衬，
///   避免在无视频的场景下背景过于空白。
class ImmersiveBackground extends ConsumerStatefulWidget {
  const ImmersiveBackground({
    super.key,
    required this.track,
    this.videoThrough = false,
  });

  final Track? track;

  /// 是否依靠下层视频/几何作为底衬（主页 = true）。
  final bool videoThrough;

  @override
  ConsumerState<ImmersiveBackground> createState() => _ImmersiveBackgroundState();
}

class _ImmersiveBackgroundState extends ConsumerState<ImmersiveBackground> {
  Color? _dominant;
  Color? _prevAccent;

  @override
  void initState() {
    super.initState();
    _extract();
  }

  @override
  void didUpdateWidget(covariant ImmersiveBackground old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track) _extract();
  }

  Future<void> _extract() async {
    final Color? c = await PaletteExtractor.dominantOf(widget.track);
    if (mounted && c != null) setState(() => _dominant = c);
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final Color a = _dominant ?? c.accent;

    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      tween: ColorTween(begin: _prevAccent ?? c.accent, end: a),
      onEnd: () => _prevAccent = a,
      builder: (BuildContext context, Color? accent, Widget? child) {
        final Color col = accent ?? c.accent;
        // 基色固定为深色（不随主题）：沉浸播放器统一走「深色孤岛」，
        // 浅色主题下也保白字可读 + 视频作为暗氛围透出。
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                col.withValues(alpha: 0.38),
                const Color(0xFF0A0A12).withValues(alpha: 0.64),
              ],
              stops: const <double>[0, 0.7],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 模糊封面底衬（仅无视频透出的场景）。
              if (!widget.videoThrough && _hasImage)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.42,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Transform.scale(
                        scale: 1.3,
                        child: _CoverImage(track: widget.track!),
                      ),
                    ),
                  ),
                ),
              // 顶部/底部压暗，保证文字与控制栏可读。
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0x44000000),
                      Colors.transparent,
                      Colors.transparent,
                      Color(0x55000000),
                    ],
                    stops: <double>[0, 0.18, 0.7, 1],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool get _hasImage {
    final Track? t = widget.track;
    return t != null &&
        ((t.coverPath?.isNotEmpty ?? false) ||
            (t.coverUrl?.isNotEmpty ?? false));
  }
}

/// 封面图（网络 / 本地 / 降级），用于背景模糊底衬。
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final String? url = track.coverUrl;
    final String? path = track.coverPath;
    final Widget fallback = ColoredBox(color: c.accentSoft);
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        cacheWidth: 1024,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (BuildContext c2, Widget child, ImageChunkEvent? p) =>
            p == null ? child : fallback,
      );
    }
    if (path != null && path.isNotEmpty) {
      return Image.file(
        File(path),
        cacheWidth: 1024,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return fallback;
  }
}

/// 大黑胶唱片封面：圆形封面 + 黑胶外环 + 中心轴孔 + 播放时旋转。
class ImmersiveDiscCover extends StatelessWidget {
  const ImmersiveDiscCover({
    super.key,
    required this.track,
    required this.spin,
    required this.size,
  });

  final Track? track;
  final Animation<double> spin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final bool hasImage = track != null &&
        ((track!.coverPath?.isNotEmpty ?? false) ||
            (track!.coverUrl?.isNotEmpty ?? false));
    final Widget inner = hasImage
        ? TrackCover(track: track, size: size, radius: size / 2)
        : Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[c.accentSoft, c.accent],
              ),
            ),
            child: Center(
              child: Icon(
                Icons.music_note_rounded,
                size: size * 0.36,
                color: c.onAccent,
              ),
            ),
          );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 唱片底盘（黑胶外环）。
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.85),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
          ),
          // 旋转封面（圆形裁切）。
          AnimatedBuilder(
            animation: spin,
            child: Padding(
              padding: EdgeInsets.all(size * 0.06),
              child: ClipOval(child: inner),
            ),
            builder: (BuildContext context, Widget? child) => Transform.rotate(
              angle: spin.value * 2 * math.pi,
              child: child,
            ),
          ),
          // 中心轴孔。
          Container(
            width: size * 0.12,
            height: size * 0.12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A0A12),
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 曲名 + 歌手（统一空态文案，白字 + 投影）。
class ImmersiveTrackTitle extends StatelessWidget {
  const ImmersiveTrackTitle({super.key, required this.track, this.alignLeft = false});

  final Track? track;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    final TextAlign align = alignLeft ? TextAlign.left : TextAlign.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          track?.title ?? '星璃 · 无限音乐空间',
          style: context.appText.title.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: kImmersiveTextShadow,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          track?.artist ?? '从曲库挑一首开始',
          style: context.appText.body.copyWith(
            color: Colors.white70,
            shadows: kImmersiveTextShadow,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
      ],
    );
  }
}

/// 播放失败 · 常驻错误条（#playback-error）。
///
/// 读取 [playbackErrorProvider]：非空时显示「⚠ + message + 重试 + 关闭」，
/// 覆盖三种失败场景（点播失败 / 中途断流 / 自动下一首失败）。条状、**非全屏**，
/// 放在底部控制栏上方，不遮挡播放控件。两页沉浸播放器（主页 / 整页正在播放）
/// 复用同一个组件，所以只此一份实现。
///
/// 取色直接用 `context.appColors`：处于 [ImmersiveSurface] 深色面内，文字用浅色。
class PlaybackErrorBanner extends ConsumerWidget {
  const PlaybackErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackError? err = ref.watch(playbackErrorProvider);
    if (err == null) return const SizedBox.shrink();

    final AppThemeColors c = context.appColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.sm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: c.danger.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: c.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              err.message,
              style: context.appText.body.copyWith(color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () {
              // 重试：先清除失败位，再按 kind 触发对应播放动作。
              ref.read(playbackErrorProvider.notifier).clear();
              _retry(ref, err);
            },
            child: Text('重试', style: TextStyle(color: c.accent)),
          ),
          TextButton(
            onPressed: () => ref.read(playbackErrorProvider.notifier).clear(),
            child: const Text('关闭', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  /// 按 [PlaybackError.kind] 分派重试动作。
  void _retry(WidgetRef ref, PlaybackError err) {
    final PlaybackActions actions = ref.read(playbackActionsProvider);
    switch (err.kind) {
      case PlaybackRetryKind.playTrack:
        if (err.track != null) unawaited(actions.playTrack(err.track!));
        break;
      case PlaybackRetryKind.next:
        unawaited(actions.next());
        break;
      case PlaybackRetryKind.toggle:
        unawaited(actions.toggle());
        break;
      case PlaybackRetryKind.none:
        break;
    }
  }
}
