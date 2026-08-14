import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/track.dart';
import '../../pages/sources/aggregate_search_page.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../services/audio/audio_service.dart';
import '../app_icon.dart';
import '../common/playback_feedback.dart';
import '../common/track_cover.dart';
import '../liquid_glass.dart';
import '../noise_texture.dart';
import '../sources/music_quality_sheet.dart';
import 'equalizer_panel.dart';
import 'playback_controls.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 统一播放器组件（场景默认样式）
/// ════════════════════════════════════════════════════════════════════════
///
/// 取代原先分散的 [MiniPlayer]（AppShell，非场景页）与 [ScenePlaybackPanel]
/// （场景页），二者收敛为同一组件，消除「各页播放器不统一」。
///
/// ### 布局（对齐场景页默认样式，R1/R2）
/// 半透明毛玻璃容器、圆角 24、细描边；内含
/// 曲目信息 + 进度条 + 播放控制 + 全局音量（R3）+ 白噪音开关（R4），
/// 并可折叠 / 全屏展开（缩放 + 淡入动画）。
///
/// ### 背景（统一为「其他三页下方的样式背景」）
/// 曲库 / 探索 / 设置 三页的下方背景是 AppShell 玻璃背景层
/// （`accent 0.10 → bgPage` 渐变 + 噪点）。场景页因 `ContentContainer`
/// 为实色底，播放面板背后不再是该背景。为保持三页一致，本组件**自带**
/// 同样的渐变 + 噪点背景，再用 [LiquidGlass]（frosted）模糊，确保无论在
/// 哪个页面，播放器背景观感完全一致。
///
/// ### 浅色模式可见性
/// 全部颜色走 `context.appColors` / `AppColors` / `AppTextStyles` 主题感知
/// token，明暗主题下文字与图标自动适配。
///
/// ### 控制器统一
/// 传输键（prev/play/next/volume）复用共享 `PlaybackIconButton`（AppIcon +
/// `iconPrimary`/`accent`），与全局播放器一致。
class UnifiedPlayer extends ConsumerStatefulWidget {
  const UnifiedPlayer({super.key, this.onOpenNowPlaying, this.lyricsSlot});

  /// 点击左侧信息区（封面 + 曲名）的回调。
  ///
  /// R23j：默认（不传）直接打开**全屏播放卡片**（[UnifiedPlayer] 自带
  /// Overlay，可拖拽调大小）；传入了则优先走外部回调（兼容旧接入）。
  final VoidCallback? onOpenNowPlaying;

  /// 可选歌词区（通常传 `LyricsView`）。
  ///
  /// 非空时在**全屏 Overlay** 的播放内容下方追加显示；为 null 时全屏面板与
  /// 原先完全一致。紧凑面板不受影响（空间有限，歌词只在全屏态展示）。
  final Widget? lyricsSlot;

  @override
  ConsumerState<UnifiedPlayer> createState() => _UnifiedPlayerState();
}

class _UnifiedPlayerState extends ConsumerState<UnifiedPlayer> {
  bool _volOpen = false;
  bool _seeking = false;
  double? _seekMs;

  /// 折叠态（R1 可折叠播放器）：收起时只显示封面 + 曲名 + 播放 / 展开。
  /// UI 自适应：空间紧张（横屏矮 / 手表）时**默认折叠**。
  bool _collapsed = false;
  bool _collapsedInit = false;

  /// 全屏展开态：插入 Overlay 时置 true。
  bool _fullscreen = false;
  OverlayEntry? _overlayEntry;

  /// 翻转白噪音开关（#167）：按当前来源写入场景或全局。
  void _toggleWhiteNoise() {
    final bool on = !ref.read(effectiveWhiteNoiseProvider).on;
    if (ref.read(whiteNoiseFollowsSceneProvider)) {
      unawaited(saveSceneWhiteNoise(ref, on: on));
    } else {
      ref.read(whiteNoiseEnabledProvider.notifier).state = on;
    }
  }

