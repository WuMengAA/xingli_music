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
import '../../widgets/card_stack.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/lyrics/lyrics_view.dart';
import '../../widgets/scene/scene_color_panel.dart';
import '../../widgets/playback/unified_player.dart';
import '../../widgets/voxel/voxel_world_view3d.dart';
import '../../widgets/scene/voxel_scene_background.dart';
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

    return PageScaffold(
      title: Terms.scene,
      actions: <Widget>[
        _GlowEntryButton(onTap: () => _showEntrySheet(context, ref)),
      ],
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (capture != null)
            Positioned.fill(
              child: VoxelSceneBackground(
                key: ValueKey(capture),
                capture: capture,
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

  /// 已裁决入口：三选一（首页 / 沉浸画布 / 配色面板）。
  ///
  /// 打点二分：Windows 上点击此按钮偶发 native 闪退（无 Dart 异常日志），
  /// 借「打开前 → 关闭后」两条日志确认崩溃发生在弹层渲染期间还是之前。
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
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const VoxelWorld3DPage()),
                    );
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
}

/// 右上角 40dp **微光圆点**入口按钮（P0-G2 / 已裁决 ②）。
///
/// 微光 = 品牌紫 12% 外圈 + 紫描边；整体 40dp 圆形，触控热区 ≥44dp（C9）。
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
