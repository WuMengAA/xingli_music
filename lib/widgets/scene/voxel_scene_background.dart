/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 · 场景背景（Phase 4 · 拍照取景 → 场景背景实时渲染）
/// ════════════════════════════════════════════════════════════════════════
///
/// 把一张 [VoxelSceneCapture] 作为播放器场景的背景层。
/// - 相机固定，低帧率重绘动态元素（水波 / 叶摇 / 天光相位）；
/// - 省电模式退化为静态单帧（不重绘动画）；
/// - 背景在下、液态玻璃在上，互不破坏（见 `docs/体素世界技术方案.md` §G-3）。
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings/performance_providers.dart';
import '../../providers/audio/audio_providers.dart';
import '../voxel/voxel_camera.dart';
import '../voxel/voxel_capture_models.dart';
import '../voxel/voxel_renderer.dart';
import '../voxel/voxel_world.dart';
import '../voxel/world_audio_engine.dart';

/// 场景背景：体素世界取景快照实时重绘层。
///
/// H2：若快照携带 16×16 音效源（[VoxelSceneCapture.sounds]），同时用
/// [WorldAudioEngine] 原样重放（同 seed 世界 + 同机位 → 听感一致）。
class VoxelSceneBackground extends ConsumerStatefulWidget {
  const VoxelSceneBackground({
    super.key,
    required this.capture,
    this.forceLive = false,
  });

  final VoxelSceneCapture capture;

  /// H2：强制实时渲染（长按背景开关开启；省电/性能档也不退化静态帧）。
  final bool forceLive;

  @override
  ConsumerState<VoxelSceneBackground> createState() =>
      _VoxelSceneBackgroundState();
}

class _VoxelSceneBackgroundState extends ConsumerState<VoxelSceneBackground>
    with SingleTickerProviderStateMixin {
  late VoxelWorld _world;
  late VoxelCamera _camera;
  WorldAudioEngine? _audio;
  final ValueNotifier<VoxelFrame> _frame =
      ValueNotifier<VoxelFrame>(VoxelFrame.empty);
  late final Ticker _ticker;

  Size _viewport = Size.zero;
  double _wave = 0;
  double _timePhase = 0.25;
  bool _dirty = true;
  Duration _lastTick = Duration.zero;
  late RenderConfig _config;
  late Duration _interval;
  bool _static = false;

  @override
  void initState() {
    super.initState();
    _rebuild(widget.capture);
    _initAudio();
    _ticker = createTicker(_onTick)..start();
  }

  void _rebuild(VoxelSceneCapture cap) {
    _world = cap.toWorld();
    _camera = cap.toCamera();
    _timePhase = cap.timePhase;
    _wave = 0;
    _dirty = true;
  }

  /// H2：快照携带 16×16 音效源时，用同 seed 世界 + 同机位原样重放。
  void _initAudio() {
    _audio?.dispose();
    _audio = null;
    final List<VoxelSoundscapeSource> sounds = widget.capture.sounds;
    if (sounds.isEmpty) return;
    final List<WorldAudioSource> sources = sounds
        .map((VoxelSoundscapeSource s) => WorldAudioSource(
              id: '${s.kind}_${s.x.toStringAsFixed(0)}_${s.y.toStringAsFixed(0)}_${s.z.toStringAsFixed(0)}',
              kind: WorldSfx.values.firstWhere(
                (WorldSfx k) => k.name == s.kind,
                orElse: () => WorldSfx.wind,
              ),
              x: s.x,
              y: s.y,
              z: s.z,
              strength: s.strength,
            ))
        .toList();
    _audio = WorldAudioEngine(_world, presetSources: sources)
      ..setGlobalVolume(_scVolume)
      ..onCamera(_camera);
  }

  double get _scVolume {
    final bool muted = ref.read(soundscapeMutedProvider);
    final double vol = ref.read(soundscapeVolumeProvider);
    return muted ? 0 : vol.clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant VoxelSceneBackground old) {
    super.didUpdateWidget(old);
    if (old.capture != widget.capture) {
      _rebuild(widget.capture);
      _initAudio();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _audio?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    // H2：每 tick 把固定机位喂给音效引擎（内部 400ms 节流），保持空间声像。
    _audio?.onCamera(_camera);
    if (_lastTick != Duration.zero && elapsed - _lastTick < _interval) return;
    final double dt = _lastTick == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.25);
    _lastTick = elapsed;

    if (_static) {
      // 省电：只渲染一次静态帧（水面静止）。
      if (_dirty && !_viewport.isEmpty) {
        _dirty = false;
        _frame.value = VoxelRenderer.buildFrame(
          world: _world,
          camera: _camera,
          viewport: _viewport,
          config: _config,
          wavePhase: 0,
          timePhase: _timePhase,
        );
      }
      return;
    }

    if (_config.waterAnimation) {
      _wave = (_wave + dt * 0.35) % 1000;
      _dirty = true;
    }
    if (!_dirty || _viewport.isEmpty) return;
    _dirty = false;
    _frame.value = VoxelRenderer.buildFrame(
      world: _world,
      camera: _camera,
      viewport: _viewport,
      config: _config,
      wavePhase: _wave,
      timePhase: _timePhase,
    );
  }

  @override
  Widget build(BuildContext context) {
    // R26skel-b4：场景背景画质**独立于游戏画质**——改用场景专用 provider
    // （画质档/帧率/雾/水波/天空/动画），游戏怎么调都不影响背景；反之亦然。
    // 原实现跟随 performanceModeProvider/fpsLimitProvider/bgAnimationEnabledProvider
    // （游戏画质预设会连带背景），现彻底解耦。
    _config = _configFor(
      ref.watch(sceneBgQualityProvider),
      fog: ref.watch(sceneBgFogProvider),
      water: ref.watch(sceneBgWaterProvider),
      sky: ref.watch(sceneBgSkyProvider),
    );
    _interval = Duration(
      milliseconds:
          (1000 ~/ ref.watch(sceneBgFpsProvider)).clamp(16, 1000).toInt(),
    );
    // H2：音量变化实时下发到背景音效引擎（含静音）。
    ref.listen<double>(soundscapeVolumeProvider,
        (double? _, double v) => _audio?.setGlobalVolume(v));
    ref.listen<bool>(soundscapeMutedProvider, (bool? _, bool m) {
      _audio?.setGlobalVolume(
          m ? 0 : ref.read(soundscapeVolumeProvider).clamp(0.0, 1.0));
    });
    // 实时渲染 = 「场景页实时开关」与「设置·动画」的联动结果（scene_page 已
    // 取并集传入 forceLive）。二者任一开启即实时重绘；均关 = 静态单帧省电。
    _static = !widget.forceLive;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Size size = Size(c.maxWidth, c.maxHeight);
        if (size != _viewport) {
          _viewport = size;
          _dirty = true;
        }
        return RepaintBoundary(
          child: CustomPaint(
            painter: _BackgroundPainter(
              frame: _frame,
              skyGradient: _config.skyGradient,
            ),
            size: size,
          ),
        );
      },
    );
  }

  static RenderConfig _configFor(
    SceneBgQuality q, {
    required bool fog,
    required bool water,
    required bool sky,
  }) =>
      RenderConfig(
        renderDistance: q.renderDistance.toDouble(),
        maxFaces: q.maxFaces,
        fogEnabled: fog,
        waterAnimation: water,
        skyGradient: sky,
      );
}

