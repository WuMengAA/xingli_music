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
import '../canvas/voxel_canvas_page.dart';

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

    return PageScaffold(
      title: Terms.scene,
      actions: <Widget>[
        _GlowEntryButton(onTap: () => _showEntrySheet(context, ref)),
      ],
      body: Column(
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
    );
  }

  /// 已裁决入口：三选一（首页 / 沉浸画布 / 配色面板）。
  Future<void> _showEntrySheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(
                  Icons.home_outlined,
                  color: AppColors.iconPrimary,
                ),
                title: const Text('首页', style: AppTextStyles.body),
                subtitle: const Text('回到 Shell 内的隐藏首页', style: AppTextStyles.artist),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setShellPage(ref, ShellPage.home);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.auto_awesome,
                  color: AppColors.iconPrimary,
                ),
                title: const Text('沉浸画布', style: AppTextStyles.body),
                subtitle: const Text('全屏进入 2.5D 场景，点击方块发声', style: AppTextStyles.artist),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const VoxelCanvasPage()),
                  );
                },
              ),
              // M5-4 新增第三项：配色面板（P0-M5-4）
              ListTile(
                leading: const Icon(
                  Icons.palette_outlined,
                  color: AppColors.iconPrimary,
                ),
                title: const Text('配色面板', style: AppTextStyles.body),
                subtitle: const Text('自定义当前场景主色 / 强调色 / 背景渐变', style: AppTextStyles.artist),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  final Scene scene = ref.read(activeSceneProvider);
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: AppColors.bgSurface,
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
              color: AppColors.bgSurface,
              border: Border.all(color: AppColors.accentSoft, width: 1.5),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: AppColors.accentSoft,
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.grid_view_rounded,
              size: AppSize.iconSm,
              color: AppColors.iconPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