  void _enterFullscreen() {
    if (_fullscreen) return;
    final OverlayState overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (_) => _FullscreenPlaybackOverlay(
        onClose: _exitFullscreen,
        lyricsSlot: widget.lyricsSlot,
      ),
    );
    overlay.insert(_overlayEntry!);
    setState(() => _fullscreen = true);
  }

  void _exitFullscreen() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _fullscreen = false);
  }

  @override
  Widget build(BuildContext context) {
    // UI 自适应：首次 build 按屏幕尺寸决定默认折叠（initState 禁读 MediaQuery）
    if (!_collapsedInit) {
      _collapsedInit = true;
      _collapsed = ResponsiveLayout.of(context).playerCollapsedByDefault;
    }
    final Track? now = ref.watch(nowPlayingProvider);
    // #167：白噪音状态取「生效来源」（跟随场景 / 全局），非全局开关本身
    final bool whiteNoise = ref.watch(effectiveWhiteNoiseProvider).on;

    final Widget header = Row(
      children: <Widget>[
        TrackCover(track: now, size: 44, radius: 10),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                now?.title ?? '星璃 · 无限音乐空间',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appText.trackName,
              ),
              const SizedBox(height: 2),
              Text(
                now?.artist ?? '从曲库挑一首开始',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appText.artist,
              ),
            ],
          ),
        ),
        PlaybackButtonFabric.whiteNoise(
          active: whiteNoise,
          onTap: _toggleWhiteNoise,
        ),
        PlaybackIconButton(
          icon: _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          size: 22,
          active: _fullscreen,
          tooltip: _fullscreen ? '退出全屏' : '全屏播放',
          onTap: _fullscreen ? _exitFullscreen : _enterFullscreen,
        ),
        PlaybackIconButton(
          icon: _collapsed
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          size: 22,
          tooltip: _collapsed ? '展开播放器' : '收起播放器',
          onTap: () => setState(() => _collapsed = !_collapsed),
        ),
      ],
    );

    // R23j：点击信息区 = 打开全屏播放卡片（默认行为）。
    // 外部显式传入 onOpenNowPlaying 时仍走外部回调（兼容旧接入）。
    final Widget headerArea = InkWell(
      onTap: widget.onOpenNowPlaying ?? _enterFullscreen,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: header,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _frostedPanel(
          context,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              headerArea,

              // ── 可折叠区域：进度条 + 控制行 + 音量面板 ──
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _collapsed
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const SizedBox(height: 8),
                          _buildProgressSlider(
                            ref,
                            _seeking,
                            _seekMs,
                            (double v) => setState(() {
                              _seeking = true;
                              _seekMs = v;
                            }),
                            (double v) {
                              setState(() {
                                _seeking = false;
                                _seekMs = null;
                              });
                              unawaited(ref
                                  .read(audioServiceProvider)
                                  .seek(Duration(milliseconds: v.round())));
                            },
                          ),
                          const SizedBox(height: 4),
                          _buildTransportRow(
                            context,
                            ref,
                            fullscreen: false,
                            volOpen: _volOpen,
                            onToggleVol: () =>
                                setState(() => _volOpen = !_volOpen),
                          ),
                          _buildVolumePanel(ref, _volOpen),
                          // ⑧：搜索 + 音质入口下沉到音乐卡片底部（全局液态玻璃卡片）。
                          _buildBottomActions(context, ref),
                        ],
                      ),
              ),
            ],
          ),
          // 紧凑面板：背景+背景的背景全透明（仅毛玻璃模糊，无盒感）
          transparent: true,
          glassTint: Colors.transparent,
          glassBorder: Colors.transparent,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 毛玻璃面板（渐变 + 噪点背景 + frosted 模糊），紧凑 / 全屏共用
// ════════════════════════════════════════════════════════════════════════