/// 把一帧 [VoxelFrame] 画到画布：天空渐变 → 不透明面 → 半透明面。
///
/// 复用 `voxel_world_view3d.dart` 的批提交策略：每趟面一个 `Vertices`，
/// draw call 降到 2 次。`BlendMode.modulate` + 纯白 paint ⇒ 顶点色原样输出。
class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({required this.frame, required this.skyGradient})
      : super(repaint: frame);

  final ValueListenable<VoxelFrame> frame;
  final bool skyGradient;

  static final Paint _vertexPaint = Paint()..color = const Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final VoxelFrame f = frame.value;
    final Rect rect = Offset.zero & size;

    final Paint sky = Paint();
    if (skyGradient) {
      sky.shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        <Color>[f.sky.zenith, f.sky.horizon],
      );
    } else {
      sky.color = f.sky.horizon;
    }
    canvas.drawRect(rect, sky);

    // R26/O4：批量桶（与游戏渲染同路径），远→近逐桶提交，画家算法正确。
    // 原为逐面 RenderFace 列表（每帧分配 RenderFace 对象）；现统一走 8 桶
    // drawVertices，消除每帧冗余对象分配。背景沿用「顶点色平涂」（忽略贴图
    // UV），与原视觉效果一致。
    for (int i = 7; i >= 0; i--) {
      final VoxelMeshBatch? plain = f.opaquePlainBuckets[i];
      if (plain != null) _drawBatch(canvas, plain);
      final VoxelMeshBatch? tex = f.opaqueTexturedBuckets[i];
      if (tex != null) _drawBatch(canvas, tex);
      final VoxelMeshBatch? water = f.waterBuckets[i];
      if (water != null) _drawBatch(canvas, water);
    }
  }

  void _drawBatch(Canvas canvas, VoxelMeshBatch b) {
    final ui.Vertices vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      b.positions,
      colors: b.colors,
    );
    canvas.drawVertices(vertices, ui.BlendMode.modulate, _vertexPaint);
    vertices.dispose();
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter old) =>
      old.frame != frame || old.skyGradient != skyGradient;
}
