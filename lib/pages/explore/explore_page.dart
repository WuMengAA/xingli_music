import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/experiment.dart';
import '../../models/capability.dart';
import '../../models/scene.dart';
import '../../models/track_stats.dart';
import '../../pages/library/playlist_detail_page.dart';
import '../../pages/social/station_lobby_page.dart';
import '../../providers/content/capability_providers.dart';
import '../../providers/content/content_providers.dart';
import '../../providers/explore/experiment_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/session/session_providers.dart';
import '../../services/content/content_service.dart';
import '../../providers/shell/shell_providers.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/aggregate_search_sheet.dart';
import '../../core/terms/naming_dict.dart';
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
/// 视觉全部走设计系统：`PageScaffold` + `context.appColors` / `context.appText`
/// + `AppSpace` / `AppRadius`，靠留白、排版层级与原生控件（GestureDetector /
/// InkWell / ListTile）区分区块，不写死任何颜色字面量。
class ExplorePage extends ConsumerWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExperimentConsent consent = ref.watch(experimentConsentProvider);

    // —— 四种功能入口的跳转动作（局部函数声明，捕获 context / ref）——
    void openSearch() => unawaited(
          AggregateSearchSheet.show(
            context: context,
            tabs: const <String>[Terms.exploreTabTracks, Terms.exploreTabPlaylists, Terms.exploreTabUsers],
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
    // 电台房（转正）：从实验区提升为正式功能入口。
    void goStation() => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const StationLobbyPage()),
        );
    // 每日推荐 / 漫游 / 电台房 已移入下方「实验室」网格，不再在此单列。
    // 歌单 / 场景类卡片跳到对应 Tab，复用既有页面，不伪造数据。

    return PageScaffold(
      title: Terms.tabExplore,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm, vertical: AppSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // cl08：官方公告条（后端内容联动，relay_server 动态下发）。
            const _RemoteNoticeBar(),
            _SearchBar(onTap: openSearch),
            const SizedBox(height: AppSpace.md),
            // 精选大卡：读真实活跃场景（activeSceneProvider），点击回到主页场景卡。
            const _FeaturedCard(),
            const SizedBox(height: AppSpace.lg),
            _SectionLabel(Terms.sceneMusic),
            const SizedBox(height: AppSpace.md),
            // 场景音乐区：读真实场景列表（sceneOrderProvider），点击切换主页场景。
            const _SceneRow(),
            const SizedBox(height: AppSpace.lg),
            _SectionLabel(Terms.hotPlaylists),
            const SizedBox(height: AppSpace.md),
            // 热门歌单区：读真实歌单（playlistsProvider），点击进入歌单详情。
            const _PlaylistRowSection(),
            const SizedBox(height: AppSpace.lg),
            _SectionLabel(Terms.features),
            const SizedBox(height: AppSpace.md),
            _FunctionSection(
              onAggregate: openSearch,
              onRecommend: goRecommend,
              onCompanion: goCompanion,
              onWorld: goWorld,
              onStation: goStation,
            ),
            const SizedBox(height: AppSpace.lg),
            _SectionLabel(Terms.lab),
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

/// 顶部搜索栏（345×44，圆角 22，裸输入框外观）。点击打开聚合搜索弹层。
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    // cl04：iOS 分组卡 + Fluent Card 质感底，与页面内容分层。
    return Container(
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: <Widget>[
                Icon(Icons.search_rounded, size: 18, color: c.iconInactive),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(Terms.exploreSearchHint, style: context.appText.hint),
                ),
              ],
            ),
          ),
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
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
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
            ],
          ),
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
    final AppThemeColors c = context.appColors;
    // cl04：场景卡卡片化分层（bgSurface + 描边），按压走 InkWell 水波纹。
    return Container(
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
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
              ],
            ),
          ),
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
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: <Widget>[
                Icon(Icons.queue_music_rounded,
                    size: 18, color: context.appColors.iconInactive),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    Terms.playlistEmpty,
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
    // cl04：歌单行卡片化分层（iOS 分组卡 + Fluent Card 质感）。
    return Container(
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
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
        ),
      ),
    );
  }
}

