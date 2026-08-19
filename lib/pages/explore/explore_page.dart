import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/experiment.dart';
import '../../models/scene.dart';
import '../../models/track_stats.dart';
import '../../pages/library/playlist_detail_page.dart';
import '../../providers/explore/experiment_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/session/session_providers.dart';
import '../../providers/shell/shell_providers.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/aggregate_search_sheet.dart';
import '../../widgets/liquid_glass.dart';
import 'consent_gate.dart';
import 'experiments/companion_page.dart';
import 'experiments/recommend_page.dart';

/// 探索页（v2 M2 重写，按画布「Screen · 探索」3:238 重建）。
///
/// 结构（自上而下，与画布一致）：
///   1. 搜索栏（点击打开聚合搜索弹层）
///   2. 精选大卡（今日场景精选）
///   3. 场景音乐区 + 2 张场景卡
///   4. 热门歌单区 + 2 行歌单
///   5. 实验场所说明条
///   6. 功能区（聚合搜索 / 智能推荐 / AI 陪伴 / 星璃世界）
///   7. 实验区（数据驱动 `experimentsProvider`，按 165×110 卡片网格渲染）
///
/// 视觉全部走设计系统：`PageScaffold` + `LiquidGlass` + `context.appColors`
/// / `context.appText` + `AppSpace` / `AppRadius`，不写死任何颜色字面量。
class ExplorePage extends ConsumerWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExperimentConsent consent = ref.watch(experimentConsentProvider);

    // —— 四种功能入口的跳转动作（局部函数声明，捕获 context / ref）——
    void openSearch() => unawaited(
          AggregateSearchSheet.show(
            context: context,
            tabs: const <String>['歌曲', '歌单', '用户'],
          ),
        );
    void goRecommend() => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RecommendPage()),
        );
    void goCompanion() => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CompanionPage()),
        );
    // 星璃世界走 Shell Tab 切换（IndexedStack 唯一真源）。
    void goWorld() => setShellPage(ref, ShellPage.world);
    // 歌单 / 场景类卡片跳到对应 Tab，复用既有页面，不伪造数据。

    return PageScaffold(
      title: '探索',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm, vertical: AppSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SearchBar(onTap: openSearch),
            const SizedBox(height: AppSpace.md),
            // 精选大卡：读真实活跃场景（activeSceneProvider），点击回到主页场景卡。
            const _FeaturedCard(),
            const SizedBox(height: AppSpace.lg),
            _SectionLabel('场景音乐'),
            const SizedBox(height: AppSpace.md),
            // 场景音乐区：读真实场景列表（sceneOrderProvider），点击切换主页场景。
            const _SceneRow(),
            const SizedBox(height: AppSpace.lg),
            _SectionLabel('热门歌单'),
            const SizedBox(height: AppSpace.md),
            // 热门歌单区：读真实歌单（playlistsProvider），点击进入歌单详情。
            const _PlaylistRowSection(),
            const SizedBox(height: AppSpace.lg),
            _NoticeBar(),
            const SizedBox(height: AppSpace.lg),
            _SectionLabel('功能'),
            const SizedBox(height: AppSpace.md),
            _FunctionSection(
              onAggregate: openSearch,
              onRecommend: goRecommend,
              onCompanion: goCompanion,
              onWorld: goWorld,
            ),
            const SizedBox(height: AppSpace.lg),
            _SectionLabel('实验'),
            const SizedBox(height: AppSpace.md),
            _ExperimentSection(consent: consent),
            const SizedBox(height: AppSpace.md),
          ],
        ),
      ),
    );
  }
}

/// 区块小标题（画布 section-label，15/w600）。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
    );
  }
}

/// 顶部搜索栏（345×44，圆角 22，毛玻璃）。点击打开聚合搜索弹层。
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlass(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: <Widget>[
            Icon(Icons.search_rounded, size: 18, color: c.iconInactive),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text('探索音乐、场景与歌单', style: context.appText.hint),
            ),
          ],
        ),
      ),
    );
  }
}

