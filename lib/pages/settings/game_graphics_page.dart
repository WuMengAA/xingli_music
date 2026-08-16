/// ════════════════════════════════════════════════════════════════════════
/// 游戏画面设置（R26p）：主页设置里的专属界面，与游戏内快捷设置共享同一批
/// provider（graphicsQualityProvider / viewDistanceChunksProvider /
/// lodStartChunksProvider / lodStepChunksProvider / fpsLimitProvider），
/// 改动即时生效、重启不丢（由 settings_persistence_providers 落盘）。
///
/// 以「低画质纯色」为基础；R26x 恢复「高清」贴图档（图集经原始 RGBA 重解码，
/// 跨 Impeller/D3D11 可靠采样，不再黑渲染）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/performance_providers.dart';
import '../../providers/voxel/graphics_quality_provider.dart';
import '../../providers/voxel/cloud_view_distance_provider.dart';
import '../../widgets/voxel/voxel_world_view3d.dart' show GraphicsQuality;
import '../../widgets/voxel/voxel_renderer.dart' show LodQuality;

/// 游戏画面 · 专属设置页（从主页设置「游戏」段进入）。
class GameGraphicsPage extends ConsumerWidget {
  const GameGraphicsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GraphicsQuality q = ref.watch(graphicsQualityProvider);
    final int vd = ref.watch(viewDistanceChunksProvider);
    final int lodStart = ref.watch(lodStartChunksProvider);
    final int lodStep = ref.watch(lodStepChunksProvider);
    final int lodMax = ref.watch(lodMaxChunksProvider);
    final LodQuality lodQuality = ref.watch(lodQualityProvider);
    final bool lodFrustumCull = ref.watch(lodFrustumCullProvider);
    final FpsLimit fps = ref.watch(fpsLimitProvider);

