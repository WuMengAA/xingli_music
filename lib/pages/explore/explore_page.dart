import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/experiment.dart';
import '../../providers/explore/experiment_providers.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_chip.dart';
import 'consent_gate.dart';

/// 探索页 = 实验场所（v2 M2 重写）。
///
/// - 未同意：全屏 [ConsentGate]（方案 A）。
/// - 已同意：顶部说明条 + 实验列表容器（数据驱动 `experimentsProvider`）。
/// - 每项：图标 + 名称 + 简介 + [StateChip] 状态 + 进入按钮；
///   「已下线」置灰 + 禁入（P0-M2-4）。
class ExplorePage extends ConsumerWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExperimentConsent consent = ref.watch(experimentConsentProvider);

    return PageScaffold(
      title: '探索实验室',
      body: consent.agreed
          ? _ExperimentList(consent: consent)
          : const ConsentGate(),
    );
  }
}

/// 已同意后的实验列表。
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
        // 顶部说明条（P0-M2-2）
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
          decoration: BoxDecoration(
            // R16：说明条底色跟随主题
            color: context.appColors.accentSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.science_rounded, size: AppSize.iconSm, color: context.appColors.accent),
              SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  '这里是实验场所：功能可能不稳定，数据本地处理不上传。',
                  style: context.appText.caption,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Expanded(
          child: visible.isEmpty
              ? const _NoExperiments()
              : GridView.builder(
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
