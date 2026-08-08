import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/palette.dart';
import '../../models/scene.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/mood/mood_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/session/session_providers.dart';
import '../../providers/theme/theme_providers.dart';
import '../../widgets/card_stack.dart';
import '../../widgets/control_bar.dart';
import '../../widgets/more_panel.dart';
import '../../widgets/volume_slider.dart';
import '../../widgets/noise_texture.dart';
import '../../providers/storage/storage_providers.dart';
import '../../widgets/reactive_particles.dart';
import '../../widgets/scene_particles.dart';

/// 音乐空间主页面（V1.0）
///
///  - 背景：场景派生色渐变 + 噪点纹理
///  - 粒子：主色派生色，高密度缓慢漂移
///  - 卡片：中央主视觉单元
///  - 右上角调色盘 / 左上角心情
///  - 底部控制区（上滑展开更多面板）
class CanvasPage extends ConsumerStatefulWidget {
  const CanvasPage({super.key});

  @override
  ConsumerState<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends ConsumerState<CanvasPage> {
  bool _panelOpen = false;
  bool _moodOpen = false;

  // 无操作漂移（5 分钟）
  Timer? _idleDriftTimer;
  int _drift = 0;

  static const List<String> _moods = ['愉悦', '平静', '低落', '兴奋'];

  @override
  void initState() {
    super.initState();
    // 启动：播放当前场景音景（按需生成，其余场景切换时再生成）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final Scene scene = ref.read(activeSceneProvider);
      unawaited(ref.read(audioServiceProvider).switchSoundscape(scene));
    });
    // 无操作 5 分钟：粒子/背景缓慢漂移一次（界面保持"活着"）
    _idleDriftTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) setState(() => _drift++);
    });
  }

  @override
  void dispose() {
    _idleDriftTimer?.cancel();
    super.dispose();
  }

  void _onSceneChanged(int index) {
    ref.read(currentSceneIndexProvider.notifier).state = index;
    final Scene scene = ref.read(sceneOrderProvider)[index];
    unawaited(ref.read(audioServiceProvider).switchSoundscape(scene));
    // 习惯性交互：自然记录场景驻留（不打扰用户，供配色记忆使用）
    if (ref.read(usageDbProvider).value != null) {
      unawaited(
        ref.read(usageRepositoryProvider).logEvent(
          type: 'scene_dwell',
          payload: {
            'sceneId': scene.id,
            'mood': scene.mood,
            'valence': scene.valence,
            'energy': scene.energy,
          },
        ),
      );
    }
  }

  void _pickMood(String mood) {
    ref.read(moodKindProvider.notifier).state =
        mood == '愉悦' ? 'warm' : mood == '平静' ? 'calm' : mood == '低落' ? 'dim' : 'bright';
    setState(() => _moodOpen = false);
    _applyMoodAudio(ref.read(moodKindProvider));
  }

  /// 心情 → 心情圆点颜色
  Color _moodColor(String moodKind) {
    return switch (moodKind) {
      'warm' => const Color(0xFFFFB05A),
      'dim' => const Color(0xFF4A7BFF),
      'bright' => const Color(0xFFFF7BFF),
      _ => const Color(0xFF9B7BFF),
    };
  }

  /// 粒子运动风格按场景派生（自定义场景优先读 particleMotion）
  ParticleMotion _sceneParticleMotion(Scene scene) {
    return switch (scene.particleMotion) {
      'rain' => ParticleMotion.rainDown,
      'snow' => ParticleMotion.snowDown,
      'fireplace' => ParticleMotion.emberUp,
      'ocean' => ParticleMotion.bubbleUp,
      'dust' => ParticleMotion.floatUp,
      _ => switch (scene.id) {
          'rain' => ParticleMotion.rainDown,
          'snow' => ParticleMotion.snowDown,
          'fireplace' => ParticleMotion.emberUp,
          'ocean' => ParticleMotion.bubbleUp,
          _ => ParticleMotion.floatUp,
        },
    };
  }

  /// 粒子颜色按场景派生（自定义场景优先读 particleColor）
  Color _sceneParticleColor(Scene scene, DerivedPalette palette) {
    if (scene.particleColor != null) return scene.particleColor!;
    return switch (scene.id) {
      'rain' => const Color(0xFFB8B8C4),
      'snow' => const Color(0xFFE8EEF4),
      'fireplace' => const Color(0xFFFF9B5A),
      'ocean' => const Color(0xFF7BB8FF),
      _ => palette.particle,
    };
  }

  /// 心情 → 音乐/音景强度
  void _applyMoodAudio(String moodKind) {
    final (double music, double soundscape) = switch (moodKind) {
      'warm' => (0.90, 0.30),
      'bright' => (1.00, 0.35),
      'dim' => (0.65, 0.15),
      _ => (0.80, 0.25),
    };
    unawaited(ref.read(audioServiceProvider)
        .setMoodIntensity(music: music, soundscape: soundscape));
  }

  @override
  Widget build(BuildContext context) {
    final List<Scene> scenes = ref.watch(sceneOrderProvider);
    final int activeIndex = ref.watch(currentSceneIndexProvider);
    final Scene activeScene = ref.watch(activeSceneProvider);
    // 「我的世界」主题音效调度联动：进入/离开场景自动启停
    ref.listen<Scene>(activeSceneProvider, (prev, next) {
      unawaited(
          ref.read(minecraftSfxServiceProvider).ensureScene(next.id));
    });
    final DerivedPalette palette = ref.watch(derivedPaletteProvider);
    final int sessionSeed = ref.watch(sessionSeedProvider);

    final bool isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;
    final bool paletteOpen = ref.watch(paletteOpenProvider);
    final double safeBottom = MediaQuery.of(context).padding.bottom;

    // 背景：场景基础色 → 派生背景（顶略亮，底略暗），1.5s 过渡
    // 自定义场景优先读 bgTop / bgBottom
    final Color sceneBase = activeScene.bgTop ??
        activeScene.visual.gradientColors.first;
    final Color sceneBottom = activeScene.bgBottom ?? palette.background;
    final HSLColor baseHsl = HSLColor.fromColor(sceneBase);
    final List<Color> bgColors = [
      activeScene.bgTop != null
          ? sceneBase
          : baseHsl
              .withLightness((baseHsl.lightness + 0.10).clamp(0.0, 0.30))
              .toColor(),
      sceneBottom,
    ];

    // ── 暗色主题孤岛（架构 §1.1 优化③ / 约定 C3）──────────────
    // 全应用已切固定浅色（kLightTheme）。本页是沉浸式画布，必须保留原有的
    // 「由用户主色实时派生」的深色观感，因此在这里、也只在这里（以及
    // PaletteStudioPage）重新套一层 buildAppTheme()。
    // 这样 ControlBar / MorePanel / VolumeSlider / PalettePanel 等既有组件
    // 对 Theme.of(context) 的依赖全部照旧成立，零改动继续服役。
    //
    // 包一层 Scaffold：为 SnackBar 提供宿主；背景透明全屏
    // resizeToAvoidBottomInset=false：避免窗口 inset 变化触发 Overlay 重排
    return Theme(
      data: buildAppTheme(ref.watch(effectivePrimaryProvider)),
      child: Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_panelOpen) setState(() => _panelOpen = false);
          if (_moodOpen) setState(() => _moodOpen = false);
          if (paletteOpen) {
            ref.read(paletteOpenProvider.notifier).state = false;
          }
          if (ref.read(volumeSliderOpenProvider)) {
            ref.read(volumeSliderOpenProvider.notifier).state = false;
          }
        },
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 1500),
        curve: Curves.linear,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: bgColors,
            stops: const [0.3, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // ── 噪点纹理 ─────────────────────────────
            const Positioned.fill(child: NoiseTexture()),

            // ── 粒子层（运动/颜色随场景变化，可全局开关）──
            if (ref.watch(showParticlesProvider))
              Positioned.fill(
                child: ReactiveParticles(
                  color: _sceneParticleColor(activeScene, palette),
                  motion: _sceneParticleMotion(activeScene),
                  seed: sessionSeed ^ (activeIndex * 7919) ^ _drift,
                ),
              ),

            SafeArea(
              child: Stack(
                children: [
                  // ── 场景卡片（中央）───────────────────
                  Positioned(
                    top: 60,
                    left: 0,
                    right: 0,
                    bottom: 140 + safeBottom,
                    child: SceneCardStack(
                      scenes: scenes,
                      currentIndex: activeIndex,
                      nowPlaying: ref.watch(nowPlayingProvider),
                      isPlaying: isPlaying,
                      onSceneChanged: _onSceneChanged,
                    ),
                  ),

                  // ── 左上角：返回按钮（P0-G3 / F4）──────
                  // 画布是全屏路由（脱离 Shell，无 Dock 与迷你播放器），
                  // 必须有明确的返回入口，否则用户只能靠系统手势。
                  const Positioned(
                    top: 8,
                    left: 12,
                    child: _CanvasBackButton(),
                  ),

                  // ── 心情入口（右移 52dp 给返回按钮让位，约定 A9）──
                  Positioned(
                    top: 8,
                    left: 64,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () =>
                              setState(() => _moodOpen = !_moodOpen),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _moodColor(ref.watch(moodKindProvider))
                                  .withValues(alpha: 0.25),
                              border: Border.all(
                                color: _moodColor(
                                        ref.watch(moodKindProvider))
                                    .withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        if (_moodOpen)
                          AnimatedScale(
                            scale: _moodOpen ? 1.0 : 0.6,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            child: Card(
                              margin: const EdgeInsets.only(top: 6),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: _moods.map((m) {
                                  final String kind = m == '愉悦'
                                      ? 'warm'
                                      : m == '平静'
                                          ? 'calm'
                                          : m == '低落'
                                              ? 'dim'
                                              : 'bright';
                                  final bool active =
                                      ref.watch(moodKindProvider) == kind;
                                  return InkWell(
                                    onTap: () => _pickMood(m),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        m,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: active
                                                  ? palette.highlight
                                                  : Colors.white54,
                                            ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── 底部：控制区 + 更多面板 ────────────
                  // 控制区常驻，上滑展开更多面板
                  // 设置与调色盘入口已移入「更多」面板
                  if (!_panelOpen)
                    Positioned(
                      bottom: 16 + safeBottom,
                      left: 0,
                      right: 0,
                      child: ControlBar(
                        onSwipeUp: () => setState(() => _panelOpen = true),
                      ),
                    ),

                  MorePanel(
                    isOpen: _panelOpen,
                    onClose: () => setState(() => _panelOpen = false),
                    safeBottom: safeBottom,
                  ),

                  VolumeSlider(safeBottom: safeBottom),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
      ),
    );
  }
}

/// 画布左上角返回按钮（40dp 半透明圆，约定 A9）
///
/// 画布可能作为根页面存在（历史入口）也可能是 push 出来的全屏路由，
/// 因此先判断 `canPop()` —— 不可返回时直接隐藏，避免出现按了没反应的死按钮。
class _CanvasBackButton extends StatelessWidget {
  const _CanvasBackButton();

  @override
  Widget build(BuildContext context) {
    if (!Navigator.of(context).canPop()) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        ),
        child: const Icon(
          Icons.arrow_back,
          size: 20,
          color: Colors.white70,
        ),
      ),
    );
  }
}
