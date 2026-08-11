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
import '../voxel/voxel_camera.dart';
import '../voxel/voxel_capture_models.dart';
import '../voxel/voxel_renderer.dart';
import '../voxel/voxel_world.dart';

/// 场景背景：体素世界取景快照实时重绘层。
class VoxelSceneBackground extends ConsumerStatefulWidget {
  const VoxelSceneBackground({super.key, required this.capture});

  final VoxelSceneCapture capture;

  @override
  ConsumerState<VoxelSceneBackground> createState() =>
      _VoxelSceneBackgroundState();
}

class _VoxelSceneBackgroundState extends ConsumerState<VoxelSceneBackground>
    with SingleTickerProviderStateMixin {
  late VoxelWorld _world;
  late VoxelCamera _camera;
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
    _ticker = createTicker(_onTick)..start();
  }

  void _rebuild(VoxelSceneCapture cap) {
    _world = cap.toWorld();
    _camera = cap.toCamera();
    _timePhase = cap.timePhase;
    _wave = 0;
    _dirty = true;
  }

  @override
  void didUpdateWidget(covariant VoxelSceneBackground old) {
    super.didUpdateWidget(old);
    if (old.capture != widget.capture) _rebuild(widget.capture);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
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
    // R21：两档（性能/质量）+ 全局帧率限制 + 背景动画独立开关。
    // R20 期间 Windows 强制静态帧的降级已随无障碍桥崩溃根治而还原，
    // 动画/渐变完全跟随档位与开关。
    final PerformanceMode mode = ref.watch(performanceModeProvider);
    _config = _configFor(mode);
    _interval = Duration(
      milliseconds: 1000 ~/ ref.watch(fpsLimitProvider).value,
    );
    // 背景动画开关：质量档默认开，性能档默认关；可手动覆盖。
    _static = !ref.watch(bgAnimationEnabledProvider) ||
        mode == PerformanceMode.performance;

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

  static RenderConfig _configFor(PerformanceMode m) => switch (m) {
    // 性能：近距离 + 低面数 + 关雾 / 关天空细节 / 关水波
    PerformanceMode.performance => const RenderConfig(
        renderDistance: 18,
        maxFaces: 1200,
        fogEnabled: false,
        waterAnimation: false,
        skyGradient: false,
      ),
    PerformanceMode.quality => const RenderConfig(
        renderDistance: 40,
        maxFaces: 5000,
      ),
  };
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

    _drawFaces(canvas, f.opaque);
    _drawFaces(canvas, f.translucent);
  }

  void _drawFaces(Canvas canvas, List<RenderFace> faces) {
    final int n = faces.length;
    if (n == 0) return;
    final Float32List positions = Float32List(n * 12);
    final Int32List colors = Int32List(n * 6);
    int p = 0;
    int c = 0;
    for (int i = 0; i < n; i++) {
      final RenderFace f = faces[i];
      final Float32List v = f.xy;
      final int argb = f.argb;
      // 三角 1：0-1-2
      positions[p++] = v[0];
      positions[p++] = v[1];
      positions[p++] = v[2];
      positions[p++] = v[3];
      positions[p++] = v[4];
      positions[p++] = v[5];
      // 三角 2：0-2-3
      positions[p++] = v[0];
      positions[p++] = v[1];
      positions[p++] = v[4];
      positions[p++] = v[5];
      positions[p++] = v[6];
      positions[p++] = v[7];
      for (int k = 0; k < 6; k++) {
        colors[c++] = argb;
      }
    }
    final ui.Vertices vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
    );
    canvas.drawVertices(vertices, ui.BlendMode.modulate, _vertexPaint);
    vertices.dispose();
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter old) =>
      old.frame != frame || old.skyGradient != skyGradient;
}
