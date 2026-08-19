import 'package:file_picker/file_picker.dart';
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
import '../../widgets/notification/app_notify.dart';

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
    appNotify(context, '已保存 2.5D 音效场景「$name」');
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
///
/// 增强（#555）：
/// - **群系音效**：顶部 7 个群系 chips（平原/森林/沙漠/高山/雪山/河流/海洋），
///   选中后该群系推荐音效置顶高亮（[kBiomeSoundIds] 映射），其余预设仍可点选。
/// - **自定义音效**：「+ 自定义」按钮 → file_picker 选音频 → 命名 → 注册进
///   会话内 [registerCustomBlockType]，与预设合并展示；点击方块即播放该文件。
class _BlockPanel extends ConsumerStatefulWidget {
  const _BlockPanel({required this.controller});

  final VoxelCanvasController controller;

  @override
  ConsumerState<_BlockPanel> createState() => _BlockPanelState();
}

class _BlockPanelState extends ConsumerState<_BlockPanel> {
  /// 当前选中的群系（null = 不筛选，全部展示）。
  String? _biome;

  /// 合并后的可用类型：预设 + 会话内自定义。
  List<VoxelBlockType> get _types => <VoxelBlockType>[
        ...kVoxelBlockTypes,
        ...customBlockTypes,
      ];

  /// 群系推荐音效 id 集（选中群系时置顶高亮）。
  List<String>? get _recommended => _biome == null ? null : kBiomeSoundIds[_biome];

  Future<void> _addCustom() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    final String? path = result?.files.single.path;
    if (path == null || !mounted) return;
    final String name = path.split(RegExp(r'[/\\]')).last;
    // 命名弹窗：默认取文件名（去扩展名）。
    final TextEditingController ctrl =
        TextEditingController(text: name.replaceAll(RegExp(r'\.\w+$'), ''));
    final String? finalName = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('自定义音效'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (finalName == null || finalName.isEmpty || !mounted) return;
    // 注册自定义块：唯一 id（时间戳），sfxKey 置空、customPath 指向文件。
    registerCustomBlockType(
      VoxelBlockType(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: finalName,
        icon: Icons.audio_file_rounded,
        sfxKey: '',
        baseVolume: 0.3,
        color: const Color(0xFF9B7BFF),
        glyph: '♪',
        customPath: path,
      ),
    );
    setState(() {});
    appNotify(context, '已添加自定义音效「$finalName」');
  }

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
          // 群系音效 chips 行。
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final String b in kBiomeSoundIds.keys) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpace.xs),
                    child: ChoiceChip(
                      label: Text(_biomeLabel(b)),
                      selected: _biome == b,
                      onSelected: (bool sel) =>
                          setState(() => _biome = sel ? b : null),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: <Widget>[
              Text('音效块', style: AppTextStyles.subtitle),
              const Spacer(),
              // 自定义音效入口。
              TextButton.icon(
                onPressed: _addCustom,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('自定义'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (BuildContext context, Widget? child) {
                return GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: AppSpace.xs,
                  crossAxisSpacing: AppSpace.xs,
                  children: <Widget>[
                    // 先展示群系推荐（选中时），再展示其余。
                    for (final VoxelBlockType type
                        in _sortedTypes())
                      _BlockTypeTile(
                        type: type,
                        recommended: _recommended?.contains(type.id) ?? false,
                        selected: widget.controller.selected.id == type.id,
                        onTap: () => widget.controller.selected = type,
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

  /// 群系推荐音效置顶 + 高亮；未选群系按原顺序（预设在前、自定义在后）。
  List<VoxelBlockType> _sortedTypes() {
    final List<String>? rec = _recommended;
    if (rec == null || rec.isEmpty) return _types;
    final List<VoxelBlockType> recTypes = <VoxelBlockType>[];
    final List<VoxelBlockType> rest = <VoxelBlockType>[];
    for (final VoxelBlockType t in _types) {
      if (rec.contains(t.id)) {
        recTypes.add(t);
      } else {
        rest.add(t);
      }
    }
    return <VoxelBlockType>[...recTypes, ...rest];
  }

  static String _biomeLabel(String key) => switch (key) {
        'plains' => '平原',
        'forest' => '森林',
        'desert' => '沙漠',
        'mountain' => '高山',
        'snowMountain' => '雪山',
        'river' => '河流',
        'ocean' => '海洋',
        _ => key,
      };
}

class _BlockTypeTile extends StatelessWidget {
  const _BlockTypeTile({
    required this.type,
    required this.selected,
    required this.onTap,
    this.recommended = false,
  });

  final VoxelBlockType type;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isCustom = type.customPath?.isNotEmpty == true;
    return Material(
      color: selected
          ? AppColors.accentSoft
          : (recommended ? const Color(0x1A9B7BFF) : AppColors.bgCard),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : (recommended ? const Color(0x669B7BFF) : AppColors.borderDefault),
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
              if (isCustom)
                Text(
                  '自定义',
                  style: AppTextStyles.caption.copyWith(fontSize: 9),
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