    return Scaffold(
      backgroundColor: context.appColors.bgSurfaceSunken,
      appBar: AppBar(
        backgroundColor: context.appColors.bgSurface,
        foregroundColor: context.appColors.textPrimary,
        title: Text('游戏画面', style: context.appText.subtitle),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: <Widget>[
          Text(
            '与游戏内设置共享，改动即时生效、重启保留。'
            '低画质已足够：无贴图、无光影，纯色平铺 + 雾 + 远景 LOD。',
            style: context.appText.artist,
          ),
          const SizedBox(height: AppSpace.lg),

          // ═══ 画质档（四档预设）═══
          _Card(
            title: '画质档',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: AppSpace.xs,
                  children: <Widget>[
                    for (final GraphicsQuality g in GraphicsQuality.values)
                      ChoiceChip(
                        label: Text(g.label),
                        selected: q == g,
                        onSelected: (_) => ref
                            .read(graphicsQualityProvider.notifier)
                            .state = g,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  q == GraphicsQuality.auto
                      ? '自动：按真实帧率调节（目标 ≥30fps），不足则逐档下调'
                          '主视距区块（4→2）；默认开启，≤60fps。'
                      : '${q.label}：视距 ${q.viewDistanceChunks} 区块 + '
                          'LOD ${q.lodMaxChunks} 区块，共 '
                          '${q.viewDistanceChunks + q.lodMaxChunks} 区块 · '
                          '${q.fpsCap}fps。',
                  style: context.appText.artist,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),

          // ═══ 帧率 ═══
          _Card(
            title: '帧率限制',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: AppSpace.xs,
                  children: <Widget>[
                    for (final FpsLimit f in FpsLimit.values)
                      ChoiceChip(
                        label: Text(f.label),
                        selected: fps == f,
                        onSelected: (_) =>
                            ref.read(fpsLimitProvider.notifier).state = f,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  '省电档预设 24fps、其余 60fps；低端机建议 24。',
                  style: context.appText.artist,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),

          // ═══ 高级（cl76：默认折叠，收纳繁琐画质选项）═══
          ExpansionTile(
            initiallyExpanded: false,
            shape: const Border(),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text('高级（视距 / LOD / 云层 / 描边）',
                style: context.appText.body),
            children: <Widget>[
              const SizedBox(height: AppSpace.sm),

              // 视距
              _Card(
                title: '视距',
                child: _Stepper(
                  label: '视距',
                  value: vd,
                  min: 2,
                  max: 12,
                  hint: '区块（1 区块 = 16 格）。越大看得越远、面数越多',
                  onChanged: (int v) =>
                      ref.read(viewDistanceChunksProvider.notifier).state = v,
                ),
              ),
              const SizedBox(height: AppSpace.md),

              // 云层区块视距（R26p2）
              _Card(
                title: '云层区块视距',
                child: _Stepper(
                  label: '云层视距',
                  value: ref.watch(cloudViewDistanceProvider),
                  min: 1,
                  max: 8,
                  hint: '区块（1 区块 = 16 格）。云场覆盖半径，越大云铺越远、云胞越多',
                  onChanged: (int v) =>
                      ref.read(cloudViewDistanceProvider.notifier).state = v,
                ),
              ),
              const SizedBox(height: AppSpace.md),

              // LOD
              _Card(
                title: '细节层次（LOD）',
                child: Column(
                  children: <Widget>[
                    _Stepper(
                      label: 'LOD 起始',
                      value: lodStart,
                      min: 0,
                      max: 6,
                      hint: '距相机多少区块外开始降精度（0 = 全程满精度）',
                      onChanged: (int v) =>
                          ref.read(lodStartChunksProvider.notifier).state = v,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    _Stepper(
                      label: 'LOD 步长',
                      value: lodStep,
                      min: 1,
                      max: 4,
                      hint: '每 N 区块降一级精度（步长 ×2）',
                      onChanged: (int v) =>
                          ref.read(lodStepChunksProvider.notifier).state = v,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    // cl76_hotfix：可调 LOD 视距（最远 60/上限 64 区块）。
                    _Stepper(
                      label: 'LOD 最远距离',
                      value: lodMax,
                      min: 2,
                      max: 64,
                      hint: '区块（1 区块 = 16 格）。可超视距，远景大方块看得更远'
                          '（地平线档 28）',
                      onChanged: (int v) =>
                          ref.read(lodMaxChunksProvider.notifier).state = v,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text('LOD 质量', style: context.appText.bodyMuted),
                    const SizedBox(height: AppSpace.xs),
                    Wrap(
                      spacing: AppSpace.xs,
                      children: <Widget>[
                        for (final LodQuality lq in LodQuality.values)
                          ChoiceChip(
                            label: Text(_lodQualityLabel(lq)),
                            selected: lodQuality == lq,
                            onSelected: (_) =>
                                ref.read(lodQualityProvider.notifier).state = lq,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'LOD 视锥剔除（关闭远景后半球，省面）',
                            style: context.appText.artist,
                          ),
                        ),
                        Switch(
                          value: lodFrustumCull,
                          onChanged: (bool v) =>
                              ref.read(lodFrustumCullProvider.notifier).state = v,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),

              // 方块描边（cl45）
              _Card(
                title: '方块描边',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '玩家 5 格内实描边 + 5~12 格极淡渐隐；'
                        '关闭后不描边（更省面数、画面更干净）',
                        style: context.appText.artist,
                      ),
                    ),
                    Switch(
                      value: ref.watch(outlineEnabledProvider),
                      onChanged: (bool v) => ref
                          .read(outlineEnabledProvider.notifier)
                          .state = v,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            '说明：画质预设一键套用（视距 / LOD / 帧率随档位）；'
            '繁琐参数已收进「高级」与主页「渲染 · 高级」折叠区。',
            style: context.appText.bodyMuted,
          ),
        ],
      ),
    );
  }
}

/// P6·R26r18：LOD 质量档位的中文标签。
String _lodQualityLabel(LodQuality lq) {
  switch (lq) {
    case LodQuality.off:
      return '关（满精度）';
    case LodQuality.balanced:
      return '均衡（2 档）';
    case LodQuality.high:
      return '高（多档细）';
  }
}

/// 卡片容器（统一圆角 + 底色）。
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: AppRadius.brLg,
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: context.appText.body),
          const SizedBox(height: AppSpace.sm),
          child,
        ],
      ),
    );
  }
}

/// 步进行（− / 值 / +）。
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String hint;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label, style: context.appText.body)),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              visualDensity: VisualDensity.compact,
              color: context.appColors.iconInactive,
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 28,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: context.appText.body
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 18),
              visualDensity: VisualDensity.compact,
              color: context.appColors.iconInactive,
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
        Text(hint, style: context.appText.artist),
      ],
    );
  }
}
