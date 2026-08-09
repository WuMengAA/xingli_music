import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scene.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/session/session_providers.dart';
import '../../widgets/card_stack.dart';

/// 场景页 · SceneCardStack 无限画布（主内容，背景/控制栏由 AppShell 提供）
class ScenePage extends ConsumerWidget {
  const ScenePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Scene> scenes = ref.watch(sceneOrderProvider);
    final int activeIndex = ref.watch(currentSceneIndexProvider);

    return SceneCardStack(
        scenes: scenes,
        currentIndex: activeIndex,
        nowPlaying: ref.watch(nowPlayingProvider),
        isPlaying: ref.watch(isPlayingProvider).valueOrNull ?? false,
        onSceneChanged: (int i) {
          ref.read(currentSceneIndexProvider.notifier).state = i;
          final Scene scene = scenes[i];
          unawaited(ref.read(audioServiceProvider).switchSoundscape(scene));
        },
    );
  }
}