/// ════════════════════════════════════════════════════════════════════════
/// 主页 · 沉浸播放器（2026-09-14 重构）
/// ════════════════════════════════════════════════════════════════════════
///
/// 取代原 [HomeSceneContent] 的「场景卡堆」为主页主体。用户需求：
/// ① 整页「正在播放页」（[NowPlayingPage]）已于 2026-09-16 彻底移除；封面 +
///    歌词已融入主页沉浸播放器，主页直接承载播放器（游戏内 HUD 亦不再跳转整页）；
/// ② 封面 + 歌词移入主页 —— 做成 Apple Music / 网易云风格的沉浸播放器：
///    全屏封面动态背景 + 大唱片封面（播放旋转）+ 曲名/歌手 + 频谱 + 歌词
///    + 完整控制栏。
///
/// 场景切换降级为「右上角入口」——点开弹出场景选择浮窗（复用 [SceneCardStack]），
/// 不再占主页主体。切场景仅切换音景层与视觉，不中断当前音乐（R5）。
///
/// 复用 [UnifiedPlayer] 的公开构建辅助（[buildTransportRow] / [buildVolumePanel]
/// / [buildBottomActions] / [ProgressSlider]），保证双端视觉一致、零重复逻辑。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../models/track.dart';
import '../../../models/scene.dart';
import '../../../providers/audio/audio_providers.dart';
import '../../../providers/scene/scene_providers.dart';
import '../../../providers/session/session_providers.dart';
import '../../../providers/shell/shell_providers.dart';
import '../../../providers/home/home_video_provider.dart';
import '../../../providers/home/player_theme_provider.dart';
import '../../../widgets/lyrics/lyrics_view.dart';
import '../../../widgets/visualizer/spectrum_bars.dart';
import '../../../widgets/visualizer/reactor_visualizer.dart';
import '../../../widgets/visualizer/audio_bloom_flower.dart';
import '../../../widgets/card_stack.dart';
import 'immersive_player_visuals.dart';
import 'unified_player.dart';
import 'video_background.dart';
import 'steam_wallpaper_background.dart';

/// 主页沉浸播放器（常驻 [IndexedStack] 第 0 页）。
class HomeImmersivePlayer extends ConsumerStatefulWidget {
  const HomeImmersivePlayer({super.key});

  @override
  ConsumerState<HomeImmersivePlayer> createState() =>
      _HomeImmersivePlayerState();
}

