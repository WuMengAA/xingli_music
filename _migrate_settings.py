# -*- coding: utf-8 -*-
"""R26fx2 设置重构：画质预设一键套全 + 画面常用/高级分组 + 删 gameGraphics 重复入口
+ slider 数值显示 + 效果词条。"""
import io

def sub(s, old, new, must=1):
    n = s.count(old)
    assert n == must, f'ANCHOR FAIL ({n}): {old[:60]!r}'
    return s.replace(old, new)

# ═══════════ settings_item_registry.dart ═══════════
p = 'lib/core/settings_item_registry.dart'
s = io.open(p, encoding='utf-8').read()

# import
s = sub(s, "import '../pages/settings/game_graphics_page.dart';\n", "")
s = sub(s,
"import '../pages/settings/voxel_save_manager_page.dart';",
"import '../pages/settings/voxel_save_manager_page.dart';\nimport '../providers/voxel/graphics_quality_provider.dart';\nimport '../widgets/voxel/voxel_world_view3d.dart' show GraphicsQuality;")

# 删 gameGraphics
s = sub(s, """  'gameGraphics': SettingItemDef(
    title: '游戏画面（画质/视距/LOD）',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.tune_rounded,
      title: '游戏画面',
      subtitle: '画质档 / 视距 / LOD / 帧率 · 与游戏内共享',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const GameGraphicsPage()),
      ),
    ),
  ),
""", "")

# perfPreset 升级
s = sub(s, """  'perfPreset': SettingItemDef(
    title: '性能预设',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('性能预设', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<PerformanceMode>(
          ref: ref,
          value: ref.watch(performanceModeProvider),
          values: PerformanceMode.values,
          labels: const <String>['性能优先', '质量优先'],
          onChanged: (PerformanceMode m) => _applyPerfPreset(ref, m),
        ),
      ],
    ),
  ),""", """  'perfPreset': SettingItemDef(
    title: '画质预设',
    builder: (context, ref) {
      final GraphicsQuality q = ref.watch(graphicsQualityProvider);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('画质预设 · 一键套用整套画面参数', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            '当前：${q.label} · 视距 ${ref.watch(viewDistanceChunksProvider)} 区块 · '
            '渲染 ${(ref.watch(renderScaleProvider) * ref.watch(renderRatioProvider)).toStringAsFixed(2)}×',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          _chips<GraphicsQuality>(
            ref: ref,
            value: q,
            values: GraphicsQuality.values,
            labels: <String>[
              for (final GraphicsQuality g in GraphicsQuality.values) g.label
            ],
            onChanged: (GraphicsQuality g) => _applyQualityPreset(ref, g),
          ),
        ],
      );
    },
  ),""")