/// 渲染播放面板背景。
///
/// 双形态（由 [transparent] 切换）：
/// - `transparent: false`（默认）：渐变 + 噪点 + frosted 模糊，用于全屏
///   Overlay（底下是深色 scrim，需自带底色保证文字可读）。
/// - `transparent: true`：**背景透明**，仅保留 [LiquidGlass]（frosted）的
///   边缘模糊 + 半透明 tint + 细描边，用于紧凑面板（坐在实色容器上，
///   透出干净底色，边缘毛玻璃过渡）。
Widget _frostedPanel(
  BuildContext context,
  Widget content, {
  double radius = 24,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  bool transparent = false,
  // R26r21：透明模式可进一步指定 tint/描边（默认极淡白），传透明色=纯模糊无盒感。
  Color? glassTint,
  Color? glassBorder,
}) {
  if (transparent) {
    return LiquidGlass(
      radius: radius,
      style: GlassStyle.frosted,
      // blur 跟随全局性能模式（省电=0 关闭模糊）
      tint: glassTint ?? const Color(0x0AFFFFFF),
      borderColor: glassBorder ?? const Color(0x26FFFFFF),
      padding: padding,
      child: content,
    );
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            context.appColors.accent.withValues(alpha: 0.10),
            context.appColors.bgPage,
          ],
          stops: const <double>[0, 0.6],
        ),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: NoiseTexture(seed: 11)),
          LiquidGlass(
            radius: 0,
            // blur 跟随全局性能模式（省电=0 关闭模糊）
            tint: const Color(0x14FFFFFF),
            borderColor: const Color(0x33FFFFFF),
            padding: padding,
            child: content,
          ),
        ],
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════
// 共享构建辅助（紧凑面板 + 全屏视图共用，避免重复逻辑）
// ════════════════════════════════════════════════════════════════════════

/// 播放模式 → 图标（Material 图标，AppIcon 未覆盖）。
IconData _modeIcon(PlayMode m) => switch (m) {
      PlayMode.order => Icons.trending_flat,
      PlayMode.reverse => Icons.keyboard_backspace,
      PlayMode.shuffle => Icons.shuffle,
      PlayMode.loop => Icons.repeat_one,
    };

String _modeLabel(PlayMode m) => switch (m) {
      PlayMode.order => '顺序',
      PlayMode.reverse => '倒叙',
      PlayMode.shuffle => '随机',
      PlayMode.loop => '单曲循环',
    };

PlayMode _nextMode(PlayMode m) => switch (m) {
      PlayMode.order => PlayMode.reverse,
      PlayMode.reverse => PlayMode.shuffle,
      PlayMode.shuffle => PlayMode.loop,
      PlayMode.loop => PlayMode.order,
    };

/// 统一传输行（prev / play / next / volume / mode）。
Widget _buildTransportRow(
  BuildContext context,
  WidgetRef ref, {
  required bool fullscreen,
  required bool volOpen,
  required VoidCallback onToggleVol,
}) {
  final bool isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;
  final PlayMode mode = ref.watch(playModeProvider);
  final bool muted = ref.watch(musicMutedProvider);
  final double playSize = fullscreen ? 40 : 32;
  final double sideSize = fullscreen ? 28 : 24;

  return PlaybackTransportRow(
    spacing: fullscreen ? 12 : 6,
    children: <Widget>[
      PlaybackIconButton(
        svgName: muted ? AppIcons.volumeMute : AppIcons.volume,
        size: sideSize,
        tint: true,
        active: volOpen,
        tooltip: '音量',
        onTap: onToggleVol,
      ),
      PlaybackIconButton(
        svgName: AppIcons.previous,
        size: sideSize,
        tooltip: '上一首',
        onTap: () => unawaited(
          ref.read(playbackActionsProvider).next(direction: -1),
        ),
      ),
      PlaybackIconButton(
        svgName: isPlaying ? AppIcons.pause : AppIcons.play,
        size: playSize,
        tooltip: isPlaying ? '暂停' : '播放',
        onTap: () async {
          final String msg =
              await ref.read(playbackActionsProvider).toggle();
          if (msg.isNotEmpty && context.mounted) {
            showPlaybackToast(context, msg);
          }
        },
      ),
      PlaybackIconButton(
        svgName: AppIcons.next,
        size: sideSize,
        tooltip: '下一首',
        onTap: () => unawaited(ref.read(playbackActionsProvider).next()),
      ),
      PlaybackIconButton(
        icon: _modeIcon(mode),
        size: sideSize,
        tint: true,
        tooltip: '播放模式：${_modeLabel(mode)}',
        onTap: () {
          final PlayMode next = _nextMode(mode);
          ref.read(playModeProvider.notifier).state = next;
          if (context.mounted) {
            showPlaybackToast(context, '播放模式：${_modeLabel(next)}');
          }
        },
      ),
    ],
  );
}

