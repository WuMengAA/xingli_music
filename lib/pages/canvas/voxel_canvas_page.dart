import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/voxel.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/envelope_providers.dart';
import '../../providers/scene/voxel_scene_providers.dart';
import '../../services/audio/sound_block_mixer.dart';
import '../../services/audio/visualizer_service.dart';
import '../../services/voxel/voxel_scene_io.dart';
import '../../widgets/voxel/voxel_spectrum_bar.dart';
import '../../widgets/noise_texture.dart';
import '../../widgets/voxel/voxel_canvas_controller.dart';
import '../../widgets/voxel/voxel_canvas_view.dart';
import '../../pages/voxel/voxel_main_menu_page.dart';
import '../scene/voxel_sound_editor_page.dart';
import '../../widgets/notification/app_notify.dart';
import '../../widgets/common/share_panel.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 新版沉浸画布（V3）：2.5D 场景编辑后的可互动场景
/// ════════════════════════════════════════════════════════════════════════
///
/// 取代旧版 [CanvasPage]（已删除：粒子 / 调色盘 / 心情 / 更多面板的暗色孤岛）。
///
/// - **数据源**：用户在 2.5D 音效编辑器（[VoxelSoundEditorPage]）里保存的
///   [VoxelSoundScene] 列表（`voxelSoundScenesProvider`），非写死场景。
///   也可由 3D 世界「转化为 2.5D」直接带入（[initialScene]）。
/// - **渲染**：共享 [VoxelCanvasView] 等距方块画布（纯 CustomPaint），
///   背景沿用 AppShell 玻璃层语言（accent 0.10→bgPage 渐变 + 噪点）。
/// - **互动**：点击方块 → 播放该类型音效一次（[SoundBlockMixer.playType]）；
///   底部「播放音景」→ 按方块数量/位置混合整场循环播放；再点停止。
/// - **音乐可视化（Module "MusicViz-2.5D"）**：播放中若有真实离线包络
///   （[envelopeSamplerProvider]），方块随节拍脉冲、高度随频段能量起伏；
///   无离线分析时降级到合成 [VisualizerService]（提示"合成数据"），不崩溃。
/// - **多场景**：顶部横向 chips 切换已保存场景；无场景时空态引导去编辑器。
/// - **沉浸**：全屏路由（脱离 Dock 与迷你播放器），左上角返回。
class VoxelCanvasPage extends ConsumerStatefulWidget {
  const VoxelCanvasPage({super.key, this.initialScene});

  /// 由 3D 世界「转化为 2.5D」带入的场景（优先载入）。
  final VoxelSoundScene? initialScene;

  @override
  ConsumerState<VoxelCanvasPage> createState() => _VoxelCanvasPageState();
}

class _VoxelCanvasPageState extends ConsumerState<VoxelCanvasPage> {
  final VoxelCanvasController _controller = VoxelCanvasController();
  SoundBlockMixer? _mixer;
  String? _currentId;
  bool _previewing = false;