/// 精选大卡（345×160，圆角 20）。画布为紫色渐变 hero，用主题强调色派生，
/// 不写死品牌色。**读真实活跃场景**（[activeSceneProvider]）——展示当前
/// 场景名 + 音景描述，点击回主页场景卡（真实场景内容），不再用假文案。
class _FeaturedCard extends ConsumerWidget {
  const _FeaturedCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    final Scene scene = ref.watch(activeSceneProvider);
    return GestureDetector(
      onTap: () => setShellPage(ref, ShellPage.home),
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[c.accent, c.accentSoft],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Spacer(),
            Text(
              scene.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ).copyWith(color: c.onAccent),
            ),
            const SizedBox(height: 4),
            Text(
              scene.soundscape.isNotEmpty
                  ? '${scene.soundscape} · 点击进入'
                  : '点击进入主页场景',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ).copyWith(color: c.onAccent.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 场景音乐区：读真实场景列表（[sceneOrderProvider]），取前 2 个场景渲染
/// 165×150 场景卡。点击 → 切换主页当前场景并回到主页（真实场景卡）。
class _SceneRow extends ConsumerWidget {
  const _SceneRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Scene> scenes = ref.watch(sceneOrderProvider);
    if (scenes.isEmpty) return const SizedBox.shrink();
    final List<Scene> shown = scenes.take(2).toList();
    return Row(
      children: <Widget>[
        for (int i = 0; i < shown.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AppSpace.md),
          Expanded(
            child: _SceneCard(
              scene: shown[i],
              onTap: () {
                // 切换主页当前场景到该场景，并回到主页场景卡。
                final int idx = scenes.indexOf(shown[i]);
                ref.read(currentSceneIndexProvider.notifier).state = idx;
                setShellPage(ref, ShellPage.home);
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// 单张场景卡：真实 [Scene] 数据（名称 + 音景描述 + 场景图标）。
class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.scene, required this.onTap});

  final Scene scene;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlass(
        radius: 18,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: scene.visual.gradientColors,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  scene.visual.glyph,
                  style: TextStyle(
                    fontSize: 28,
                    color: scene.visual.accent.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(scene.name, style: context.appText.subtitle),
            const SizedBox(height: 2),
            Text(
              scene.soundscape.isNotEmpty ? scene.soundscape : scene.mood,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.appText.artist,
            ),
          ],
        ),
      ),
    );
  }
}

/// 热门歌单区：读真实歌单（[playlistsProvider]），取前 2 个渲染 345×64 行。
/// 点击 → 打开对应 [PlaylistDetailPage]。空歌单时显示空态引导（不再放假数据）。
class _PlaylistRowSection extends ConsumerWidget {
  const _PlaylistRowSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Playlist>> playlists = ref.watch(playlistsProvider);
    return playlists.when(
      loading: () => const SizedBox(
        height: 64,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (Object e, StackTrace st) => const SizedBox.shrink(),
      data: (List<Playlist> list) {
        if (list.isEmpty) {
          return LiquidGlass(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: <Widget>[
                Icon(Icons.queue_music_rounded,
                    size: 18, color: context.appColors.iconInactive),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    '还没有歌单，去曲库收藏歌曲后会自动生成',
                    style: context.appText.caption,
                  ),
                ),
              ],
            ),
          );
        }
        final List<Playlist> shown = list.take(2).toList();
        return Column(
          children: <Widget>[
            for (int i = 0; i < shown.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpace.sm),
              _PlaylistRow(
                playlist: shown[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PlaylistDetailPage(playlistId: shown[i].id ?? -1),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 歌单行（345×64，圆角 16）：封面 + 标题 + 副信息 + 箭头（真实歌单数据）。
class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, required this.onTap});

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlass(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: c.bgPlaceholder,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.queue_music_rounded,
                  size: 24, color: c.iconInactive),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(playlist.name, style: context.appText.trackName),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.trackCount} 首',
                    style: context.appText.artist,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: AppSize.iconSm, color: c.iconInactive),
          ],
        ),
      ),
    );
  }
}

