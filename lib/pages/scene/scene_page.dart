import '../../core/theme/app_theme_colors.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/scene.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/session/session_providers.dart';
import '../../providers/shell/shell_providers.dart';
import '../../providers/settings/performance_providers.dart';
import '../../providers/voxel/world_audio_provider.dart';
import '../../widgets/card_stack.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/lyrics/lyrics_view.dart';
import '../../widgets/scene/scene_color_panel.dart';
import '../../widgets/playback/unified_player.dart';
import '../../widgets/voxel/voxel_world_view3d.dart';
import '../../pages/voxel/voxel_main_menu_page.dart';
import '../../widgets/scene/voxel_scene_background.dart';
import '../../widgets/scene/scene_video_background.dart';
import '../../widgets/voxel/voxel_capture_models.dart';
import '../../services/log_service.dart';

/// 场景页 · 浅色场景卡堆 + 一体化播放面板（R1/R2）
///
/// v2 M1：接入统一模板 [PageScaffold]。
/// v2 M5-4：右上角 40dp **微光圆点**入口弹出**三选一** ——
/// 首页 / 沉浸画布 / 配色面板（P0-M5-4，配色写入 `Scene.visual` 等并持久化）。
/// v2 R1/R2：底部由「分开的播放卡片 + 全局迷你播放器」重构为
/// **一体化播放面板**（对齐旧沉浸画布 ControlBar 款式），
/// 并随场景页自带全局音量（R3）与白噪音开关（R4）。
/// R5：切换场景仅切换音景层与视觉，**不中断当前音乐播放**。
class ScenePage extends ConsumerWidget {
  const ScenePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Scene> scenes = ref.watch(sceneOrderProvider);
    final int activeIndex = ref.watch(currentSceneIndexProvider);
    final Scene active = ref.watch(activeSceneProvider);
    final VoxelSceneCapture? capture = active.voxelCapture;
    // H2：右上角「游戏背景」开关 + 长按实时渲染。
    final bool bgOn = ref.watch(voxelBgEnabledProvider);
    final bool bgLive = ref.watch(voxelBgLiveProvider);
    final bool bgAnim = ref.watch(sceneBgAnimProvider);
    // 实时渲染 = 实时开关 或 动画开关（二者联动取并集，显示与实际不再不同步）。
    final bool bgRealtime = bgLive || bgAnim;

