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
            Positioned.fill(child: SteamWallpaperBackground(wallpaper: wp)),
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
              // 视频背景控制（哔站视频作模糊背景）。
              Consumer(
                builder: (BuildContext ctx, WidgetRef sref, Widget? _) {
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