/// 实验场所说明条（345×48，圆角 12）。画布为浅紫提示条。
class _NoticeBar extends StatelessWidget {
  const _NoticeBar();

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.science_rounded, size: 18, color: c.accent),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              '实验场所 · 功能可能不稳定，数据本地处理不上传',
              style: context.appText.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// 功能区：聚合搜索 / 智能推荐 / AI 陪伴 / 星璃世界（345×56，圆角 16）。
class _FunctionSection extends StatelessWidget {
  const _FunctionSection({
    required this.onAggregate,
    required this.onRecommend,
    required this.onCompanion,
    required this.onWorld,
  });

  final VoidCallback onAggregate;
  final VoidCallback onRecommend;
  final VoidCallback onCompanion;
  final VoidCallback onWorld;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Column(
      children: <Widget>[
        _FuncRow(
          title: '聚合搜索',
          subtitle: '网易云 / B站 / 本地 三源合一',
          onTap: onAggregate,
          trailing: Icon(Icons.search_rounded, size: AppSize.iconSm, color: c.iconInactive),
        ),
        const SizedBox(height: AppSpace.sm),
        _FuncRow(
          title: '智能推荐',
          subtitle: '外部音源优先 · 按类型筛选',
          onTap: onRecommend,
          trailing: Icon(Icons.auto_awesome_rounded, size: AppSize.iconSm, color: c.iconInactive),
        ),
        const SizedBox(height: AppSpace.sm),
        _FuncRow(
          title: 'AI 陪伴',
          subtitle: '关键词触发 · 联动应用内资源',
          onTap: onCompanion,
          trailing: Icon(Icons.smart_toy_outlined, size: AppSize.iconSm, color: c.iconInactive),
        ),
        const SizedBox(height: AppSpace.sm),
        _FuncRow(
          title: '星璃世界',
          subtitle: '3D 体素世界 · 空间音效',
          onTap: onWorld,
          trailing: Icon(Icons.view_in_ar_rounded, size: AppSize.iconSm, color: c.iconInactive),
        ),
      ],
    );
  }
}

/// 功能行（列表形式：标题 + 副题 + 尾部图标，纵向紧凑）。
class _FuncRow extends StatelessWidget {
  const _FuncRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlass(
        radius: 16,
        padding: const EdgeInsets.only(
            left: 20, right: 16, top: 10, bottom: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// 实验区（数据驱动 `experimentsProvider`，按同意状态逐项过滤）。
///
/// 未同意 → 全屏 [ConsentGate]；已同意 → 165×110 卡片网格（双列）。
class _ExperimentSection extends ConsumerWidget {
  const _ExperimentSection({required this.consent});
  final ExperimentConsent consent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ExperimentItem> experiments = ref.watch(experimentsProvider);
    final List<ExperimentItem> visible = experiments
        .where((ExperimentItem e) => consent.isEnabled(e))
        .toList();

    if (!consent.agreed) {
      return const ConsentGate();
    }
    if (visible.isEmpty) {
      return Text('所有实验均已停用。', style: context.appText.bodyMuted);
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 165 / 110,
      crossAxisSpacing: AppSpace.md,
      mainAxisSpacing: AppSpace.md,
      children: visible.map((ExperimentItem e) => _ExpCard(item: e)).toList(),
    );
  }
}

/// 单张实验卡（165×110，圆角 16）：标题 + 描述。点击进入对应实验页。
class _ExpCard extends StatelessWidget {
  const _ExpCard({required this.item});
  final ExperimentItem item;

  @override
  Widget build(BuildContext context) {
    final bool retired = item.status == ExperimentStatus.retired;

    return Opacity(
      opacity: retired ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: retired
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => item.builder()),
                ),
        child: LiquidGlass(
          radius: 16,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(item.name, style: context.appText.subtitle),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  item.description,
                  style: context.appText.artist,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