    return PageScaffold(
      title: Terms.scene,
      actions: <Widget>[
        // H2：游戏背景开关——点击开/关体素取景背景（可叠加现有深色背景）；
        // 长按强制「实时渲染」（省电/性能档也不退化静态帧）。
        _VoxelBgToggle(
          enabled: bgOn,
          live: bgRealtime,
          available: capture != null,
          onToggle: () => ref
              .read(voxelBgEnabledProvider.notifier)
              .state = !bgOn,
          onLongPress: () {
            // 联动：实时开关与动画开关同步翻转（取并集，关两者 = 静态单帧）。
            final bool next = !bgRealtime;
            ref.read(voxelBgLiveProvider.notifier).state = next;
            ref.read(sceneBgAnimProvider.notifier).state = next;
          },
        ),
        _GlowEntryButton(onTap: () => _showEntrySheet(context, ref)),
        // cl29·②：相机功能迁入 Scene 模块——场景页直接可达「拍照取景」。
        // 用户确认：进入前询问「基于哪个存档/世界进入」——拍照取景基于
        // 存档的种子世界，避免总是新建一个空白默认世界。
        _SceneIconButton(
          icon: Icons.camera_alt_outlined,
          tooltip: '拍照取景',
          onTap: () => _openCameraWithSaveChoice(context, ref),
        ),
        // cl29·②：场景评估（当前场景取景快照的信息面板）。
        _SceneIconButton(
          icon: Icons.analytics_outlined,
          tooltip: '场景评估',
          onTap: () => _showEvalSheet(context, ref),
        ),
      ],
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // H2：开关关闭或该场景无取景 → 回退原有深色渐变背景。
          // R26skel-b4：B站视频源可作场景背景——当前曲目来自 B站时，
          // 背景切为视频画面（静音随音乐播放）；否则照旧体素取景。
          // ⚠️ 仅场景页/播放器背景；3D 游戏内不放视频（用户明确要求）。
          if (capture != null && bgOn)
            Positioned.fill(
              child: SceneVideoBackground(
                fallback: VoxelSceneBackground(
                  key: ValueKey(capture),
                  capture: capture,
                  forceLive: bgRealtime,
                ),
              ),
            ),
          Positioned.fill(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: SceneCardStack(
              scenes: scenes,
              currentIndex: activeIndex,
              nowPlaying: ref.watch(nowPlayingProvider),
              isPlaying: ref.watch(isPlayingProvider).valueOrNull ?? false,
              onSceneChanged: (int i) {
                ref.read(currentSceneIndexProvider.notifier).state = i;
                final Scene scene = scenes[i];
                // R5：仅切换音景层，音乐由 AppShell/播放面板继续播放
                unawaited(ref.read(audioServiceProvider).switchSoundscape(scene));
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.sm,
              AppSpace.md,
              AppSpace.sm,
            ),
            // 歌词区：LyricsView 自行跟随 audio_providers 的当前曲目与播放进度
            child: UnifiedPlayer(lyricsSlot: LyricsView()),
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// R26skel：主页场景右上角「拍照取景」——把**拍到的场景**列出来（含取景
  /// 快照的场景），用户选；可选「去拍新场景」；随后跳转**游戏唯一入口**
  /// （游戏主菜单）。不再直接 push [VoxelWorld3DPage]——游戏只能从主菜单
  /// 进入，避免叠加游戏/叠加存档。
  Future<void> _openCameraWithSaveChoice(
      BuildContext context, WidgetRef ref) async {
    final List<Scene> scenes = ref.read(sceneOrderProvider);
    final List<Scene> captured = <Scene>[
      for (final Scene s in scenes)
        if (s.voxelCapture != null) s,
    ];
    if (!context.mounted) return;
    final Scene? chosen = await showModalBottomSheet<Scene>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.camera_alt_outlined,
                    color: context.appColors.accent),
                title: Text('拍到的场景', style: context.appText.body),
                subtitle: Text('选一个场景，或去拍新的，然后进入游戏', style: context.appText.artist),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    // 「去拍新场景」：进入游戏主菜单 → 世界存档 → 拍照取景。
                    ListTile(
                      leading: Icon(Icons.add_a_photo_outlined,
                          color: context.appColors.iconPrimary),
                      title: Text('去拍新场景', style: context.appText.body),
                      subtitle: Text('进入游戏，在 3D 世界取景', style: context.appText.artist),
                      onTap: () => Navigator.of(sheetContext).pop(),
                    ),
                    for (final Scene s in captured)
                      ListTile(
                        leading: Icon(Icons.auto_awesome,
                            color: context.appColors.iconPrimary),
                        title: Text(s.name, style: context.appText.body),
                        subtitle: Text('已拍 · 进入游戏', style: context.appText.artist),
                        onTap: () => Navigator.of(sheetContext).pop(s),
                      ),
                    if (captured.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Text(
                          '还没有拍过的场景——点「去拍新场景」进游戏拍一张。',
                          style: context.appText.artist,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted) return;
    // 无论选了哪个场景 / 去拍，都跳到游戏主菜单（唯一入口）。
    if (chosen != null) {
      // 选中场景：切为当前场景（背景/音景跟随），再进游戏主菜单。
      final int idx = scenes.indexOf(chosen);
      if (idx >= 0) {
        ref.read(currentSceneIndexProvider.notifier).state = idx;
        ref.read(voxelBgEnabledProvider.notifier).state = true;
      }
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VoxelMainMenuPage()),
    );
  }

  /// R26fix：进入 3D 世界必须选存档（修复「绕过存档管理直接进全新世界」）。
  /// R26skel：改为跳转**游戏主菜单**——游戏唯一入口，跳转最远到主菜单；
  /// 存档经主菜单「世界存档」进入，其他地方不允许新建/跳转/恢复存档。
  Future<void> _openWorldWithSaveChoice(
      BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VoxelMainMenuPage()),
    );
  }

  Future<void> _showEntrySheet(BuildContext context, WidgetRef ref) async {
    LogService.instance.i('ui', '场景入口弹层：开始打开');
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.appColors.bgSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        builder: (BuildContext sheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: Icon(
                    Icons.home_outlined,
                    color: context.appColors.iconPrimary,
                  ),
                  title: Text('首页', style: context.appText.body),
                  subtitle: Text('回到 Shell 内的隐藏首页', style: context.appText.artist),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setShellPage(ref, ShellPage.home);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.auto_awesome,
                    color: context.appColors.iconPrimary,
                  ),
                  title: Text('3D 世界', style: context.appText.body),
                  subtitle: Text('全屏进入体素世界（经典方块人 / 自由探索）', style: context.appText.artist),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openWorldWithSaveChoice(context, ref);
                  },
                ),
                // M5-4 新增第三项：配色面板（P0-M5-4）
                ListTile(
                  leading: Icon(
                    Icons.palette_outlined,
                    color: context.appColors.iconPrimary,
                  ),
                  title: Text('配色面板', style: context.appText.body),
                  subtitle: Text('自定义当前场景主色 / 强调色 / 背景渐变', style: context.appText.artist),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    final Scene scene = ref.read(activeSceneProvider);
                    showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: context.appColors.bgSurface,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(AppRadius.lg),
                        ),
                      ),
                      builder: (_) => SceneColorPanel(scene: scene),
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
      LogService.instance.d('ui', '场景入口弹层：已关闭');
    } catch (e) {
      // 弹层期间任何 Dart 异常：记录不静默（native 崩溃则进程直接消失，
      // 此时只有「开始打开」一条日志，可据此二分）。
      LogService.instance.e('ui', '场景入口弹层异常: $e');
    }
  }

  /// cl29·②：场景评估底部弹层——展示当前场景取景快照的评估信息。
  Future<void> _showEvalSheet(BuildContext context, WidgetRef ref) async {
    final Scene scene = ref.read(activeSceneProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) =>
          _SceneEvalSheet(cap: scene.voxelCapture, sceneName: scene.name),
    );
  }
}

