/// ════════════════════════════════════════════════════════════════════════
/// 液态玻璃 · 性能基准（Liquid Glass Benchmark）
/// ════════════════════════════════════════════════════════════════════════
///
/// 背景：部分安卓手机无法加载液态玻璃（premium 真折射走自定义 fragment
/// shader + 纹理捕获，Mali GPU / 老驱动 / Impeller 不兼容时首帧卡顿或
/// 渲染失败——这是 premium 路径专属问题，standard/minimal 不触发）。
///
/// 本页在**当前设备**上实测三档（premium / standard / minimal）的光栅帧
/// 耗时（raster duration），输出 P50/P75/P95/P99 与推荐档位，用于：
///   1. 量化「这台机器扛不扛得住 premium」；
///   2. 对照包内 GlassQualityAdapter 阈值（P75<20ms→premium，
///      20~28ms→standard，>28ms→minimal）给出降级建议；
///   3. 展示 shader 支持探测结果（`isShaderFilterSupported==false` 时
///      任何 shader 档都不可用，应强制 minimal/关闭玻璃）。
///
/// 纯测量工具，不改任何运行时设置；挂载在 设置→关于→开发者工具。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';
import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/performance_providers.dart';

/// 三档测量顺序。
const List<GlassQuality> kBenchmarkTiers = <GlassQuality>[
  GlassQuality.premium,
  GlassQuality.standard,
  GlassQuality.minimal,
];

/// 跳过首段帧数（等 shader 编译/首次路由稳定，包内适配器用 90）。
const int kSkipFrames = 60;

/// 每档采集帧数（60fps ≈ 2 秒）。
const int kCollectFrames = 120;

/// 一档的测量结果。
class _TierResult {
  _TierResult({required this.quality, required this.samples});
  final GlassQuality quality;
  final List<int> samples; // raster duration in µs

  double _pct(int p) {
    if (samples.isEmpty) return 0;
    final List<int> s = List<int>.from(samples)..sort();
    final int idx = ((s.length - 1) * p / 100).round();
    return s[idx] / 1000.0; // ms
  }

  double get p50 => _pct(50);
  double get p75 => _pct(75);
  double get p95 => _pct(95);
  double get p99 => _pct(99);
  int get count => samples.length;
}

/// 液态玻璃性能基准页。
class LiquidGlassBenchmarkPage extends ConsumerStatefulWidget {
  const LiquidGlassBenchmarkPage({super.key});

  @override
  ConsumerState<LiquidGlassBenchmarkPage> createState() =>
      _LiquidGlassBenchmarkPageState();
}

