import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../providers/scene/scene_custom_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../scenes/scene_api.dart';
import '../../widgets/common/page_scaffold.dart';
import 'custom_scene_edit_page.dart';

/// 自定义场景列表（v2 M5-2 · P0-M5-2）。
///
/// 列出全部场景（内置 / 自定义分组，标记来源），支持显示 / 隐藏开关与
/// 「+ 新建场景」（P0-M5-3）。
class CustomSceneListPage extends ConsumerWidget {
  const CustomSceneListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Scene> all = ref.watch(scenesProvider);
    final List<Scene> builtIn =
        all.where((Scene s) => !s.isCustom).toList();
    final List<Scene> customs =
        all.where((Scene s) => s.isCustom).toList();

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '自定义场景',
          onBack: () => Navigator.of(context).pop(),
          actions: <Widget>[
            TextButton.icon(
              onPressed: () => _createScene(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建'),
            ),
          ],
          body: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              if (customs.isNotEmpty) ...<Widget>[
                _GroupHeader('自定义'),
                for (final Scene s in customs) _SceneTile(scene: s),
              ],
              if (builtIn.isNotEmpty) ...<Widget>[
                _GroupHeader('内置'),
                for (final Scene s in builtIn) _SceneTile(scene: s),
              ],
              const SizedBox(height: AppSpace.lg),
              const Text(
                '提示：自定义场景可导出 / 导入场景包（复用场景编辑器导出能力）。',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createScene(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CustomSceneEditPage(),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Text(label, style: AppTextStyles.bodyMuted),
    );
  }
}

/// 场景条目：图标 + 名称 + 显示开关 + 来源标记 + 编辑。
class _SceneTile extends ConsumerWidget {
  const _SceneTile({required this.scene});

  final Scene scene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Center(
              child: Text(
                scene.visual.glyph,
                style: const TextStyle(
                  fontSize: 18,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(scene.name,
                    style: AppTextStyles.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  scene.isCustom ? '自定义 · ${scene.mood}' : '内置 · ${scene.mood}',
                  style: AppTextStyles.artist,
                ),
              ],
            ),
          ),
          // 显示开关（持久化 visible，P0-M5-3）
          Switch(
            value: scene.visible,
            onChanged: (bool v) async {
              await ref
                  .read(customScenesProvider.notifier)
                  .save(scene.copyWith(visible: v));
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: AppColors.textTertiary),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CustomSceneEditPage(scene: scene),
              ),
            ),
          ),
          // P1-M5-6：导出场景包（复用 scene_packer / scene_api）
          IconButton(
            icon: const Icon(Icons.ios_share_rounded,
                size: 18, color: AppColors.textTertiary),
            tooltip: '导出场景包',
            onPressed: () => _exportPack(context, scene),
          ),
          if (scene.isCustom)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppColors.danger),
              onPressed: () async {
                await ref
                    .read(customScenesProvider.notifier)
                    .remove(scene.id);
              },
            ),
        ],
      ),
    );
  }

  /// 导出场景包：编码为 JSON 字符串并复制到剪贴板（P1-M5-6）。
  Future<void> _exportPack(BuildContext context, Scene scene) async {
    final String pack = Scenes.encodePack(scene);
    await Clipboard.setData(ClipboardData(text: pack));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导出「${scene.name}」场景包并复制到剪贴板')),
    );
  }
}
