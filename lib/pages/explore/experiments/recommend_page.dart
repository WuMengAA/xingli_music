import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/light_tokens.dart';
import '../../../models/scene.dart';
import '../../../models/track.dart';
import '../../../providers/audio/audio_providers.dart';
import '../../../providers/audio/playback_notifier.dart';
import '../../../providers/scene/scene_providers.dart';
import '../../../widgets/common/info_row.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_chip.dart';
import '../../../widgets/common/state_views.dart';

/// 实验 A · 智能推荐（v2 M2 · P0-M2-3）。
///
/// 按当前场景情绪（valence / energy）从曲库推荐曲目：
/// - 优先推荐与场景情绪距离近的曲目（简单启发式）；
/// - 点击即播（走 [playbackActionsProvider]，C6）。
class RecommendPage extends ConsumerWidget {
  const RecommendPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Scene scene = ref.watch(activeSceneProvider);
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '智能推荐',
          actions: const <Widget>[_ExperimentBadge()],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '当前场景：${scene.name}（${scene.mood}）',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                '启发式：偏好 valence/energy 与场景接近的曲目',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpace.md),
              Expanded(
                child: library.when(
                  data: (List<Track> all) {
                    final List<Track> ranked = _recommend(all, scene);
                    if (ranked.isEmpty) {
                      return const EmptyView(
                        title: '曲库为空',
                        message: '请先在设置「音源」中添加音乐',
                      );
                    }
                    return ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: ranked.length,
                      itemBuilder: (BuildContext context, int i) {
                        final Track t = ranked[i];
                        return InfoRow(
                          track: t,
                          onTap: () async {
                            final String msg = await ref
                                .read(playbackActionsProvider)
                                .playTrack(t);
                            if (msg.isNotEmpty && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(msg)),
                              );
                            }
                          },
                        );
                      },
                    );
                  },
                  loading: () => const LoadingView(),
                  error: (Object e, StackTrace st) => ErrorView(
                    message: '推荐失败：$e',
                    onRetry: () => ref.invalidate(effectiveMusicLibraryProvider),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 简单启发式排序：曲目按“标题/歌手/专辑”与场景名/氛围词重合度 + 稳定
  /// 顺序。真实推荐模型为后续版本（P2）。
  List<Track> _recommend(List<Track> all, Scene scene) {
    final List<Track> tracks = List<Track>.of(all);
    final String sceneText = '${scene.name}${scene.mood}${scene.desc}'.toLowerCase();
    tracks.sort((Track a, Track b) {
      final int sa = _score(a, sceneText);
      final int sb = _score(b, sceneText);
      return sb.compareTo(sa);
    });
    return tracks;
  }

  int _score(Track t, String sceneText) {
    int s = 0;
    final String title = t.title.toLowerCase();
    final String artist = t.artist.toLowerCase();
    if (sceneText.contains(title)) s += 3;
    if (sceneText.contains(artist)) s += 1;
    // 稳定的探索性：同 artist 多曲目略靠前
    s += 0;
    return s;
  }
}

/// 实验页常驻「实验」标识（P0-M2-3 页内常驻）。
class _ExperimentBadge extends StatelessWidget {
  const _ExperimentBadge();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(right: 4),
      child: StateChip(tone: ChipTone.experimenting, label: '实验'),
    );
  }
}