/// 官方公告条（cl08：后端内容联动）。
///
/// 从 relay_server `/api/content/notices` 拉取最新公告展示；
/// 离线 / 后端不可达时自动隐藏（不打断本地使用）。
class _RemoteNoticeBar extends ConsumerWidget {
  const _RemoteNoticeBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    final AsyncValue<List<RemoteNotice>> notices =
        ref.watch(remoteNoticesProvider);
    return notices.maybeWhen(
      data: (List<RemoteNotice> list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final RemoteNotice n = list.first;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.accentSoft.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: c.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.campaign_rounded, size: 18, color: c.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(n.title, style: context.appText.trackName),
                      const SizedBox(height: 2),
                      Text(
                        n.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.appText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// 功能区：聚合搜索 / 智能推荐 / AI 陪伴 / 星璃世界（345×56，圆角 16）。
///
/// 收敛为核心 4 个高频入口；每日推荐 / 漫游 / 电台房 已下沉到下方「实验室」
/// 网格（数据驱动 `experimentsProvider`），避免功能区分裂在两个区块造成重复。
class _FunctionSection extends StatelessWidget {
  const _FunctionSection({
    required this.onAggregate,
    required this.onRecommend,
    required this.onCompanion,
    required this.onWorld,
    required this.onStation,
  });

  final VoidCallback onAggregate;
  final VoidCallback onRecommend;
  final VoidCallback onCompanion;
  final VoidCallback onWorld;
  final VoidCallback onStation;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Column(
      children: <Widget>[
        _FuncRow(
          title: Terms.aggregateSearch,
          subtitle: '网易云 / B站 / 本地 三源合一',
          onTap: onAggregate,
          trailing: Icon(Icons.search_rounded, size: AppSize.iconSm, color: c.iconInactive),
        ),
        const SizedBox(height: AppSpace.sm),
        _FuncRow(
          title: Terms.smartRecommend,
          subtitle: '外部音源优先 · 按类型筛选',
          onTap: onRecommend,
          trailing: Icon(Icons.auto_awesome_rounded, size: AppSize.iconSm, color: c.iconInactive),
        ),
        const SizedBox(height: AppSpace.sm),
        _FuncRow(
          title: Terms.aiCompanion,
          subtitle: '关键词触发 · 联动应用内资源',
          onTap: onCompanion,
          trailing: Icon(Icons.smart_toy_outlined, size: AppSize.iconSm, color: c.iconInactive),
        ),
        const SizedBox(height: AppSpace.sm),
        _FuncRow(
          title: Terms.starliteWorld,
          subtitle: '3D 体素世界 · 空间音效',
          onTap: onWorld,
          trailing: Icon(Icons.view_in_ar_rounded, size: AppSize.iconSm, color: c.iconInactive),
        ),
        const SizedBox(height: AppSpace.sm),
        _FuncRow(
          title: Terms.station,
          subtitle: '一起听 · 校园点歌 · 共享音乐',
          onTap: onStation,
          trailing: Icon(Icons.radio_rounded, size: AppSize.iconSm, color: c.iconInactive),
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
    // cl04：功能行卡片化分层（iOS Settings 分组卡 + Fluent Card 质感）。
    return Container(
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(
                left: 20, right: 16, top: 10, bottom: 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 实验区（数据驱动 `experimentsProvider`，按同意状态 + 能力开关逐项过滤）。
///
/// 未同意 → 全屏 [ConsentGate]；已同意 → 165×110 卡片网格（双列）。
class _ExperimentSection extends ConsumerWidget {
  const _ExperimentSection({required this.consent});
  final ExperimentConsent consent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ExperimentItem> experiments = ref.watch(experimentsProvider);
    final List<ExperimentItem> visible = experiments
        .where((ExperimentItem e) =>
            consent.isEnabled(e) && _capabilityAllows(ref, e.id))
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

/// 实验 id → 能力 id。未列入的实验保持原状，不受能力开关约束。
const Map<String, String> _experimentCapabilityIds = <String, String>{
  'netease_recommend': 'netease.recommend',
};

/// 该实验对应的能力是否允许展示。
///
/// 判定顺序刻意这样排，是为了服务端不可用时不让本机功能凭空消失：
/// 1. 用户显式关掉 → 一定隐藏。选配存在本地，不依赖服务端可达性。
/// 2. 清单里有这一项 → 以清单的 enabled / 是否 planned 为准。
/// 3. 清单里没有（离线且无缓存）→ **放行**。网易云推荐是客户端能力，
///    实现在端上，不该因为连不上服务端就把本机功能藏起来。
bool _capabilityAllows(WidgetRef ref, String experimentId) {
  final String? capabilityId = _experimentCapabilityIds[experimentId];
  if (capabilityId == null) return true;

  if (ref.watch(capabilitySelectionProvider).contains(capabilityId)) {
    return false;
  }
  for (final Capability c in ref.watch(capabilitiesProvider)) {
    if (c.id == capabilityId) return c.enabled && !c.isPlanned;
  }
  return true;
}

/// 单张实验卡（165×110，圆角 16）：标题 + 描述。点击进入对应实验页。
class _ExpCard extends StatelessWidget {
  const _ExpCard({required this.item});
  final ExperimentItem item;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final bool retired = item.status == ExperimentStatus.retired;

    return Opacity(
      opacity: retired ? 0.5 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: c.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: retired
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => item.builder()),
                    ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(item.name, style: context.appText.subtitle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