/// 进度条（主题感知色）。
Widget _buildProgressSlider(
  WidgetRef ref,
  bool seeking,
  double? seekMs,
  ValueChanged<double> onChanged,
  ValueChanged<double> onEnd,
) {
  final Duration? pos = ref.watch(musicPositionProvider).valueOrNull;
  final Duration? dur = ref.watch(musicDurationProvider).valueOrNull;
  return _ProgressSlider(
    pos: pos,
    dur: dur,
    seeking: seeking,
    seekMs: seekMs,
    onChanged: onChanged,
    onEnd: onEnd,
  );
}

/// 音量面板（#170：主音量总输出 + 六大声音分类各自独立控制）。
///
/// 分类与规范名见 [AudioCategory]（音乐 / 背景声 / 白噪音 / 音效 /
/// 世界空间音效 / 提示音）；每行带一句**小字概念说明**，拖动滑块即播该分类的
/// 代表性反馈音（[AudioService.playCategoryCue]，内部 220ms 节流）。
/// 白噪音行额外提供「跟随场景 / 全局播放」切换（#167）。
Widget _buildVolumePanel(WidgetRef ref, bool volOpen) {
  final double master = ref.watch(masterVolumeProvider);
  final double musicVol = ref.watch(musicVolumeProvider);
  final double scVol = ref.watch(soundscapeVolumeProvider);
  final double sfx = ref.watch(sfxVolumeProvider);
  final double world = ref.watch(worldSfxVolumeProvider);
  final double uiCue = ref.watch(uiCueVolumeProvider);
  final bool muted = ref.watch(musicMutedProvider);
  final bool follows = ref.watch(whiteNoiseFollowsSceneProvider);
  final WhiteNoiseState wn = ref.watch(effectiveWhiteNoiseProvider);

  /// 播放该分类的代表性反馈音（调整确认）。
  void cue(AudioCategory c) =>
      unawaited(ref.read(audioServiceProvider).playCategoryCue(c));

  return AnimatedSize(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    child: volOpen
        ? Column(
            children: <Widget>[
              const SizedBox(height: 6),
              // 主音量：不属于分类，是所有分类的总输出
              _VolRow(
                label: '主音量',
                concept: '所有分类的总输出',
                value: master,
                onChanged: (double v) {
                  ref.read(masterVolumeProvider.notifier).state = v;
                  unawaited(
                      ref.read(audioServiceProvider).setMasterVolume(v));
                },
              ),
              _VolRow(
                category: AudioCategory.music,
                value: muted ? 0 : musicVol,
                onChanged: (double v) {
                  ref.read(musicVolumeProvider.notifier).state = v;
                  ref.read(musicMutedProvider.notifier).state = false;
                  unawaited(
                      ref.read(audioServiceProvider).setMusicVolume(v));
                  unawaited(
                      ref.read(audioServiceProvider).setMusicMuted(false));
                  cue(AudioCategory.music);
                },
              ),
              _VolRow(
                category: AudioCategory.soundscape,
                value: scVol,
                onChanged: (double v) {
                  ref.read(soundscapeVolumeProvider.notifier).state = v;
                  unawaited(
                      ref.read(audioServiceProvider).setSoundscapeVolume(v));
                  cue(AudioCategory.soundscape);
                },
              ),
              // #167：白噪音——跟随场景时写入当前场景，否则写全局
              _VolRow(
                category: AudioCategory.whiteNoise,
                value: wn.volume,
                trailing: _WhiteNoiseSourceToggle(follows: follows),
                onChanged: (double v) {
                  if (follows) {
                    unawaited(saveSceneWhiteNoise(ref, volume: v));
                  } else {
                    ref.read(whiteNoiseVolumeProvider.notifier).state = v;
                  }
                  cue(AudioCategory.whiteNoise);
                },
              ),
              _VolRow(
                category: AudioCategory.sfx,
                value: sfx,
                onChanged: (double v) {
                  ref.read(sfxVolumeProvider.notifier).state = v;
                  unawaited(
                      ref.read(audioServiceProvider).setSfxVolume(v));
                  cue(AudioCategory.sfx);
                },
              ),
              _VolRow(
                category: AudioCategory.worldSpatial,
                value: world,
                onChanged: (double v) {
                  ref.read(worldSfxVolumeProvider.notifier).state = v;
                  cue(AudioCategory.worldSpatial);
                },
              ),
              _VolRow(
                category: AudioCategory.uiCue,
                value: uiCue,
                onChanged: (double v) {
                  ref.read(uiCueVolumeProvider.notifier).state = v;
                  cue(AudioCategory.uiCue);
                },
              ),
            ],
          )
        : const SizedBox(width: double.infinity),
  );
}