# _applyQualityPreset
s = sub(s, """/// 性能预设一键应用（与 settings_page 原 _applyPerformancePreset 等价）。
void _applyPerfPreset(WidgetRef ref, PerformanceMode m) {
  ref.read(performanceModeProvider.notifier).state = m;
  ref.read(fpsLimitProvider.notifier).state = defaultFpsFor(m);
  ref.read(noiseOverrideProvider.notifier).state =
      m == PerformanceMode.performance ? false : null;
  ref.read(glassBlurOverrideProvider.notifier).state =
      m == PerformanceMode.performance ? 0.0 : null;
  ref.read(bgAnimationOverrideProvider.notifier).state =
      m == PerformanceMode.performance ? false : null;
  ref.read(liquidGlassOverrideProvider.notifier).state =
      m == PerformanceMode.performance ? false : null;
}""", """/// R26fx：画质预设一键应用——把整套画面参数（画质档/视距/LOD/分辨率/特效/
/// 帧率）一次设齐，避免「画质档、性能预设、视距、LOD、渲染参数各自独立
/// 叠加生效、出了问题不知道是哪一层」的混乱。
void _applyQualityPreset(WidgetRef ref, GraphicsQuality q) {
  ref.read(graphicsQualityProvider.notifier).state = q;
  ref.read(performanceModeProvider.notifier).state =
      q == GraphicsQuality.perf || q == GraphicsQuality.smooth
          ? PerformanceMode.performance
          : PerformanceMode.quality;
  ref.read(viewDistanceChunksProvider.notifier).state = q.viewDistanceChunks;
  ref.read(lodStartChunksProvider.notifier).state = q.lodStartChunks;
  ref.read(lodStepChunksProvider.notifier).state = q.lodStepChunks;
  ref.read(lodEnabledProvider.notifier).state = true;
  ref.read(lodStepBlocksProvider.notifier).state = 16;
  ref.read(lodSampleBaseProvider.notifier).state = 4;
  ref.read(lodMaxChunksProvider.notifier).state =
      q == GraphicsQuality.perf
          ? 4
          : (q == GraphicsQuality.smooth ? 6 : 8);
  ref.read(renderScaleProvider.notifier).state = q.renderScale;
  ref.read(renderRatioProvider.notifier).state = 1.0;
  ref.read(renderPrecisionProvider.notifier).state = 1.0;
  ref.read(fpsLimitProvider.notifier).state =
      q == GraphicsQuality.perf ? FpsLimit.fps24 : FpsLimit.fps60;
  final bool low = q == GraphicsQuality.perf || q == GraphicsQuality.smooth;
  ref.read(noiseOverrideProvider.notifier).state = low ? false : null;
  ref.read(glassBlurOverrideProvider.notifier).state = low ? 0.0 : null;
  ref.read(bgAnimationOverrideProvider.notifier).state = low ? false : null;
  ref.read(liquidGlassOverrideProvider.notifier).state = low ? false : null;
}""")

# slider 数值显示
s = sub(s, """        Text('视距', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        Slider(
          value: ref.watch(viewDistanceChunksProvider).toDouble(),
          min: 2,
          max: 12,
          divisions: 10,
          label: '${ref.watch(viewDistanceChunksProvider)} 区块',""", """        Text(
          '视距 · 当前 ${ref.watch(viewDistanceChunksProvider)} 区块',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Slider(
          value: ref.watch(viewDistanceChunksProvider).toDouble(),
          min: 2,
          max: 12,
          divisions: 10,
          label: '${ref.watch(viewDistanceChunksProvider)} 区块',""")
s = sub(s, "        Text('LOD 起始（区块）', style: Theme.of(context).textTheme.bodyMedium),",
        "        Text(\n          'LOD 起始 · 当前 ${ref.watch(lodStartChunksProvider)} 区块',\n          style: Theme.of(context).textTheme.bodyMedium,\n        ),")
s = sub(s, "        Text('LOD 最远距离（区块，可超视距）', style: Theme.of(context).textTheme.bodyMedium),",
        "        Text(\n          'LOD 最远距离 · 当前 ${ref.watch(lodMaxChunksProvider)} 区块（可超视距）',\n          style: Theme.of(context).textTheme.bodyMedium,\n        ),")
s = sub(s, "        Text('渲染分辨率（倍率，1.0=画质档默认）', style: Theme.of(context).textTheme.bodyMedium),",
        "        Text(\n          '渲染分辨率 · 当前 ${ref.watch(renderScaleProvider).toStringAsFixed(2)}×',\n          style: Theme.of(context).textTheme.bodyMedium,\n        ),")

# 词条
s = sub(s, "      subtitle: '开 / 关（跟随档位或手动）',",
        "      subtitle: '胶片颗粒质感；关 = 更省 GPU（低档位默认关）',")
s = sub(s, "      title: '背景动画',\n      subtitle: '开 / 关',",
        "      title: '背景动画',\n      subtitle: '背景动态动画；关 = 省电省性能（低档位默认关）',")