/// 右上角 40dp **微光圆点**入口按钮（P0-G2 / 已裁决 ②）。
///
/// 微光 = 品牌紫 12% 外圈 + 紫描边；整体 40dp 圆形，触控热区 ≥44dp（C9）。
/// H2：右上角「游戏背景」开关——点击开/关体素取景背景（可叠加现有深色
/// 背景），长按强制「实时渲染」（省电/性能档也不退化静态帧）。
class _VoxelBgToggle extends StatelessWidget {
  const _VoxelBgToggle({
    required this.enabled,
    required this.live,
    required this.available,
    required this.onToggle,
    required this.onLongPress,
  });

  final bool enabled;
  final bool live;
  final bool available;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSize.touchMin,
      height: AppSize.touchMin,
      alignment: Alignment.center,
      child: Tooltip(
        message: live
            ? '游戏背景已开 · 实时渲染中（长按关闭实时）'
            : (enabled
                ? '游戏背景已开（长按实时渲染）'
                : '游戏背景已关（点击开启）'),
        child: GestureDetector(
          onTap: available ? onToggle : null,
          onLongPress: available ? onLongPress : null,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? context.appColors.accent.withValues(alpha: 0.22)
                  : context.appColors.bgSurface,
              border: Border.all(
                color: enabled
                    ? context.appColors.accent
                    : context.appColors.accentSoft,
                width: 1.5,
              ),
            ),
            child: Icon(
              live
                  ? Icons.visibility_rounded
                  : (enabled
                      ? Icons.view_in_ar_rounded
                      : Icons.view_in_ar_outlined),
              size: AppSize.iconSm,
              color: enabled
                  ? context.appColors.accent
                  : context.appColors.iconPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowEntryButton extends StatelessWidget {
  const _GlowEntryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSize.touchMin,
      height: AppSize.touchMin,
      alignment: Alignment.center,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.appColors.bgSurface,
              border: Border.all(color: context.appColors.accentSoft, width: 1.5),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: context.appColors.accentSoft,
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.grid_view_rounded,
              size: AppSize.iconSm,
              color: context.appColors.iconPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// cl29·②：场景页统一入口的圆形图标按钮（拍照取景 / 场景评估）。
class _SceneIconButton extends StatelessWidget {
  const _SceneIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSize.touchMin,
      height: AppSize.touchMin,
      alignment: Alignment.center,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.appColors.bgSurface,
                border: Border.all(
                  color: context.appColors.accentSoft,
                  width: 1.5,
                ),
              ),
              child: Icon(icon, size: AppSize.iconSm,
                  color: context.appColors.iconPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// cl29·②：场景评估面板——读取当前场景的 [VoxelSceneCapture] 展示评估信息。
class _SceneEvalSheet extends StatelessWidget {
  const _SceneEvalSheet({required this.cap, required this.sceneName});

  final VoxelSceneCapture? cap;
  final String sceneName;

  static const double _deg = 180 / 3.141592653589793;

  @override
  Widget build(BuildContext context) {
    final Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: Text('场景评估 · $sceneName', style: context.appText.body),
    );
    if (cap == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          header,
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              0,
              AppSpace.lg,
              AppSpace.lg,
            ),
            child: Text(
              '该场景暂无取景快照。进入 3D 世界点相机图标拍照取景，即可生成'
              '场景背景并在此查看评估信息。',
              style: context.appText.artist,
            ),
          ),
        ],
      );
    }
    final VoxelSceneCapture c = cap!;
    final String seedHex =
        '#${(c.seed & 0xffffffff).toRadixString(16).toUpperCase().padLeft(8, '0')}';
    final String phase = c.timePhase < 0.125 || c.timePhase >= 0.875
        ? '黎明'
        : (c.timePhase < 0.375 ? '正午' : (c.timePhase < 0.625 ? '黄昏' : '夜'));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        header,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Column(
            children: <Widget>[
              _EvalRow('世界种子', seedHex),
              _EvalRow(
                '机位 X / Y / Z',
                '${c.cameraX.toStringAsFixed(1)} / '
                '${c.cameraY.toStringAsFixed(1)} / '
                '${c.cameraZ.toStringAsFixed(1)}',
              ),
              _EvalRow(
                '偏航 / 俯仰',
                '${(c.yaw * _deg).toStringAsFixed(1)}° / '
                '${(c.pitch * _deg).toStringAsFixed(1)}°',
              ),
              _EvalRow('视场角 FOV', '${(c.fov * _deg).toStringAsFixed(1)}°'),
              _EvalRow('时相', phase),
              _EvalRow('音景源', '${c.sounds.length} 个'),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
      ],
    );
  }
}

class _EvalRow extends StatelessWidget {
  const _EvalRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: context.appText.artist),
            ),
            Text(value, style: context.appText.body),
          ],
        ),
      );
}
