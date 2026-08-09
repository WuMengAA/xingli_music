import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../models/scene.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/session/session_providers.dart';
import '../../providers/shell/shell_providers.dart';
import '../../widgets/card_stack.dart';
import '../canvas/canvas_page.dart';

/// 场景页 · SceneCardStack 无限画布（主内容，背景/控制栏由 AppShell 提供）
///
/// 右上角提供 40dp 圆形入口按钮（Q7-A / P0-G2）：点击弹出「首页 / 沉浸画布」
/// 二选一 —— 首页切到 Shell 内隐藏页（Dock 全灰），沉浸画布以全屏路由打开
/// （脱离 Shell，无 Dock / 迷你播放器，P0-G3）。
class ScenePage extends ConsumerWidget {
  const ScenePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Scene> scenes = ref.watch(sceneOrderProvider);
    final int activeIndex = ref.watch(currentSceneIndexProvider);

    return Stack(
      children: <Widget>[
        SceneCardStack(
          scenes: scenes,
          currentIndex: activeIndex,
          nowPlaying: ref.watch(nowPlayingProvider),
          isPlaying: ref.watch(isPlayingProvider).valueOrNull ?? false,
          onSceneChanged: (int i) {
            ref.read(currentSceneIndexProvider.notifier).state = i;
            final Scene scene = scenes[i];
            unawaited(ref.read(audioServiceProvider).switchSoundscape(scene));
          },
        ),
        Positioned(
          top: 0,
          right: 0,
          child: _EntryButton(onTap: () => _showEntrySheet(context, ref)),
        ),
      ],
    );
  }

  /// Q7-A 二选一弹窗：首页（Shell 内隐藏页）/ 沉浸画布（全屏路由）。
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
                subtitle: const Text('全屏进入，脱离 Dock 与迷你播放器', style: AppTextStyles.artist),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const CanvasPage()),
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

/// 右上角 40dp 圆形入口按钮（P0-G2）。
class _EntryButton extends StatelessWidget {
  const _EntryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.grid_view_rounded, size: AppSize.iconSm, color: AppColors.iconPrimary),
        ),
      ),
    );
  }
}