/// ⑧⑩：音乐卡片底部操作行——搜索（弹出式底部卡片）+ 音质 / 清晰度。
Widget _buildBottomActions(BuildContext context, WidgetRef ref) {
  final AppThemeColors colors = context.appColors;
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        TextButton.icon(
          onPressed: () => unawaited(showAggregateSearchSheet(context)),
          icon: Icon(Icons.search_rounded, size: 18, color: colors.accent),
          label: Text('搜索', style: context.appText.caption),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(width: 14),
        TextButton.icon(
          onPressed: () => unawaited(showMusicQualitySheet(context)),
          icon:
              Icon(Icons.high_quality_rounded, size: 18, color: colors.accent),
          label: Text('音质', style: context.appText.caption),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ],
    ),
  );
}

/// 白噪音来源切换（#167）：跟随场景 ⇄ 全局播放。
///
/// 「跟随场景」= 每个场景各自记忆白噪音开关与音量，换场景自动切换；
/// 「全局播放」= 忽略场景设置，全局统一一份，走到哪都一样。
class _WhiteNoiseSourceToggle extends ConsumerWidget {
  const _WhiteNoiseSourceToggle({required this.follows});

  final bool follows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color accent = context.appColors.accent;
    return Tooltip(
      message: follows
          ? '白噪音跟随场景：每个场景独立记忆，点击改为全局播放'
          : '白噪音全局播放：忽略场景设置，点击改为跟随场景',
      child: InkWell(
        onTap: () {
          ref.read(whiteNoiseFollowsSceneProvider.notifier).state = !follows;
          unawaited(ref
              .read(audioServiceProvider)
              .playCategoryCue(AudioCategory.uiCue));
        },
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                follows ? Icons.landscape_rounded : Icons.public_rounded,
                size: 12,
                color: accent,
              ),
              const SizedBox(width: 3),
              Text(
                follows ? '跟随场景' : '全局播放',
                style: TextStyle(fontSize: 11, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 白噪音开关小圆钮工厂（与折叠钮同款 tint 风格）。
class PlaybackButtonFabric {
  const PlaybackButtonFabric._();

  static Widget whiteNoise({
    required bool active,
    required VoidCallback onTap,
  }) =>
      PlaybackIconButton(
        icon: active
            ? Icons.graphic_eq_rounded
            : Icons.graphic_eq_outlined,
        size: 22,
        tint: true,
        active: active,
        tooltip: active ? '关闭场景白噪音' : '开启场景白噪音',
        onTap: onTap,
      );
}

// ════════════════════════════════════════════════════════════════════════
// 全屏展开 Overlay（缩放 + 淡入动画）
// ════════════════════════════════════════════════════════════════════════

class _FullscreenPlaybackOverlay extends ConsumerStatefulWidget {
  const _FullscreenPlaybackOverlay({required this.onClose, this.lyricsSlot});

  final VoidCallback onClose;

  /// 可选歌词区（见 [UnifiedPlayer.lyricsSlot]）。
  final Widget? lyricsSlot;

  @override
  ConsumerState<_FullscreenPlaybackOverlay> createState() =>
      _FullscreenPlaybackOverlayState();
}

class _FullscreenPlaybackOverlayState
    extends ConsumerState<_FullscreenPlaybackOverlay> {
  bool _visible = false;
  bool _volOpen = false; // 全局液态玻璃卡片：默认展开的音量面板关闭
  bool _seeking = false;
  double? _seekMs;

  /// R23j：面板尺寸比例（相对屏幕宽度，0.5~1.0，可右下角拖拽调整）。
  double _scale = 0.85;
  double _scaleStart = 0.85;

  @override
  void initState() {
    super.initState();
    // 挂载后下一帧触发进入动画（从 0.9 缩放 + 透明度 0 → 1）
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => setState(() => _visible = true),
    );
  }

  void _requestClose() {
    setState(() => _visible = false);
    Future.delayed(const Duration(milliseconds: 280), widget.onClose);
  }

  /// 翻转白噪音开关（#167）：按当前来源写入场景或全局。
  void _toggleWhiteNoise() {
    final bool on = !ref.read(effectiveWhiteNoiseProvider).on;
    if (ref.read(whiteNoiseFollowsSceneProvider)) {
      unawaited(saveSceneWhiteNoise(ref, on: on));
    } else {
      ref.read(whiteNoiseEnabledProvider.notifier).state = on;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final Track? now = ref.watch(nowPlayingProvider);
    // #167：白噪音状态取「生效来源」（跟随场景 / 全局）
    final bool whiteNoise = ref.watch(effectiveWhiteNoiseProvider).on;
    return Material(
      // R26r21：Overlay 条目无 Material 祖先 → 面板内 Slider/IconButton/InkWell
      // 崩溃「No Material widget found」；透明包一层即可。
      color: Colors.transparent,
      child: Stack(
        children: <Widget>[
          // 遮罩：点击关闭。R26r21：透明遮罩（两侧透明，露出底层应用）。
          AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: GestureDetector(
              onTap: _requestClose,
              child: Container(color: Colors.transparent),
            ),
          ),
          // 面板：缩放 + 淡入，宽度可拖拽调整（R23j）
          Center(
            child: AnimatedScale(
              scale: _visible ? 1.0 : 0.9,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: SizedBox(
                  width: screen.width * _scale,
                  child: Stack(
                    children: <Widget>[
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: screen.height - 96,
                        ),
                        child: _frostedPanel(
                          context,
                          SingleChildScrollView(
                            child: _buildContent(now, whiteNoise),
                          ),
                          radius: 32,
                          padding: const EdgeInsets.all(24),
                          // R26r21：面板背景透明（仅 frosted 半透明 + 细描边），
                          // 配合透明遮罩 → 音乐菜单两侧与背景都透明。
                          transparent: true,
                        ),
                      ),
                    // 右下角拖拽手柄：等比调面板大小
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => _scaleStart = _scale,
                        onPanUpdate: (DragUpdateDetails d) {
                          final double next =
                              _scaleStart + d.delta.dx / screen.width;
                          setState(
                            () => _scale = next.clamp(0.5, 1.0),
                          );
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.appColors.bgControl
                                .withValues(alpha: 0.8),
                          ),
                          child: Icon(
                            Icons.open_in_full_rounded,
                            size: 14,
                            color: context.appColors.iconInactive,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }

  /// I：播放菜单内打开均衡器（复用 [EqualizerPanel]，弹层展示）。
  void _openEqualizer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.md,
            AppSpace.md,
            AppSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('均衡器', style: context.appText.subtitle),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              const Flexible(child: EqualizerPanel()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Track? now, bool whiteNoise) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[        Row(
          children: <Widget>[
            TrackCover(track: now, size: 72, radius: 16),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    now?.title ?? '星璃 · 无限音乐空间',
                    style: context.appText.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    now?.artist ?? '从曲库挑一首开始',
                    style: context.appText.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // I：均衡器（Windows mpv 滤镜真 DSP / Android 真 EQ / 其余模拟层）
            PlaybackIconButton(
              icon: Icons.equalizer_rounded,
              size: AppSize.iconSm,
              tooltip: '均衡器',
              onTap: () => _openEqualizer(context),
            ),
            PlaybackIconButton(
              icon: Icons.fullscreen_exit,
              size: AppSize.iconSm,
              tooltip: '退出全屏',
              onTap: _requestClose,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildProgressSlider(
          ref,
          _seeking,
          _seekMs,
          (double v) => setState(() {
            _seeking = true;
            _seekMs = v;
          }),
          (double v) {
            setState(() {
              _seeking = false;
              _seekMs = null;
            });
            unawaited(ref
                .read(audioServiceProvider)
                .seek(Duration(milliseconds: v.round())));
          },
        ),
        const SizedBox(height: 8),
        _buildTransportRow(
          context,
          ref,
          fullscreen: true,
          volOpen: _volOpen,
          onToggleVol: () => setState(() => _volOpen = !_volOpen),
        ),
        _buildVolumePanel(ref, _volOpen),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: _toggleWhiteNoise,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  PlaybackIconButton(
                    icon: whiteNoise
                        ? Icons.graphic_eq_rounded
                        : Icons.graphic_eq_outlined,
                    size: 22,
                    tint: true,
                    active: whiteNoise,
                    tooltip: whiteNoise ? '关闭白噪音' : '开启白噪音',
                    onTap: _toggleWhiteNoise,
                  ),
                  const SizedBox(width: 8),
                  Text('白噪音', style: context.appText.body),
                  const SizedBox(width: 8),
                  // #167：来源切换（跟随场景 / 全局播放）
                  _WhiteNoiseSourceToggle(
                    follows: ref.watch(whiteNoiseFollowsSceneProvider),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── 歌词区（可选）：调用方传入 lyricsSlot 时才出现 ──
        // R23j：外层已包 SingleChildScrollView，无需（也不能）用 Flexible。
        if (widget.lyricsSlot != null) ...<Widget>[
          const SizedBox(height: 8),
          widget.lyricsSlot!,
        ],
        const SizedBox(height: 8),
        // ⑨：搜索 + 音质也放进沉浸式卡片（与底部音乐卡片同源）。
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            PlaybackIconButton(
              icon: Icons.search_rounded,
              size: AppSize.iconSm,
              tooltip: '搜索',
              onTap: () => unawaited(showAggregateSearchSheet(context)),
            ),
            const SizedBox(width: 16),
            PlaybackIconButton(
              icon: Icons.high_quality_rounded,
              size: AppSize.iconSm,
              tooltip: '音质',
              onTap: () => unawaited(showMusicQualitySheet(context)),
            ),
          ],
        ),
      ],
    );
  }
}

/// 紧凑可拖拽进度条（主题感知色）。
class _ProgressSlider extends StatelessWidget {
  const _ProgressSlider({
    required this.pos,
    required this.dur,
    required this.seeking,
    required this.seekMs,
    required this.onChanged,
    required this.onEnd,
  });

  final Duration? pos;
  final Duration? dur;
  final bool seeking;
  final double? seekMs;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onEnd;

  String _fmt(Duration d) {
    final int mm = d.inMilliseconds ~/ 60000;
    final int ss = (d.inMilliseconds % 60000) ~/ 1000;
    return '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final double durMs = dur?.inMilliseconds.toDouble() ?? 0;
    final double curMs = seekMs ?? (pos?.inMilliseconds.toDouble() ?? 0);
    final bool enabled = durMs > 0;

    return Row(
      children: <Widget>[
        Text(
          _fmt(Duration(milliseconds: curMs.round())),
          style: TextStyle(
            color: context.appColors.textTertiary,
            fontSize: 10,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: seeking ? 8 : 3,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: seeking ? 10 : 5,
              ),
              activeTrackColor: context.appColors.accent,
              inactiveTrackColor: context.appColors.progressTrack,
              thumbColor: context.appColors.accent,
            ),
            child: Slider(
              value: enabled ? curMs.clamp(0.0, durMs) : 0,
              max: enabled ? durMs : 1,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onEnd : null,
            ),
          ),
        ),
        Text(
          _fmt(dur ?? Duration.zero),
          style: TextStyle(
            color: context.appColors.textTertiary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

/// 单个分类的音量行（#170）。
///
/// 标题行 = 规范分类名 + **小字概念说明**（一句话点明这类声音是什么）+
/// 可选尾部控件（如白噪音的「跟随场景 / 全局播放」切换）；下方为紧凑滑块。
/// 传 [category] 时标题与说明取 [AudioCategory] 的规范文案，保证全局同名；
/// 非分类项（主音量）用 [label] + [concept] 显式给出。
class _VolRow extends StatelessWidget {
  const _VolRow({
    required this.value,
    required this.onChanged,
    this.category,
    this.label,
    this.concept,
    this.trailing,
  });

  /// 声音分类（非空时文案取分类规范名）。
  final AudioCategory? category;

  /// 显式标题（仅非分类项用，如「主音量」）。
  final String? label;

  /// 显式概念小字（仅非分类项用）。
  final String? concept;

  /// 尾部控件（如白噪音来源切换）。
  final Widget? trailing;

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final String title = category?.label ?? label ?? '';
    final String hint = category?.concept ?? concept ?? '';
    final AppThemeColors colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            // 概念小字：解释这类声音是什么，避免用户凭名字猜
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        // 紧凑滑块：六类同屏时不至于把播放面板撑高
        SizedBox(
          height: 24,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
