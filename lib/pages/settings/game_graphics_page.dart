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
import '../../providers/voxel/graphics_quality_provider.dart'
    show applyGraphicsQuality, graphicsQualityProvider;
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
                        onSelected: (_) => applyGraphicsQuality(ref, g),
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

          // ═══ 常用画质参数（提到顶层卡片，不再藏进折叠，减少套娃层级）═══
          _Card(
            title: '视距',
            child: _Stepper(
              label: '视距',
              value: vd,
              min: 2,
              max: 4,
              hint: '区块（1 区块 = 16 格）。上限 4，远景由 LOD 延伸',
              onChanged: (int v) =>
                  ref.read(viewDistanceChunksProvider.notifier).state = v,
            ),
          ),
          const SizedBox(height: AppSpace.md),

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
                _Stepper(
                  label: 'LOD 最远距离',
                  value: lodMax,
                  min: 2,
                  max: 64,
                  hint: '区块（1 区块 = 16 格）。可超视距，远景大方块看得更远'
                      '（地平线档 64）',
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
          const SizedBox(height: AppSpace.md),

          // ═══ 高级（仅保留极客项；用分区标题替代「卡片套卡片」的嵌套）═══
          ExpansionTile(
            initiallyExpanded: false,
            shape: const Border(),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text('高级（渲染精度 / 剔除 / 杂项）',
                style: context.appText.body),
            children: <Widget>[
              const SizedBox(height: AppSpace.sm),
              // 渲染精度
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('渲染精度', style: context.appText.body),
                  const SizedBox(height: 6),
                  Slider(
                    value: ref.watch(renderPrecisionScaleProvider),
                    min: 0.25,
                    max: 2.0,
                    divisions: 14,
                    label:
                        '${ref.watch(renderPrecisionScaleProvider).toStringAsFixed(2)}×',
                    onChanged: (double v) => ref
                        .read(renderPrecisionScaleProvider.notifier)
                        .state = v,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              _ToggleRow(
                title: 'LOD 开关',
                subtitle: '关 = 全满精度方阵，无远景大方块（最费面数）',
                value: ref.watch(lodEnabledProvider),
                onChanged: (bool v) =>
                    ref.read(lodEnabledProvider.notifier).state = v,
              ),
              const SizedBox(height: AppSpace.xs),
              _Chips<int>(
                label: 'LOD 采样（合成大方块边长）',
                value: ref.watch(lodSampleBaseProvider),
                values: const <int>[2, 4, 8],
                labels: const <String>['2×2（细）', '4×4（中）', '8×8（粗）'],
                onChanged: (int v) =>
                    ref.read(lodSampleBaseProvider.notifier).state = v,
              ),
              const SizedBox(height: AppSpace.xs),
              _ToggleRow(
                title: '边界雾',
                subtitle: '开=视距边缘收口雾（隐藏远景，LOD 关闭）；关=LOD 远景看得更远',
                value: ref.watch(boundaryFogEnabledProvider),
                onChanged: (bool v) =>
                    ref.read(boundaryFogEnabledProvider.notifier).state = v,
              ),
              const SizedBox(height: AppSpace.xs),
              _Chips<double>(
                label: '几何精度（面数倍率，与渲染分辨率无关）',
                value: ref.watch(renderPrecisionProvider),
                values: const <double>[0.5, 1.0, 1.5, 2.0],
                labels: const <String>['0.5×', '1×', '1.5×', '2×'],
                onChanged: (double v) =>
                    ref.read(renderPrecisionProvider.notifier).state = v,
              ),
              const Divider(height: 1),
              Text('剔除', style: context.appText.bodyMuted),
              const SizedBox(height: AppSpace.xs),
              _ToggleRow(
                title: '侧面剔除',
                subtitle: '远处区块按视角朝向减面（配合 LOD 迟滞防闪烁）',
                value: ref.watch(faceCullEnabledProvider),
                onChanged: (bool v) =>
                    ref.read(faceCullEnabledProvider.notifier).state = v,
              ),
              const SizedBox(height: AppSpace.xs),
              _ToggleRow(
                title: '遮挡剔除',
                subtitle: '隐藏被相邻不透明方块完全盖住的内部面（最大面数收益）',
                value: ref.watch(occlusionCullEnabledProvider),
                onChanged: (bool v) =>
                    ref.read(occlusionCullEnabledProvider.notifier).state = v,
              ),
              const SizedBox(height: AppSpace.xs),
              _ToggleRow(
                title: '背面剔除',
                subtitle: '去掉背向相机的三角面（面数减半）',
                value: ref.watch(backFaceCullEnabledProvider),
                onChanged: (bool v) =>
                    ref.read(backFaceCullEnabledProvider.notifier).state = v,
              ),
              const SizedBox(height: AppSpace.xs),
              _ToggleRow(
                title: '视锥剔除',
                subtitle: '跳过视锥外区块（默认关：历史曾误删可见区块）',
                value: ref.watch(frustumCullEnabledProvider),
                onChanged: (bool v) =>
                    ref.read(frustumCullEnabledProvider.notifier).state = v,
              ),
              const Divider(height: 1),
              Text('杂项', style: context.appText.bodyMuted),
              const SizedBox(height: AppSpace.xs),
              _ToggleRow(
                title: '水下滤镜',
                subtitle: '水下蓝色色调 + 阳光衰减',
                value: ref.watch(underwaterFilterEnabledProvider),
                onChanged: (bool v) =>
                    ref.read(underwaterFilterEnabledProvider.notifier).state = v,
              ),
              const SizedBox(height: AppSpace.xs),
              _ToggleRow(
                title: '水流动',
                subtitle: '放置水源后向四周 9 格扩散（20 tick/秒 驱动）',
                value: ref.watch(waterFlowEnabledProvider),
                onChanged: (bool v) =>
                    ref.read(waterFlowEnabledProvider.notifier).state = v,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            '说明：画质预设一键套用（视距 / LOD / 帧率随档位）；'
            '常用参数已提升到顶层，极客项收进「高级」折叠区。',
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

/// 开关行（标题 + 副标题 + 开关）。
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: context.appText.body),
              const SizedBox(height: 2),
              Text(subtitle, style: context.appText.artist),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// 选项行（标题 + 选项 chips）。
class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.label,
    required this.value,
    required this.values,
    required this.labels,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final List<String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: context.appText.body),
        const SizedBox(height: 6),
        Wrap(
          spacing: AppSpace.xs,
          children: <Widget>[
            for (int i = 0; i < values.length; i++)
              ChoiceChip(
                label: Text(labels[i]),
                selected: value == values[i],
                onSelected: (_) => onChanged(values[i]),
              ),
          ],
        ),
      ],
    );
  }
}
