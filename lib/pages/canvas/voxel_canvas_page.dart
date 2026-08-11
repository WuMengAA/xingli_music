import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/voxel.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/voxel_scene_providers.dart';
import '../../services/audio/sound_block_mixer.dart';
import '../../widgets/noise_texture.dart';
import '../../widgets/voxel/voxel_canvas_controller.dart';
import '../../widgets/voxel/voxel_canvas_view.dart';
import '../../widgets/voxel/voxel_world_view3d.dart';
import '../scene/voxel_sound_editor_page.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 新版沉浸画布（V3）：2.5D 场景编辑后的可互动场景
/// ════════════════════════════════════════════════════════════════════════
///
/// 取代旧版 [CanvasPage]（已删除：粒子 / 调色盘 / 心情 / 更多面板的暗色孤岛）。
///
/// - **数据源**：用户在 2.5D 音效编辑器（[VoxelSoundEditorPage]）里保存的
///   [VoxelSoundScene] 列表（`voxelSoundScenesProvider`），非写死场景。
/// - **渲染**：共享 [VoxelCanvasView] 等距方块画布（纯 CustomPaint），
///   背景沿用 AppShell 玻璃层语言（accent 0.10→bgPage 渐变 + 噪点）。
/// - **互动**：点击方块 → 播放该类型音效一次（[SoundBlockMixer.playType]）；
///   底部「播放音景」→ 按方块数量/位置混合整场循环播放；再点停止。
/// - **多场景**：顶部横向 chips 切换已保存场景；无场景时空态引导去编辑器。
/// - **沉浸**：全屏路由（脱离 Dock 与迷你播放器），左上角返回。
class VoxelCanvasPage extends ConsumerStatefulWidget {
  const VoxelCanvasPage({super.key});

  @override
  ConsumerState<VoxelCanvasPage> createState() => _VoxelCanvasPageState();
}

class _VoxelCanvasPageState extends ConsumerState<VoxelCanvasPage> {
  final VoxelCanvasController _controller = VoxelCanvasController();
  SoundBlockMixer? _mixer;
  String? _currentId;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    // 默认载入第一个已保存场景（若有）。
    final List<VoxelSoundScene> scenes = ref.read(voxelSoundScenesProvider);
    if (scenes.isNotEmpty) {
      _controller.load(scenes.first);
      _currentId = scenes.first.id;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _mixer?.dispose();
    super.dispose();
  }

  SoundBlockMixer get _ensureMixer =>
      _mixer ??= SoundBlockMixer(ref.read(audioServiceProvider));

  Future<void> _select(VoxelSoundScene scene) async {
    if (scene.id == _currentId) return;
    await _stopPreview();
    if (!mounted) return;
    _controller.load(scene);
    _currentId = scene.id;
  }

  Future<void> _playScene() async {
    if (_controller.blocks.isEmpty) return;
    await _ensureMixer.preview(_controller.blocks, loop: true);
    if (mounted) setState(() => _previewing = true);
  }

  Future<void> _stopPreview() async {
    await _ensureMixer.stop();
    if (mounted) setState(() => _previewing = false);
  }

  Future<void> _tapBlock(int col, int row) async {
    final String? typeId =
        _controller.blocks[VoxelCanvasController.keyOf(col, row)];
    if (typeId == null) return;
    await _ensureMixer.playType(voxelBlockTypeById(typeId));
  }

