import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../models/voxel.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/voxel_scene_providers.dart';
import '../../services/audio/sound_block_mixer.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_chip.dart';
import '../../widgets/voxel/voxel_canvas_controller.dart';
import '../../widgets/voxel/voxel_canvas_view.dart';

/// 2.5D 类我的世界音效编辑器（v2 M5-1 · P0-M5-1）。
///
/// - 等距方块画布（共享 [VoxelCanvasView] 渲染基础）；
/// - 音效块面板（选择类型，可拖到画布 / 点击放置）；
/// - 底部工具栏：试听 / 播放 / 撤销 / 重做 / 清空 / 保存；
/// - 竖屏：画布居中、面板在上；横屏：画布居左、面板居右（PRD §4.5）；
/// - 保存为**独立音效层**（A2 已裁决：不入 `Scene.soundscapePath`）。
class VoxelSoundEditorPage extends ConsumerStatefulWidget {
  const VoxelSoundEditorPage({super.key, this.initialSceneId});

  final String? initialSceneId;

  @override
  ConsumerState<VoxelSoundEditorPage> createState() =>
      _VoxelSoundEditorPageState();
}

class _VoxelSoundEditorPageState extends ConsumerState<VoxelSoundEditorPage> {
  late final VoxelCanvasController _controller;
  SoundBlockMixer? _mixer;
  bool _previewing = false;
  final TextEditingController _nameCtrl = TextEditingController(text: '我的音景');

  @override
  void initState() {
    super.initState();
    _controller = VoxelCanvasController(cols: 8, rows: 8);
    // 编辑既有场景
    final String? id = widget.initialSceneId;
    if (id != null) {
      final VoxelSoundScene? scene =
          ref.read(voxelSoundScenesProvider.notifier).byId(id);
      if (scene != null) {
        _controller.load(scene);
        _nameCtrl.text = scene.name;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _mixer?.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  SoundBlockMixer get _ensureMixer =>
      _mixer ??= SoundBlockMixer(ref.read(audioServiceProvider));

  Future<void> _preview() async {
    await _ensureMixer.preview(_controller.blocks, loop: true);
    if (mounted) {
      setState(() => _previewing = true);
    }
  }

  Future<void> _stop() async {
    await _ensureMixer.stop();
    if (mounted) {
      setState(() => _previewing = false);
    }
  }

  Future<void> _save() async {
    final String name = _nameCtrl.text.trim().isEmpty
        ? '我的音景'
        : _nameCtrl.text.trim();
    final String id = widget.initialSceneId ??
        'voxel_${DateTime.now().millisecondsSinceEpoch}';
    final VoxelSoundScene scene = _controller.toScene(id, name);
    await ref.read(voxelSoundScenesProvider.notifier).save(scene);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存 2.5D 音效场景「$name」')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool landscape = width >= AppSize.landscapeBreakpoint;

    final Widget canvas = Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? child) {
          return VoxelCanvasView(
            controller: _controller,
            height: landscape ? 360 : 300,
            tileW: 46,
            tileH: 28,
            onTapBlock: (int col, int row) =>
                _controller.toggleBlock(col, row),
          );
        },
      ),
    );

    final Widget panel = _BlockPanel(controller: _controller);

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '2.5D 音效编辑器',
          onBack: () => Navigator.of(context).pop(),
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 4),
              child: StateChip(tone: ChipTone.experimenting, label: '实验'),
            ),
          ],
          body: landscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 3, child: _toolbarAndCanvas(canvas)),
                    const SizedBox(width: AppSpace.md),
                    Expanded(flex: 2, child: panel),
                  ],
                )
              : Column(
                  children: <Widget>[
                    Expanded(child: panel),
                    const SizedBox(height: AppSpace.sm),
                    _toolbarAndCanvas(canvas),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _toolbarAndCanvas(Widget canvas) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: canvas),
        const SizedBox(height: AppSpace.sm),
        _Toolbar(
          previewing: _previewing,
          canUndo: _controller.canUndo,
          canRedo: _controller.canRedo,
          onPreview: _previewing ? _stop : _preview,
          onUndo: () => setState(() => _controller.undo()),
          onRedo: () => setState(() => _controller.redo()),
          onClear: () => setState(() => _controller.clear()),
          onSave: _save,
          nameCtrl: _nameCtrl,
        ),
      ],
    );
  }
}

/// 音效块面板（选择类型）。
class _BlockPanel extends StatelessWidget {
  const _BlockPanel({required this.controller});

  final VoxelCanvasController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('音效块', style: AppTextStyles.subtitle),
          const SizedBox(height: AppSpace.sm),
          Expanded(
            child: ListenableBuilder(
              listenable: controller,
              builder: (BuildContext context, Widget? child) {
                return GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: AppSpace.xs,
                  crossAxisSpacing: AppSpace.xs,
                  children: <Widget>[
                    for (final VoxelBlockType type in kVoxelBlockTypes)
                      _BlockTypeTile(
                        type: type,
                        selected: controller.selected.id == type.id,
                        onTap: () => controller.selected = type,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockTypeTile extends StatelessWidget {
  const _BlockTypeTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final VoxelBlockType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentSoft : AppColors.bgCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.borderDefault,
            ),
          ),
          padding: const EdgeInsets.all(AppSpace.xs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(type.icon,
                  size: AppSize.icon,
                  color: selected ? AppColors.accent : AppColors.iconPrimary),
              const SizedBox(height: 2),
              Text(
                type.name,
                style: AppTextStyles.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部工具栏。
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.previewing,
    required this.canUndo,
    required this.canRedo,
    required this.onPreview,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onSave,
    required this.nameCtrl,
  });

  final bool previewing;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onPreview;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback onSave;
  final TextEditingController nameCtrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: nameCtrl,
                  style: AppTextStyles.body,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '场景名称',
                    labelStyle: AppTextStyles.hint,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _toolButton(
                icon: previewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                label: previewing ? '停止' : '试听',
                onTap: onPreview,
                highlight: previewing,
              ),
              _toolButton(
                icon: Icons.undo_rounded,
                label: '撤销',
                onTap: canUndo ? onUndo : null,
              ),
              _toolButton(
                icon: Icons.redo_rounded,
                label: '重做',
                onTap: canRedo ? onRedo : null,
              ),
              _toolButton(
                icon: Icons.delete_sweep_rounded,
                label: '清空',
                onTap: onClear,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool highlight = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: AppSize.iconSm,
              color: onTap == null
                  ? AppColors.iconInactive
                  : (highlight ? AppColors.accent : AppColors.iconPrimary),
            ),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: onTap == null
                    ? AppColors.iconInactive
                    : (highlight ? AppColors.accent : AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