s = sub(s, "      title: '液态玻璃（折射）',\n      subtitle: '开 / 关',",
        "      title: '液态玻璃（折射）',\n      subtitle: '液态玻璃折射；关 = 省性能（低档位默认关）',")
s = sub(s, "      subtitle: 'FOV 不变：完整视线窄锥剔除 + 边界黑化 + 泛光（绝佳效果）',",
        "      subtitle: '手电筒光锥：FOV 不变，锥内照亮、锥外变暗 + 泛光（仅渲染）',")
s = sub(s, "      subtitle: '太阳方向投影阴影（方块被遮挡时投下硬阴影）',",
        "      subtitle: '太阳投影硬阴影（开=真实立体；关=省面数）',")

io.open(p, 'w', encoding='utf-8').write(s)
print('registry OK')

# ═══════════ settings_layout.dart ═══════════
p2 = 'lib/core/settings_layout.dart'
t = io.open(p2, encoding='utf-8').read()
old_perf = """        SettingGroup(
          id: 'visual_perf',
          name: '性能与质量',
          items: <SettingItem>[
            SettingItem(id: 'gameGraphics', title: '游戏画面（画质/视距/LOD）'),
            SettingItem(id: 'perfPreset', title: '性能预设', kind: SettingKind.chips),
            SettingItem(id: 'fpsLimit', title: '帧率限制', kind: SettingKind.chips),
            SettingItem(id: 'viewDistance', title: '视距', kind: SettingKind.chips),
            SettingItem(id: 'lodStart', title: 'LOD 起始', kind: SettingKind.chips),
            SettingItem(id: 'lodStep', title: 'LOD 步长', kind: SettingKind.chips),
            SettingItem(id: 'lodEnabled', title: 'LOD 开关', kind: SettingKind.toggle),
            SettingItem(id: 'lodStepBlocks', title: 'LOD 步长（格）', kind: SettingKind.chips),
            SettingItem(id: 'lodSample', title: 'LOD 采样（大方块）', kind: SettingKind.chips),
            SettingItem(id: 'lodMaxChunks', title: 'LOD 最远距离', kind: SettingKind.slider),
            SettingItem(id: 'engineBackend', title: '图形后端', kind: SettingKind.chips),
            SettingItem(id: 'renderScale', title: '渲染分辨率', kind: SettingKind.slider),
            SettingItem(id: 'renderRatio', title: '渲染比例', kind: SettingKind.chips),
            SettingItem(id: 'renderPrecision', title: '渲染精度', kind: SettingKind.chips),
            SettingItem(id: 'shadowRender', title: '阴影渲染', kind: SettingKind.toggle),
            SettingItem(id: 'aoRender', title: '环境光屏蔽（AO）', kind: SettingKind.toggle),
            SettingItem(id: 'fxNoise', title: '噪点纹理', kind: SettingKind.toggle),
            SettingItem(id: 'fxBlur', title: '玻璃模糊', kind: SettingKind.toggle),
            SettingItem(id: 'fxBg', title: '背景动画', kind: SettingKind.toggle),
            SettingItem(id: 'fxLiquid', title: '液态玻璃（折射）', kind: SettingKind.toggle),
          ],
        ),
        SettingGroup(
          id: 'visual_render',
          name: '渲染（更多）',
          items: <SettingItem>[
            SettingItem(id: 'flashlight', title: '手电筒模式', kind: SettingKind.toggle),
            SettingItem(id: 'underwaterFilter', title: '水下滤镜', kind: SettingKind.toggle),
            SettingItem(id: 'faceCull', title: '侧面剔除', kind: SettingKind.toggle),
            SettingItem(id: 'occlusionCull', title: '遮挡剔除', kind: SettingKind.toggle),
            SettingItem(id: 'backFaceCull', title: '背面剔除', kind: SettingKind.toggle),
            SettingItem(id: 'frustumCull', title: '视锥剔除', kind: SettingKind.toggle),
          ],
        ),"""
