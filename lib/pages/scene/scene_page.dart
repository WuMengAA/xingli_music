import '../../core/theme/app_theme_colors.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../models/scene.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/session/session_providers.dart';
import '../../providers/settings/performance_providers.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../providers/voxel/world_audio_provider.dart';
import '../../widgets/card_stack.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/voxel/voxel_capture_models.dart';
import '../../widgets/scene/voxel_scene_background.dart';
import '../../widgets/scene/scene_video_background.dart';
import '../../pages/scene/custom_scene_edit_page.dart';
import '../../pages/voxel/voxel_main_menu_page.dart';
import '../../widgets/common/scene_eval_sheet.dart';

/// 主页 · 场景内容（原场景页合并进主页，R1/R2）
///
/// 顶部操作条（游戏背景开关 / 拍照取景 / 场景评估）+ 场景卡堆 +
/// 一体化播放面板（歌词内嵌）。切换场景仅切换音景层与视觉，
/// **不中断当前音乐播放**（R5）。
///
/// 视觉严格对齐画布「Screen · 首页重做 v1」(3:1)：
///  - 顶部问候语 + 品牌名；
///  - 右侧三个 32×32 圆形操作按钮（游戏背景 / 拍照取景 / 场景评估）；
///  - 柔光晕 + 双层玻璃场景卡（Hero + 背卡） + 轮播圆点；
///  - 底部胶囊音乐卡。
class HomeSceneContent extends ConsumerWidget {
  const HomeSceneContent({super.key});

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
    // cl76：视频背景改按「视听」开关——开启即按当前曲目播 B站背景视频，
    // 不再要求先「拍摄场景」；关闭时回退体素取景 / 深色渐变。
    final bool visualOn = ref.watch(biliVisualEnabledProvider);

    final AppThemeColors c = context.appColors;

