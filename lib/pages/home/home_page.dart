import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scene.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/scene_providers.dart';

/// 首页 · 当前播放卡（主内容，背景/控制栏由 AppShell 提供）
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Scene scene = ref.watch(activeSceneProvider);
    final Track? now = ref.watch(nowPlayingProvider);
    final ThemeData theme = Theme.of(context);
    final double w = MediaQuery.of(context).size.width;

    return Center(
        child: Container(
          width: w * 0.78,
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前播放',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  )),
              const SizedBox(height: 10),
              Text(scene.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  )),
              const SizedBox(height: 8),
              Text(now?.title ?? scene.track,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface,
                  )),
              const SizedBox(height: 4),
              Text(now?.artist ?? scene.artist,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  )),
            ],
          ),
        ),
    );
  }
}