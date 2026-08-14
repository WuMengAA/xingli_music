import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/experiment.dart';
import '../../providers/explore/experiment_providers.dart';
import '../../providers/sources/netease_provider.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_chip.dart';
import '../../pages/voxel/voxel_main_menu_page.dart';
import '../sources/aggregate_search_page.dart';
import 'consent_gate.dart';
import 'experiments/companion_page.dart';
import 'experiments/recommend_page.dart';

/// 探索页 = 实验场所（v2 M2 重写）。
///
/// - 顶部常驻「功能」区（R26r21：列表形式——聚合搜索 / 智能推荐 / AI 陪伴 /
///   星璃世界，按序排列；2.5D 系列已删，音效并入 3D 世界）。
/// - 下方：未同意 → 全屏 [ConsentGate]；已同意 → 实验列表
///   （数据驱动 `experimentsProvider`，逐项启停过滤）。
class ExplorePage extends ConsumerWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExperimentConsent consent = ref.watch(experimentConsentProvider);

    // R26r21：整页单一滚动列表——说明条置顶 → 功能（4 行）→ 实验列表；
    // 功能区不再独占空间，整体随页面滚动，下方实验内容始终可达。
    return PageScaffold(
      title: '探索',
      body: ListView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm, vertical: AppSpace.sm),
        children: <Widget>[
          const _ExperimentNotice(),
          const SizedBox(height: AppSpace.md),
          const _FunctionSection(),
          const SizedBox(height: AppSpace.md),
          if (consent.agreed)
            _ExperimentList(consent: consent)
          else
            const Padding(
              padding: EdgeInsets.only(top: AppSpace.lg),
              child: ConsentGate(),
            ),
        ],
      ),
    );
  }
}

/// R26r21：顶部说明条（「这里是实验场所……」置顶）。
class _ExperimentNotice extends StatelessWidget {
  const _ExperimentNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
      decoration: BoxDecoration(
        color: context.appColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.science_rounded,
              size: AppSize.iconSm, color: context.appColors.accent),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              '这里是实验场所：功能可能不稳定，数据本地处理不上传。',
              style: context.appText.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// R26r21：功能模块入口（常驻，**列表形式**、纵向紧凑）。顺序：
/// 聚合搜索 → 智能推荐 → AI 陪伴 → 星璃世界（2.5D 已删）。
class _FunctionSection extends ConsumerWidget {
  const _FunctionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NeteaseAuthState netease = ref.watch(neteaseAuthProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('功能', style: context.appText.subtitle),
        const SizedBox(height: AppSpace.sm),
        _FuncTile(
          icon: Icons.travel_explore_rounded,
          title: '聚合搜索',
          subtitle: netease.isLoggedIn
              ? '网易云 · 已登录：${netease.account?.nickname ?? '网易云用户'}'
              : '网易云 · 未登录（进入可登录）',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AggregateSearchPage(),
            ),
          ),
        ),
        _FuncTile(
          icon: Icons.auto_awesome_rounded,
          title: '智能推荐',
          subtitle: '外部音源优先 · 按类型筛选',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const RecommendPage()),
          ),
        ),
        _FuncTile(
          icon: Icons.smart_toy_outlined,
          title: 'AI 陪伴',
          subtitle: '关键词触发 · 联动应用内资源',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CompanionPage()),
          ),
        ),
          _FuncTile(
            icon: Icons.view_in_ar_rounded,
            title: '星璃世界',
            subtitle: '3D 体素世界 · 空间音效',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                // H1r2：入口先到独立主菜单页（新的世界/读取存档/多人联机/游戏设置）。
                builder: (_) => const VoxelMainMenuPage(),
              ),
            ),
          ),
      ],
    );
  }
}

/// 功能行（列表形式：紧凑行 = 图标 + 标题 + 副题 + 箭头，纵向高度小）。
class _FuncTile extends StatelessWidget {
  const _FuncTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: context.appColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.appColors.border),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(icon,
                    size: AppSize.iconSm, color: context.appColors.accent),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: context.appText.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: context.appText.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: AppSize.iconSm,
                    color: context.appColors.iconInactive),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 已同意后的实验列表（R26r21：说明条已上移置顶，这里只渲染网格、随外层滚动）。
class _ExperimentList extends ConsumerWidget {
  const _ExperimentList({required this.consent});

  final ExperimentConsent consent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ExperimentItem> experiments = ref.watch(experimentsProvider);
    // 逐项启停过滤（P1-M2-5）
    final List<ExperimentItem> visible = experiments
        .where((ExperimentItem e) => consent.isEnabled(e))
        .toList();

    final double width = MediaQuery.sizeOf(context).width;
    final bool landscape = width >= AppSize.landscapeBreakpoint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('实验', style: context.appText.subtitle),
        const SizedBox(height: AppSpace.sm),
        if (visible.isEmpty)
          const _NoExperiments()
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: landscape ? 320 : 280,
              mainAxisSpacing: AppSpace.gridRowGap,
              crossAxisSpacing: AppSpace.md,
              childAspectRatio: 1.5,
            ),
            itemCount: visible.length,
            itemBuilder: (BuildContext context, int i) {
              final ExperimentItem e = visible[i];
              return _ExperimentCard(item: e);
            },
          ),
      ],
    );
  }
}

/// 单张实验卡。
class _ExperimentCard extends ConsumerWidget {
  const _ExperimentCard({required this.item});

  final ExperimentItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool retired = item.status == ExperimentStatus.retired;

    return Opacity(
      opacity: retired ? 0.5 : 1.0,
      child: Material(
        // R16：实验卡底色跟随主题
        color: context.appColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: retired
              ? null // 已下线禁入（P0-M2-4）
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => item.builder()),
                  ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.appColors.border),
            ),
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(item.icon,
                        size: AppSize.icon,
                        color: retired
                            ? context.appColors.iconInactive
                            : context.appColors.accent),
                    const Spacer(),
                    StateChip(
                      tone: _toneOf(item.status),
                      label: item.statusLabel,
                    ),
                  ],
                ),
                const Spacer(),
                Text(item.name, style: context.appText.subtitle),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: context.appText.artist,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  retired ? '已下线，暂不可进入' : '点击进入',
                  style: context.appText.caption.copyWith(
                    color: retired
                        ? context.appColors.textTertiary
                        : context.appColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ChipTone _toneOf(ExperimentStatus s) => switch (s) {
        ExperimentStatus.experimenting => ChipTone.experimenting,
        ExperimentStatus.stable => ChipTone.stable,
        ExperimentStatus.retired => ChipTone.retired,
      };
}

class _NoExperiments extends StatelessWidget {
  const _NoExperiments();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '所有实验均已停用。\n可到设置 → ${Terms.experiment} 中重新启用。',
        style: context.appText.bodyMuted,
        textAlign: TextAlign.center,
      ),
    );
  }
}