class _HomeImmersivePlayerState extends ConsumerState<HomeImmersivePlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _coverSpin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    if (ref.read(isPlayingProvider).valueOrNull ?? false) _coverSpin.repeat();
  }

  @override
  void dispose() {
    _coverSpin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Track? track = ref.watch(nowPlayingProvider);
    // 当前播放器主题（默认 / 哔站视频 / 某个 Steam 壁纸）
    final String theme = ref.watch(playerThemeProvider);
    final List<ImportedWallpaper> walls = ref.watch(importedWallpapersProvider);
    ImportedWallpaper? wp;
    for (final ImportedWallpaper w in walls) {
      if (w.id == theme) {
        wp = w;
        break;
      }
    }
    // 播放态切换时启停唱片旋转；暂停即平滑停转，省 CPU。
    ref.listen<AsyncValue<bool>>(isPlayingProvider, (_, AsyncValue<bool> next) {
      final bool playing = next.valueOrNull ?? false;
      if (playing && !_coverSpin.isAnimating) {
        _coverSpin.repeat();
      } else if (!playing && _coverSpin.isAnimating) {
        _coverSpin.stop();
      }
    });

    return ImmersiveSurface(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 最底层（按主题）：哔站视频 / Steam 壁纸；默认主题无外部层，用渐变背景。
          if (theme == 'video')
            const Positioned.fill(child: VideoBackground()),
          if (wp != null)
            Positioned.fill(
              child: SteamWallpaperBackground(key: ValueKey<String>(wp.id), wallpaper: wp),
            ),
          // 动态背景：默认主题不透明渐变；视频/壁纸主题半透明让下层透出。
          Positioned.fill(
            child: ImmersiveBackground(
              track: track,
              videoThrough: theme != 'builtin',
            ),
          ),
          // 音频反应花 + 音效反应堆：仅在默认/视频主题叠加（壁纸主题本身即反应视觉）。
          if (theme == 'builtin' || theme == 'video') ...<Widget>[
            const Positioned.fill(child: AudioBloomFlower()),
            const Positioned.fill(child: ReactorVisualizer(opacity: 0.4)),
          ],
          // 前景内容（安全区 + 布局）。
          SafeArea(
            child: Column(
              children: <Widget>[
                // 顶部：问候 + 品牌 + 场景入口。诉求⑧：滚动时随顶栏一起淡出折叠。
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: ref.watch(topBarAutoHideProvider) ? 0.0 : 1.0,
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    alignment: Alignment.topCenter,
                    child: ref.watch(topBarAutoHideProvider)
                        ? const SizedBox.shrink()
                        : _HomeTopBar(onOpenScenes: _showSceneSheet),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext c, BoxConstraints bc) {
                      final bool landscape = bc.maxWidth >= bc.maxHeight * 1.1;
                      if (landscape) {
                        return _landscapeBody(
                          track: track,
                          maxHeight: bc.maxHeight,
                        );
                      }
                      return _portraitBody(track: track);
                    },
                  ),
                ),
                // 播放失败时常驻的错误 + 重试提示（与正在播放页共用同一组件）。
                const PlaybackErrorBanner(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 竖屏主体：大唱片 → 曲名/歌手 → 频谱 → 歌词。
  Widget _portraitBody({required Track? track}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpace.sm),
          Center(child: ImmersiveDiscCover(track: track, spin: _coverSpin, size: 240)),
          const SizedBox(height: AppSpace.lg),
          ImmersiveTrackTitle(track: track),
          const SizedBox(height: AppSpace.sm),
          const SpectrumBars(height: 44),
          const SizedBox(height: AppSpace.md),
          LyricsView(height: 220),
        ],
      ),
    );
  }

  /// 横屏主体：左封面、右信息 + 歌词。
  Widget _landscapeBody({required Track? track, required double maxHeight}) {
    final double coverSize = (maxHeight * 0.6).clamp(160.0, 320.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: coverSize + AppSpace.sm,
            child: Center(
              child: ImmersiveDiscCover(
                track: track,
                spin: _coverSpin,
                size: coverSize,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ImmersiveTrackTitle(track: track, alignLeft: true),
                const SizedBox(height: AppSpace.xs),
                const SpectrumBars(height: 36),
                const SizedBox(height: AppSpace.sm),
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext c, BoxConstraints bc) =>
                        LyricsView(height: bc.maxHeight),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 弹出场景选择浮窗（复用 [SceneCardStack]，场景切换降级为入口）。
  Future<void> _showSceneSheet() async {
    final List<Scene> scenes = ref.read(sceneOrderProvider);
    final int activeIndex = ref.read(currentSceneIndexProvider);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (BuildContext sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Text('场景', style: context.appText.title),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: SceneCardStack(
                    scenes: scenes,
                    currentIndex: activeIndex,
                    onLongPress: () => Navigator.of(sheetCtx).pop(),
                    onSceneChanged: (int i) {
                      HapticFeedback.lightImpact();
                      ref.read(currentSceneIndexProvider.notifier).state = i;
                      final Scene scene = scenes[i];
                      unawaited(
                        ref.read(audioServiceProvider).switchSoundscape(scene),
                      );
                    },
                  ),
                ),
              ),
              // 主题选择（默认 / 哔站视频 / 发现的 Steam 壁纸）
              Consumer(
                builder: (BuildContext ctx, WidgetRef sref, Widget? _) {
                  final String cur = sref.watch(playerThemeProvider);
                  final List<ImportedWallpaper> ws =
                      sref.watch(importedWallpapersProvider);
                  final List<Widget> chips = <Widget>[
                    ChoiceChip(
                      label: const Text('默认'),
                      selected: cur == 'builtin',
                      onSelected: (_) =>
                          sref.read(playerThemeProvider.notifier).state =
                              'builtin',
                    ),
                    ChoiceChip(
                      label: const Text('哔站视频'),
                      selected: cur == 'video',
                      onSelected: (_) =>
                          sref.read(playerThemeProvider.notifier).state =
                              'video',
                    ),
                    for (final ImportedWallpaper w in ws)
                      ChoiceChip(
                        label: Tooltip(
                          message: w.folderPath,
                          child: Text(
                            w.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        selected: cur == w.id,
                        onSelected: (_) =>
                            sref.read(playerThemeProvider.notifier).state =
                                w.id,
                      ),
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Text('主题', style: ctx.appText.title),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.md,
                          0,
                          AppSpace.md,
                          AppSpace.sm,
                        ),
                        child: Wrap(
                          spacing: AppSpace.sm,
                          runSpacing: AppSpace.sm,
                          children: chips,
                        ),
                      ),
                    ],
                  );
                },
              ),
              // 壁纸效果调节（仅当选中 Steam 壁纸主题时可用）
              Consumer(
                builder: (BuildContext ctx, WidgetRef sref, Widget? _) {
                  final String cur = sref.watch(playerThemeProvider);
                  final List<ImportedWallpaper> ws =
                      sref.watch(importedWallpapersProvider);
                  ImportedWallpaper? active;
                  for (final ImportedWallpaper w in ws) {
                    if (w.id == cur) {
                      active = w;
                      break;
                    }
                  }
                  if (active == null) return const SizedBox.shrink();
                  final Map<String, dynamic> fx =
                      sref.watch(wallpaperEffectsProvider);
                  void setFx(String k, dynamic v) => sref
                      .read(wallpaperEffectsProvider.notifier)
                      .state = <String, dynamic>{...fx, k: v};
                  final double intensity =
                      (fx['audioIntensity'] as double?) ?? 1.2;
                  final int grid = (fx['gridSize'] as int?) ?? 160;
                  final bool meteor = (fx['meteorEnabled'] as bool?) ?? true;
                  final double meteorS =
                      (fx['meteorSensitivity'] as double?) ?? 0.35;
                  final bool ripple = (fx['rippleEnabled'] as bool?) ?? true;
                  final double rippleS =
                      (fx['rippleSensitivity'] as double?) ?? 0.2;
                  final bool idle = (fx['idleWaveEnabled'] as bool?) ?? true;
                  final bool rotate =
                      (fx['autoRotateEnabled'] as bool?) ?? false;
                  final String fxTheme = (fx['theme'] as String?) ?? 'nocturnal';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Text('效果', style: ctx.appText.title),
                      ),
                      _EffectSlider(
                        label: '音频强度',
                        value: intensity,
                        min: 0.5,
                        max: 2.0,
                        divisions: 30,
                        fmt: (double v) => v.toStringAsFixed(2),
                        onChanged: (double v) => setFx('audioIntensity', v),
                      ),
                      _EffectSlider(
                        label: '网格密度',
                        value: grid.toDouble(),
                        min: 40,
                        max: 256,
                        divisions: 216,
                        fmt: (double v) => v.round().toString(),
                        onChanged: (double v) => setFx('gridSize', v.round()),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.md,
                          0,
                          AppSpace.md,
                          AppSpace.sm,
                        ),
                        child: Wrap(
                          spacing: AppSpace.sm,
                          children: <Widget>[
                            ChoiceChip(
                              label: const Text('夜行'),
                              selected: fxTheme == 'nocturnal',
                              onSelected: (_) => setFx('theme', 'nocturnal'),
                            ),
                            ChoiceChip(
                              label: const Text('日间'),
                              selected: fxTheme == 'day',
                              onSelected: (_) => setFx('theme', 'day'),
                            ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('流星'),
                        value: meteor,
                        onChanged: (bool v) => setFx('meteorEnabled', v),
                      ),
                      if (meteor)
                        _EffectSlider(
                          label: '流星灵敏度',
                          value: meteorS,
                          min: 0,
                          max: 1,
                          divisions: 20,
                          fmt: (double v) => v.toStringAsFixed(2),
                          onChanged: (double v) =>
                              setFx('meteorSensitivity', v),
                        ),
                      SwitchListTile(
                        title: const Text('涟漪'),
                        value: ripple,
                        onChanged: (bool v) => setFx('rippleEnabled', v),
                      ),
                      if (ripple)
                        _EffectSlider(
                          label: '涟漪灵敏度',
                          value: rippleS,
                          min: 0,
                          max: 1,
                          divisions: 20,
                          fmt: (double v) => v.toStringAsFixed(2),
                          onChanged: (double v) =>
                              setFx('rippleSensitivity', v),
                        ),
                      SwitchListTile(
                        title: const Text('空闲波浪'),
                        value: idle,
                        onChanged: (bool v) => setFx('idleWaveEnabled', v),
                      ),
                      SwitchListTile(
                        title: const Text('自动旋转'),
                        value: rotate,
                        onChanged: (bool v) => setFx('autoRotateEnabled', v),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.md,
                          0,
                          AppSpace.md,
                          AppSpace.md,
                        ),
                        child: TextButton.icon(
                          onPressed: () => sref
                              .read(wallpaperEffectsProvider.notifier)
                              .state = Map<String, dynamic>.from(
                            kDefaultWallpaperEffects,
                          ),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('重置为默认'),
                        ),
                      ),
                    ],
                  );
                },
              ),
              // 视频背景控制（哔站视频作模糊背景）。
              Consumer(
                builder: (BuildContext ctx, WidgetRef sref, Widget? _) {
                  if (sref.watch(playerThemeProvider) != 'video') {
                    return const SizedBox.shrink();
                  }
                  final bool videoOn = sref.watch(homeVideoEnabledProvider);
                  final double blur = sref.watch(homeVideoBlurProvider);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Divider(height: 1),
                      SwitchListTile(
                        title: Text('视频背景', style: ctx.appText.title),
                        subtitle: Text(
                          '哔站视频作模糊背景（静音）',
                          style: ctx.appText.caption,
                        ),
                        value: videoOn,
                        onChanged: (bool v) =>
                            sref.read(homeVideoEnabledProvider.notifier).state = v,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.md,
                          0,
                          AppSpace.md,
                          AppSpace.sm,
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.blur_on,
                                size: 18, color: Colors.white70),
                            const SizedBox(width: AppSpace.sm),
                            Expanded(
                              child: Slider(
                                min: 0,
                                max: 40,
                                divisions: 40,
                                value: blur,
                                label: blur.toStringAsFixed(0),
                                onChanged: (double v) => sref
                                    .read(homeVideoBlurProvider.notifier)
                                    .state = v,
                              ),
                            ),
                            SizedBox(
                              width: 34,
                              child: Text(
                                blur.toStringAsFixed(0),
                                style: ctx.appText.caption,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 主页顶部条：问候 + 品牌 + 场景入口。
class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({required this.onOpenScenes});

  final VoidCallback onOpenScenes;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final String greet = _greeting(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.xs,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  greet,
                  style: context.appText.caption.copyWith(
                    color: Colors.white70,
                    fontSize: 13,
                    shadows: kImmersiveTextShadow,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '星璃音乐',
                  style: context.appText.title.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: kImmersiveTextShadow,
                  ),
                ),
              ],
            ),
          ),
          // 场景入口（原场景卡堆降级为小入口）。
          Material(
            color: Colors.white.withValues(alpha: 0.12),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onOpenScenes,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _greeting(DateTime now) {
    final int h = now.hour;
    if (h >= 5 && h < 11) return '早安，新的一天听点什么？';
    if (h >= 11 && h < 14) return '午安，听点什么？';
    if (h >= 14 && h < 18) return '下午好，听点什么？';
    if (h >= 18 && h < 23) return '晚上好，听点什么？';
    return '夜深了，听点什么？';
  }
}

/// 壁纸「效果」滑杆（主页场景浮窗内，仅壁纸主题可见）。
class _EffectSlider extends StatelessWidget {
  const _EffectSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.fmt,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) fmt;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        0,
        AppSpace.md,
        AppSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(label, style: context.appText.caption),
          ),
          Expanded(
            child: Slider(
              min: min,
              max: max,
              divisions: divisions,
              value: value,
              label: fmt(value),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              fmt(value),
              style: context.appText.caption,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