    return PageScaffold(
      // 画布顶部是「问候语 + 品牌名」两行，标题本身为空，由 body 内呈现。
      title: '',
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
        // cl29·②：相机功能迁入 Scene 模块——场景页直接可达「拍照取景」。
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
          // cl76：视频背景按「视听」开关——开启（默认）即按当前曲目自动匹配
          // B站视频作背景画面（静音随音乐播），无匹配/失败回退体素取景（有取景
          // 且开启时）或深色渐变；视听关闭时照旧体素取景。
          // ⚠️ 仅场景页/播放器背景；3D 游戏内不放视频（用户明确要求）。
          if (visualOn)
            Positioned.fill(
              // cl53-F1：主页视频背景四角圆角（与 ContentContainer 玻璃表面
              // 一致），顶部底部都圆角，避免直角贴边显得突兀。
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: SceneVideoBackground(
                  fallback: (capture != null && bgOn)
                      ? VoxelSceneBackground(
                          key: ValueKey(capture),
                          capture: capture,
                          forceLive: bgRealtime,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                c.bgSurfaceSunken,
                                c.bgSurface,
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            )
          else if (capture != null && bgOn)
            Positioned.fill(
              child: VoxelSceneBackground(
                key: ValueKey(capture),
                capture: capture,
                forceLive: bgRealtime,
              ),
            ),
          // cl04：首页不滚动——固定布局（问候语 + 场景卡 + 圆点 + 音乐卡）一屏内，
          // 场景卡占剩余空间自适应（FittedBox 防溢出/裁切）。
          Column(
            children: <Widget>[
                // ── 顶部：问候语 + 品牌名 ──────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.md,
                    AppSpace.lg,
                    AppSpace.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '晚上好，听点什么？',
                        style: context.appText.caption.copyWith(
                          fontSize: 13,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '星璃音乐',
                        style: context.appText.title.copyWith(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),

                // ── 场景卡（柔光晕 + 背卡 + Hero + 圆点）────────
                // 占剩余空间自适应，不随页面滚动。
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    child: Builder(
                      builder: (BuildContext ctx) {
                        final double screenW = MediaQuery.of(ctx).size.width;
                        final double cardW = screenW * 0.94;
                        final double cardH = cardW * 9 / 16;
                        return Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: cardW,
                              height: cardH + 44,
                              child: Stack(
                            clipBehavior: Clip.none,
                            children: <Widget>[
                              // scene-glow：卡后柔光晕（accent 派生，跟随皮肤）。
                              Positioned(
                                top: -30,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Container(
                                    width: 200,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: c.accent.withValues(alpha: 0.16),
                                    ),
                                  ),
                                ),
                              ),
                              // scene-card-back：背卡（白色半透明 + 细描边），
                              // 在 Hero 后微微探出，形成双层玻璃景深。
                              Positioned(
                                top: 14,
                                left: 6,
                                right: 6,
                                child: Container(
                                  height: cardH,
                                  decoration: BoxDecoration(
                                    color: c.bgCard.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: c.border.withValues(alpha: 0.5),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                              // 复用既有 SceneCardStack（场景切换 / 音景 / 长按编辑
                              // 逻辑全部保留，仅视觉贴合画布双层玻璃）。
                              SceneCardStack(
                                scenes: scenes,
                                currentIndex: activeIndex,
                                // cl46-E：长按场景中间卡片 = 打开当前场景的详细 / 个性编辑。
                                onLongPress: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => CustomSceneEditPage(
                                      scene: ref.read(activeSceneProvider),
                                    ),
                                  ),
                                ),
                                onSceneChanged: (int i) {
                                  ref.read(currentSceneIndexProvider.notifier).state = i;
                                  final Scene scene = scenes[i];
                                  // R5：仅切换音景层，音乐由 AppShell/播放面板继续播放
                                  unawaited(ref
                                      .read(audioServiceProvider)
                                      .switchSoundscape(scene));
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),

                // ── 轮播圆点（carousel dots）──────────────────
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (int i = 0; i < scenes.length; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == activeIndex ? 10 : 6,
                          height: i == activeIndex ? 10 : 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == activeIndex
                                ? c.accent
                                : c.iconInactive.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
              ],
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

  /// cl29·②：场景评估底部弹层——展示当前场景取景快照的评估信息（预设组件 SceneEvalSheet）。
  Future<void> _showEvalSheet(BuildContext context, WidgetRef ref) async {
    final Scene scene = ref.read(activeSceneProvider);
    final VoxelSceneCapture? cap = scene.voxelCapture;
    if (cap == null) {
      // 暂无取景快照：用浅提示底部弹层引导用户拍照取景。
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.appColors.bgSurface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
          ),
          child: Text(
            '该场景暂无取景快照。进入 3D 世界点相机图标拍照取景，即可生成'
            '场景背景并在此查看评估信息。',
            style: context.appText.artist,
          ),
        ),
      );
      return;
    }
    const double deg = 180 / 3.141592653589793;
    final String seedHex =
        '#${(cap.seed & 0xffffffff).toRadixString(16).toUpperCase().padLeft(8, '0')}';
    final String phase = cap.timePhase < 0.125 || cap.timePhase >= 0.875
        ? '黎明'
        : (cap.timePhase < 0.375 ? '正午' : (cap.timePhase < 0.625 ? '黄昏' : '夜'));
    await SceneEvalSheet.show(
      context: context,
      title: '场景评估 · ${scene.name}',
      rows: <SceneEvalRow>[
        SceneEvalRow(label: '世界种子', value: seedHex),
        SceneEvalRow(
          label: '机位 X / Y / Z',
          value: '${cap.cameraX.toStringAsFixed(1)} / '
              '${cap.cameraY.toStringAsFixed(1)} / '
              '${cap.cameraZ.toStringAsFixed(1)}',
        ),
        SceneEvalRow(
          label: '偏航 / 俯仰',
          value: '${(cap.yaw * deg).toStringAsFixed(1)}° / '
              '${(cap.pitch * deg).toStringAsFixed(1)}°',
        ),
        SceneEvalRow(
          label: '视场角 FOV',
          value: '${(cap.fov * deg).toStringAsFixed(1)}°',
        ),
        SceneEvalRow(label: '时相', value: phase),
        SceneEvalRow(label: '音景源', value: '${cap.sounds.length} 个'),
      ],
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
            width: 32,
            height: 32,
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
              size: 18,
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
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.appColors.bgSurface,
                border: Border.all(
                  color: context.appColors.accentSoft,
                  width: 1.5,
                ),
              ),
              child: Icon(icon, size: 18,
                  color: context.appColors.iconPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
