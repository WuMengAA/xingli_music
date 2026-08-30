import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../models/scene.dart';
import '../../../models/track.dart';
import '../../../providers/audio/audio_providers.dart';
import '../../../providers/audio/playback_notifier.dart';
import '../../../providers/scene/scene_providers.dart';
import '../../../providers/settings/oobe_choice_providers.dart';
import '../../../services/content/local_semantic_random.dart';
import '../../../widgets/common/info_row.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_chip.dart';
import '../../../widgets/common/state_views.dart';
import '../../../widgets/notification/app_notify.dart';

/// 本地语义随机（T4）· 离线推荐。
///
/// 与服务端推荐（编辑精选）并存的**数据主权替代**：不依赖网络，纯本地
/// 计算。按当前场景情绪（mood → 语义词库）对曲库语义打分 + 随机抖动排序，
/// 每次「换一批」结果都不相同——语义相关但不重复。
class LocalSemanticRandomPage extends ConsumerStatefulWidget {
  const LocalSemanticRandomPage({super.key});

  @override
  ConsumerState<LocalSemanticRandomPage> createState() =>
      _LocalSemanticRandomPageState();
}

class _LocalSemanticRandomPageState
    extends ConsumerState<LocalSemanticRandomPage> {
  /// 换一批时递增：改变 widget 的 seed → 新的随机推荐结果。
  int _seed = 0;

  void _reshuffle() => setState(() => _seed++);

  @override
  Widget build(BuildContext context) {
    final Scene scene = ref.watch(activeSceneProvider);
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);

    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '语义随机',
          actions: const <Widget>[_ExperimentBadge()],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: <Widget>[
                    Text(
                      '当前场景：${scene.name}（${scene.mood}）',
                      style: context.appText.bodyMuted,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _reshuffle,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('换一批'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Expanded(
                child: library.when(
                  data: (List<Track> all) {
                    // cl17：OOBE 所选流派（≤3）并入语义词库——风格选择落地，
                    // 偏好流派命中曲目优先前排，未选流派时行为不变。
                    final List<String> genreWords =
                        ref.watch(genrePrefsProvider).toList(growable: false);
                    final List<Track> ranked = const LocalSemanticRandom()
                        .recommend(all, scene,
                            seed: Random(_seed),
                            extraKeywords: genreWords);
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
                              appNotify(context, msg);
                            }
                          },
                        );
                      },
                    );
                  },
                  loading: () => const LoadingView(),
                  error: (Object e, StackTrace st) => ErrorView(
                    message: '加载曲库失败，请稍后重试',
                    onRetry: () =>
                        ref.invalidate(effectiveMusicLibraryProvider),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 实验页常驻「实验」标识（与 recommend_page 一致）。
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