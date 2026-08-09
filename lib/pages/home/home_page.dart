import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/scene.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/track_cover.dart';

/// 首页 · 当前播放卡（v2 M1 接入 PageScaffold，P0-C4：无搜索栏）。
///
/// 展示当前场景 + 当前播放曲目；Dock 全灰（Shell 派生）。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Scene scene = ref.watch(activeSceneProvider);
    final Track? now = ref.watch(nowPlayingProvider);
    final double width = MediaQuery.sizeOf(context).width;

    return PageScaffold(
      title: Terms.nowPlaying,
      body: Center(
        child: Container(
          width: (width * 0.78).clamp(0.0, 480.0),
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(scene.name,
                  style: AppTextStyles.bodyMuted),
              const SizedBox(height: AppSpace.md),
              Center(
                child: TrackCover(
                  track: now,
                  size: 120,
                  radius: AppRadius.lg,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                now?.title ?? scene.track,
                style: AppTextStyles.title.copyWith(fontSize: 28),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                now?.artist ?? scene.artist,
                style: AppTextStyles.bodyMuted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                '场景：${scene.name} · ${scene.mood}',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