  @override
  Widget build(BuildContext context) {
    final List<VoxelSoundScene> scenes = ref.watch(voxelSoundScenesProvider);
    final VoxelSoundScene? active = _activeOf(scenes);

    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      body: Stack(
        children: <Widget>[
          // ── 玻璃背景层：极淡场景主色 + 噪点（与 AppShell 同语言）──
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      context.appColors.accent.withValues(alpha: 0.10),
                      context.appColors.bgPage,
                    ],
                    stops: const <double>[0, 0.6],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(child: NoiseTexture(seed: 11)),
          ),

          // ── 内容层 ─────────────────────────────────────
          SafeArea(
            child: scenes.isEmpty
                ? _EmptyScene(onCreate: _openEditor, onOpen3D: _open3DWorld)
                : _buildBody(scenes, active!),
          ),
        ],
      ),
    );
  }

  VoxelSoundScene? _activeOf(List<VoxelSoundScene> scenes) {
    if (scenes.isEmpty) return null;
    for (final VoxelSoundScene s in scenes) {
      if (s.id == _currentId) return s;
    }
    return scenes.first;
  }

  Widget _buildBody(List<VoxelSoundScene> scenes, VoxelSoundScene active) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool landscape = width >= AppSize.landscapeBreakpoint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── 顶栏：返回 + 场景切换 ──────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: Row(
            children: <Widget>[
              _BackButton(),
              const SizedBox(width: AppSpace.xs),
              const Text('沉浸画布', style: AppTextStyles.subtitle),
              const Spacer(),
              // 视图切换：2.5D 等距（当前页）↔ 3D 体素世界（Phase 1 预览）。
              // 原 2.5D 视图保留不删，二者可随时切换，Phase 5 前可回滚。
              ChoiceChip(
                label: const Text('2.5D'),
                selected: true,
                onSelected: (_) {},
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: AppSpace.xs),
              ChoiceChip(
                label: const Text('3D 视图'),
                selected: false,
                onSelected: (_) => _open3DWorld(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm),

        // 场景切换 chips（多场景时显示）
        if (scenes.length > 1)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              itemCount: scenes.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpace.xs),
              itemBuilder: (BuildContext context, int i) {
                final VoxelSoundScene s = scenes[i];
                final bool selected = s.id == active.id;
                return ChoiceChip(
                  label: Text(s.name),
                  selected: selected,
                  onSelected: (_) => unawaited(_select(s)),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Text(
              active.name,
              style: AppTextStyles.bodyMuted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: AppSpace.sm),

        // ── 中央：等距方块画布（可互动）──────────────
        Expanded(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (BuildContext context, Widget? child) {
              return VoxelCanvasView(
                controller: _controller,
                height: landscape ? 420 : 360,
                tileW: 46,
                tileH: 28,
                showGrid: false,
                onTapBlock: (int col, int row) => unawaited(_tapBlock(col, row)),
              );
            },
          ),
        ),

        // ── 底部：音景控制 + 编辑入口 ────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _previewing ? _stopPreview : _playScene,
                      icon: Icon(
                        _previewing
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _previewing ? '停止音景' : '播放音景',
                        style: AppTextStyles.button,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  OutlinedButton.icon(
                    onPressed: _openEditor,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('编辑', style: AppTextStyles.button),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                '点击方块可单独试听；「播放音景」按方块数量 / 位置混合整场循环。',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: context.appColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openEditor() {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VoxelSoundEditorPage(
            initialSceneId: _currentId,
          ),
        ),
      ),
    );
  }

  /// 打开 3D 体素世界预览页（Phase 1）。播放中的音景先停，避免两层环境音糊在一起。
  void _open3DWorld() {
    unawaited(_stopPreview());
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const VoxelWorld3DPage()),
      ),
    );
  }
}

/// 左上角返回按钮（40dp 半透明圆，同旧画布语言；不可返回时隐藏）。
class _BackButton extends StatelessWidget {
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
          color: context.appColors.accent.withValues(alpha: 0.10),
          border: Border.all(
            color: context.appColors.accent.withValues(alpha: 0.24),
          ),
        ),
        child: Icon(
          Icons.arrow_back,
          size: 20,
          color: context.appColors.iconPrimary,
        ),
      ),
    );
  }
}

/// 空态：还没有任何 2.5D 音效场景 → 引导去编辑器创建。
class _EmptyScene extends StatelessWidget {
  const _EmptyScene({required this.onCreate, required this.onOpen3D});

  final VoidCallback onCreate;
  final VoidCallback onOpen3D;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: context.appColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Icon(
              Icons.grid_view_rounded,
              size: 28,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          const Text('还没有 2.5D 音效场景', style: AppTextStyles.subtitle),
          const SizedBox(height: AppSpace.xs),
          Text(
            '先去编辑器摆几个音效方块，再回到这里沉浸试听',
            style: AppTextStyles.caption.copyWith(
              color: context.appColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('创建音效场景'),
          ),
          const SizedBox(height: AppSpace.xs),
          TextButton.icon(
            onPressed: onOpen3D,
            icon: const Icon(Icons.view_in_ar_rounded, size: 18),
            label: const Text('先去 3D 体素世界逛逛'),
          ),
        ],
      ),
    );
  }
}
