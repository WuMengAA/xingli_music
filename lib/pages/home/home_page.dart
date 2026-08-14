import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/scene.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/track_cover.dart';
import '../../widgets/scene/voxel_scene_background.dart';
import '../../widgets/voxel/voxel_capture_models.dart';

/// 首页 · 场景大媒体卡片 + 当前播放卡（v2 M1 接入 PageScaffold，P0-C4：无搜索栏）。
///
/// 顶部为**当前场景的大媒体卡片**（渐变封面 + 场景名/mood/描述），
/// 下方为当前播放曲目（封面 + 标题/歌手）。Dock 全灰（Shell 派生）。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Scene scene = ref.watch(activeSceneProvider);
    final Track? now = ref.watch(nowPlayingProvider);

    return PageScaffold(
      title: Terms.nowPlaying,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          // ── 场景大媒体卡片（R26fx：主页大卡，渐变封面 + 场景信息）──
          _SceneHeroCard(scene: scene),
          const SizedBox(height: 18),
          // ── 当前播放曲目 ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: context.appColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('当前播放', style: context.appText.caption),
                const SizedBox(height: AppSpace.md),
                Center(
                  child: TrackCover(
                    track: now,
                    size: 140,
                    radius: AppRadius.lg,
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Center(
                  child: Text(
                    now?.title ?? scene.track,
                    style: context.appText.title.copyWith(fontSize: 26),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Center(
                  child: Text(
                    now?.artist ?? scene.artist,
                    style: context.appText.bodyMuted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 场景大媒体卡：渐变封面 + 大 glyph + 场景名/mood/描述。
class _SceneHeroCard extends StatelessWidget {
  const _SceneHeroCard({required this.scene});
  final Scene scene;

  @override
  Widget build(BuildContext context) {
    final VoxelSceneCapture? capture = scene.voxelCapture;
    final List<Color> colors = scene.visual.gradientColors.isNotEmpty
        ? scene.visual.gradientColors
        : const <Color>[Color(0xFF0B1220), Color(0xFF1B2A4A)];
    return Container(
      height: 180,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: context.appColors.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // cl42·④：有取景快照 → 显示存档图片（静态单帧，剥离空间音效，
          // 不另起音效引擎；与场景页背景同源，首页也能「跳出存档的图片」）。
          if (capture != null)
            Positioned.fill(
              child: VoxelSceneBackground(
                key: ValueKey(capture),
                capture: capture.withSounds(const <VoxelSoundscapeSource>[]),
                forceLive: false,
              ),
            ),
          // 取景图上压暗，保证文字可读。
          if (capture != null)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                ),
              ),
            ),
          // 无取景 → 回退渐变封面 + 大 glyph。
          if (capture == null) ...<Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors.length >= 2
                      ? <Color>[colors[0], colors[1]]
                      : <Color>[colors[0], colors[0]],
                  stops: scene.visual.stops,
                ),
              ),
            ),
            Positioned(
              right: -14,
              bottom: -24,
              child: Text(
                scene.visual.glyph,
                style: TextStyle(
                  fontSize: 150,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ),
          ],
          // 场景信息。
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    scene.mood,
                    style: context.appText.caption
                        .copyWith(color: Colors.white, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  scene.name,
                  style: context.appText.title
                      .copyWith(color: Colors.white, fontSize: 22),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (scene.desc.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    scene.desc,
                    style: context.appText.artist
                        .copyWith(color: Colors.white70, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