new_perf = """        SettingGroup(
          id: 'visual_common',
          name: '画面 · 常用',
          items: <SettingItem>[
            SettingItem(id: 'perfPreset', title: '画质预设', kind: SettingKind.chips),
            SettingItem(id: 'viewDistance', title: '视距', kind: SettingKind.slider),
            SettingItem(id: 'fpsLimit', title: '帧率限制', kind: SettingKind.chips),
            SettingItem(id: 'renderScale', title: '渲染分辨率', kind: SettingKind.slider),
          ],
        ),
        SettingGroup(
          id: 'visual_advanced',
          name: '画面 · 高级',
          items: <SettingItem>[
            SettingItem(id: 'lodEnabled', title: 'LOD 开关', kind: SettingKind.toggle),
            SettingItem(id: 'lodStart', title: 'LOD 起始', kind: SettingKind.slider),
            SettingItem(id: 'lodStepBlocks', title: 'LOD 步长（格）', kind: SettingKind.chips),
            SettingItem(id: 'lodSample', title: 'LOD 采样（大方块）', kind: SettingKind.chips),
            SettingItem(id: 'lodMaxChunks', title: 'LOD 最远距离', kind: SettingKind.slider),
            SettingItem(id: 'engineBackend', title: '图形后端', kind: SettingKind.chips),
            SettingItem(id: 'renderRatio', title: '渲染比例', kind: SettingKind.chips),
            SettingItem(id: 'renderPrecision', title: '渲染精度', kind: SettingKind.chips),
            SettingItem(id: 'shadowRender', title: '阴影渲染', kind: SettingKind.toggle),
            SettingItem(id: 'aoRender', title: '环境光屏蔽（AO）', kind: SettingKind.toggle),
            SettingItem(id: 'fxNoise', title: '噪点纹理', kind: SettingKind.toggle),
            SettingItem(id: 'fxBlur', title: '玻璃模糊', kind: SettingKind.toggle),
            SettingItem(id: 'fxBg', title: '背景动画', kind: SettingKind.toggle),
            SettingItem(id: 'fxLiquid', title: '液态玻璃（折射）', kind: SettingKind.toggle),
            SettingItem(id: 'flashlight', title: '手电筒模式', kind: SettingKind.toggle),
            SettingItem(id: 'underwaterFilter', title: '水下滤镜', kind: SettingKind.toggle),
            SettingItem(id: 'faceCull', title: '侧面剔除', kind: SettingKind.toggle),
            SettingItem(id: 'occlusionCull', title: '遮挡剔除', kind: SettingKind.toggle),
            SettingItem(id: 'backFaceCull', title: '背面剔除', kind: SettingKind.toggle),
            SettingItem(id: 'frustumCull', title: '视锥剔除', kind: SettingKind.toggle),
          ],
        ),"""
t = sub(t, old_perf, new_perf)
io.open(p2, 'w', encoding='utf-8').write(t)
print('layout OK')

# ═══════════ settings_page.dart ═══════════
p3 = 'lib/pages/settings/settings_page.dart'
u = io.open(p3, encoding='utf-8').read()
u = sub(u, """        const SizedBox(height: AppSpace.sm),
        // R26p：游戏画面专属设置（与游戏内共享 provider）。
        _EntryRow(
          icon: Icons.tune_rounded,
          title: '游戏画面',
          subtitle: '画质档 / 视距 / LOD / 帧率 · 与游戏内共享',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const GameGraphicsPage(),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        // R26p：世界存档管理器（新建 / 恢复多备份 / 导出 / 重命名 / 删除）。""",
"""        const SizedBox(height: AppSpace.sm),
        // R26p：世界存档管理器（新建 / 恢复多备份 / 导出 / 重命名 / 删除）。""")
io.open(p3, 'w', encoding='utf-8').write(u)
print('settings_page OK')
print('ALL DONE')