  // ── Module "MusicViz-2.5D"：播放进度 → 方块可视化帧 ──
  EnvelopePlaybackSampler? _sampler;
  VisualizerService? _fallback;
  StreamSubscription<List<double>>? _bandsSub;
  StreamSubscription<double>? _beatSub;
  bool _usingFallback = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialScene != null) {
      // 3D 世界提取带入：优先载入该场景（含 heights）。
      _controller.load(widget.initialScene!);
      _currentId = widget.initialScene!.id;
    } else {
      // 默认载入第一个已保存场景（若有）。
      final List<VoxelSoundScene> scenes =
          ref.read(voxelSoundScenesProvider);
      if (scenes.isNotEmpty) {
        _controller.load(scenes.first);
        _currentId = scenes.first.id;
      }
    }
  }

  /// 绑定可视化数据源：优先真实离线包络；无则降级合成源。
  ///
  /// 在 build 内调用（随 [envelopeSamplerProvider] 变化重建），按 identity 比对
  /// 决定是否重建订阅，避免每帧重复订阅。
  void _syncViz(EnvelopePlaybackSampler? sampler) {
    if (sampler != null) {
      if (!_usingFallback && sampler == _sampler) return;
      _teardownFallback();
      _sampler = sampler;
      _usingFallback = false;
      _bandsSub = sampler.bands.listen(
        (List<double> b) => _controller.applyEnvelope(b, _controller.vizBeat),
      );
      _beatSub = sampler.beat.listen(
        (double b) => _controller.applyEnvelope(
          _controller.vizBands ?? const <double>[],
          b,
        ),
      );
    } else {
      // 无真实包络 → 合成源（仅一次）。
      if (_usingFallback && _fallback != null) return;
      _teardownSampler();
      final VisualizerService fb =
          VisualizerService(ref.read(audioServiceProvider));
      fb.start();
      _fallback = fb;
      _usingFallback = true;
      // 合成源只暴露 level / bands：用低频段能量近似节拍脉冲。
      _bandsSub = fb.bands.listen((List<double> b) {
        final double beat = b.isEmpty
            ? 0.0
            : (b[0] * 0.6 + (b.length > 1 ? b[1] : 0.0) * 0.4).clamp(0.0, 1.0);
        _controller.applyEnvelope(b, beat);
      });
      _beatSub = null;
    }
  }

  void _teardownSampler() {
    _bandsSub?.cancel();
    _beatSub?.cancel();
    _bandsSub = null;
    _beatSub = null;
    _sampler = null;
  }

  void _teardownFallback() {
    _teardownSampler();
    _fallback?.dispose();
    _fallback = null;
    _usingFallback = false;
  }

  @override
  void dispose() {
    _teardownFallback();
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
    // 绑定音乐可视化源（真实离线包络优先，否则合成降级）。
    final EnvelopePlaybackSampler? sampler =
        ref.watch(envelopeSamplerProvider);
    _syncViz(sampler);
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
    // 合成降级提示（无离线包络时可视化非真实数据）。
    final bool vizSynthetic = ref.watch(envelopeSamplerProvider) == null;

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
              const SizedBox(width: AppSpace.xs),
              // 场景分享 / 导入（Phase 2：让 Phase 1 的产出可留存、可交换）。
              IconButton(
                icon: const Icon(Icons.download_rounded, size: 18),
                tooltip: '导入场景',
                visualDensity: VisualDensity.compact,
                onPressed: _importScene,
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded, size: 18),
                tooltip: '分享场景',
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(_shareScene(active)),
              ),
              // 可视化可调参数（Phase 2：viz 编辑态持久化）。
              IconButton(
                icon: const Icon(Icons.tune_rounded, size: 18),
                tooltip: '可视化设置',
                visualDensity: VisualDensity.compact,
                onPressed: _openVizSettings,
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

        if (vizSynthetic)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Text(
              '可视化使用合成数据（当前曲目无离线分析）',
              style: AppTextStyles.caption.copyWith(
                color: context.appColors.textTertiary,
              ),
            ),
          ),

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

        // ── Phase 2：实时频谱条（当前帧频段能量可视化）────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.xs,
            AppSpace.md,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '实时频谱',
                style: AppTextStyles.caption.copyWith(
                  color: context.appColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              VoxelSpectrumBar(controller: _controller, height: 52),
            ],
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
    // R26fix→R26skel：进入 3D 世界统一走「游戏主菜单」——游戏唯一入口，
    // 存档经主菜单「世界存档」进入，避免绕过存档管理直接进全新世界。
    unawaited(_stopPreview());
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const VoxelMainMenuPage(),
        ),
      ),
    );
  }

  /// 分享当前场景：先弹出分享面板选择渠道，再序列化为临时 JSON 文件并调起系统分享。
  Future<void> _shareScene(VoxelSoundScene scene) async {
    final ShareChannel? channel = await SharePanel.show(
      context: context,
      channels: <ShareChannel>[
        ShareChannel(icon: Icons.chat_bubble_outline, label: '微信'),
        ShareChannel(icon: Icons.group_outlined, label: 'QQ'),
        ShareChannel(icon: Icons.link, label: '链接'),
        ShareChannel(icon: Icons.share_rounded, label: '系统分享'),
      ],
    );
    if (channel == null || !mounted) return; // 用户取消
    try {
      final XFile x = await sceneToTempXFile(scene);
      await Share.shareXFiles(
        <XFile>[x],
        subject: scene.name,
        text: '星璃音乐 2.5D 音效场景：${scene.name}',
      );
    } catch (e) {
      if (mounted) _toast('分享失败，请稍后重试');
    }
  }

  /// 从外部 JSON 文件导入场景：解析 → 分配新 id → 存入场景列表并载入。
  Future<void> _importScene() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        allowMultiple: false,
      );
      final String? path = result?.files.single.path;
      if (path == null) return; // 用户取消
      final String content = await File(path).readAsString();
      final VoxelSoundScene parsed = decodeSceneFile(content);
      final VoxelSoundScene imported = parsed.copyWith(
        id: newSceneId(),
        name: '${parsed.name}（导入）',
      );
      await ref.read(voxelSoundScenesProvider.notifier).save(imported);
      if (mounted) {
        _controller.load(imported);
        _currentId = imported.id;
        setState(() {});
        _toast('已导入场景：${imported.name}');
      }
    } on SceneFileFormatException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('导入失败，请稍后重试');
    }
  }

  void _toast(String msg) {
    appNotify(context, msg);
  }

  /// 打开可视化设置面板：3 个滑块（振幅 / 涟漪位置权重 / 节拍脉冲）+ 重置。
  /// 改动即时写入控制器并随场景持久化（见 [VoxelCanvasController.setVizSettings]）。
  void _openVizSettings() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSt) {
          final VoxelVizSettings s = _controller.vizSettings;
          return AlertDialog(
            title: const Text('可视化设置'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _vizSlider(
                  setSt,
                  '起伏振幅',
                  s.amplitude,
                  0,
                  1.5,
                  (double v) => _controller.setVizSettings(
                    s.copyWith(amplitude: v),
                  ),
                ),
                _vizSlider(
                  setSt,
                  '涟漪位置权重',
                  s.ripplePosWeight,
                  0,
                  1,
                  (double v) => _controller.setVizSettings(
                    s.copyWith(ripplePosWeight: v),
                  ),
                ),
                _vizSlider(
                  setSt,
                  '节拍脉冲',
                  s.beatPulse,
                  0,
                  0.4,
                  (double v) => _controller.setVizSettings(
                    s.copyWith(beatPulse: v),
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  _controller.setVizSettings(const VoxelVizSettings());
                  setSt(() {});
                },
                child: const Text('重置'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 单个可视化滑块：标签 + 实时数值 + [Slider]，拖动即写控制器。
  Widget _vizSlider(
    StateSetter setSt,
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label, style: AppTextStyles.body),
              const Spacer(),
              Text(
                value.toStringAsFixed(2),
                style: AppTextStyles.caption.copyWith(
                  color: context.appColors.textTertiary,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: (double v) {
              onChanged(v);
              setSt(() {});
            },
          ),
        ],
      );
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