class _LiquidGlassBenchmarkPageState
    extends ConsumerState<LiquidGlassBenchmarkPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  bool _running = false;
  String _message = '';
  GlassQuality _previewQuality = GlassQuality.standard;
  final Map<GlassQuality, _TierResult> _results =
      <GlassQuality, _TierResult>{};

  /// 本次测量中已跳过/已采集的帧计数（按需渲染进度）。
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    // 持续动画保证帧产出（静态页面不重绘就没有新帧可供计时）。
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _runBenchmark() async {
    if (_running) return;
    setState(() {
      _running = true;
      _message = '正在测量…';
      _results.clear();
      _progress = 0;
    });

    // shader 支持探测：不支持的机器任何 shader 档都测不出真实结果。
    final bool shaderOk = ui.ImageFilter.isShaderFilterSupported;

    for (final GlassQuality q in kBenchmarkTiers) {
      // 切换预览档位，触发重渲染。
      setState(() => _previewQuality = q);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final List<int> raw = <int>[];
      int skipped = 0;
      final Completer<void> done = Completer<void>();

      void onTimings(List<FrameTiming> timings) {
        for (final FrameTiming t in timings) {
          if (skipped < kSkipFrames) {
            skipped++;
            continue;
          }
          raw.add(t.rasterDuration.inMicroseconds);
          if (raw.length >= kCollectFrames) {
            if (!done.isCompleted) done.complete();
            return;
          }
        }
        if (mounted) {
          setState(() => _progress = raw.length);
        }
      }

      SchedulerBinding.instance.addTimingsCallback(onTimings);
      try {
        await done.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {}, // 超时也收尾（保留已采集样本）
        );
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(onTimings);
      }

      if (raw.isNotEmpty && mounted) {
        setState(() {
          _results[q] = _TierResult(quality: q, samples: raw);
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _progress = 0;
      _message = _buildRecommendation(shaderOk);
    });
  }

  String _buildRecommendation(bool shaderOk) {
    if (_results.isEmpty) return '未采集到帧数据，请重试。';
    if (!shaderOk) {
      return '⚠️ 本设备不支持自定义 shader（isShaderFilterSupported=false）。'
          'premium/standard 均不可用，应强制 minimal（纯模糊兜底）或关闭玻璃。';
    }
    final _TierResult? premium = _results[GlassQuality.premium];
    if (premium == null) return '测量未完成。';
    final double p75 = premium.p75;
    if (p75 < 20) {
      return '✅ 推荐 premium：P75=${p75.toStringAsFixed(1)}ms < 20ms，'
          '本机能扛住完整折射 shader。';
    }
    if (p75 <= 28) {
      return '🟡 推荐 standard：P75=${p75.toStringAsFixed(1)}ms（20~28ms），'
          'premium 偏紧，用轻量 shader 更稳。';
    }
    return '🔴 推荐 minimal：P75=${p75.toStringAsFixed(1)}ms > 28ms，'
        '本机 GPU 预算不足，用零 shader 的纯模糊兜底。';
  }

  @override
  Widget build(BuildContext context) {
    final bool shaderOk = ui.ImageFilter.isShaderFilterSupported;
    final EngineBackend backend = ref.watch(engineBackendProvider);

    return Scaffold(
      backgroundColor: context.appColors.bgSurfaceSunken,
      appBar: AppBar(
        backgroundColor: context.appColors.bgSurface,
        foregroundColor: context.appColors.textPrimary,
        title: Text('液态玻璃 · 性能基准', style: context.appText.subtitle),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: <Widget>[
          const SizedBox(height: AppSpace.lg),

          // ═══ 设备能力 ═══
          _Card(
            title: '设备能力',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _InfoRow(
                  label: '图形后端',
                  value: backend.name,
                ),
                _InfoRow(
                  label: 'shader 支持',
                  value: shaderOk ? '✔ 支持' : '✘ 不支持（应强制 minimal）',
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  '包内阈值：premium 需 P75<20ms；standard 需 ≤28ms；'
                  '超过则建议 minimal（零 shader 兜底）。',
                  style: context.appText.caption.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),

          // ═══ 预览面板（当前档位）═══
          _Card(
            title: '实时预览（当前测量档：${_qualityLabel(_previewQuality)}）',
            child: SizedBox(
              height: 140,
              child: Stack(
                children: <Widget>[
                  // 有内容可折射/模糊的动态背景
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _anim,
                      builder: (BuildContext context, Widget? _) {
                        final double t = _anim.value;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: <Color>[
                                HSLColor.fromAHSL(
                                  1,
                                  (t * 360) % 360,
                                  0.6,
                                  0.5,
                                ).toColor(),
                                HSLColor.fromAHSL(
                                  1,
                                  ((t * 360) + 120) % 360,
                                  0.5,
                                  0.35,
                                ).toColor(),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Xingli Glass',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // 玻璃面板
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: AdaptiveGlass(
                        shape: LiquidRoundedSuperellipse(
                          borderRadius: 20,
                        ),
                        quality: _previewQuality,
                        settings: LiquidGlassSettings(
                          blur: 18,
                          glassColor: Colors.white.withValues(alpha: 0.10),
                          thickness: _previewQuality == GlassQuality.premium
                              ? 34
                              : 14,
                          refractiveIndex:
                              _previewQuality == GlassQuality.premium
                                  ? 1.2
                                  : 1.05,
                          chromaticAberration:
                              _previewQuality == GlassQuality.premium
                                  ? 0.096
                                  : 0.012,
                          saturation: 1.4,
                          glowIntensity: _previewQuality == GlassQuality.premium
                              ? 0.7
                              : 0.4,
                          fresnelStrength:
                              _previewQuality == GlassQuality.premium
                                  ? 1.2
                                  : 1.0,
                          ambientRim: _previewQuality == GlassQuality.premium
                              ? 0.2
                              : 0.0,
                          shadowElevation: 1.0,
                          whitenStrength: 0.0,
                          edgeAbsorption: 0.0,
                        ),
                        child: const Center(
                          child: Text(
                            'GLASS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),

          // ═══ 开始基准 ═══
          FilledButton.icon(
            onPressed: _running ? null : _runBenchmark,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed),
            label: Text(_running
                ? '测量中… 已采集 $_progress/$kCollectFrames 帧'
                : '开始性能基准'),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              _message,
              style: context.appText.body.copyWith(
                color: context.appColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),

          // ═══ 结果表 ═══
          if (_results.isNotEmpty)
            _Card(
              title: '光栅帧耗时（ms，越小越好）',
              child: Table(
                columnWidths: const <int, TableColumnWidth>{
                  0: FlexColumnWidth(),
                  1: FlexColumnWidth(),
                  2: FlexColumnWidth(),
                  3: FlexColumnWidth(),
                  4: FlexColumnWidth(),
                },
                children: <TableRow>[
                  TableRow(
                    children: <Widget>[
                      _headerCell('档位'),
                      _headerCell('P50'),
                      _headerCell('P75'),
                      _headerCell('P95'),
                      _headerCell('P99'),
                    ],
                  ),
                  for (final GlassQuality q in kBenchmarkTiers)
                    TableRow(
                      children: <Widget>[
                        _cell(_qualityLabel(q)),
                        _cell(_resultText(q, (r) => r.p50)),
                        _cell(_resultText(q, (r) => r.p75)),
                        _cell(_resultText(q, (r) => r.p95)),
                        _cell(_resultText(q, (r) => r.p99)),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _resultText(GlassQuality q, double Function(_TierResult) pick) {
    final _TierResult? r = _results[q];
    if (r == null) return '—';
    return pick(r).toStringAsFixed(1);
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.appText.caption.copyWith(
            color: context.appColors.textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _cell(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.appText.body,
        ),
      );

  static String _qualityLabel(GlassQuality q) => switch (q) {
        GlassQuality.premium => 'premium',
        GlassQuality.standard => 'standard',
        GlassQuality.minimal => 'minimal',
      };
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.appColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: context.appText.subtitle),
          const SizedBox(height: AppSpace.sm),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: context.appText.body.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(value, style: context.appText.body),
        ],
      ),
    );
  }
}
