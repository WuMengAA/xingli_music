import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../models/companion_models.dart';
import '../../../providers/companion/companion_providers.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_chip.dart';
import '../../../widgets/companion/companion_bubble.dart';

/// 实验 · AI 陪伴（Phase 1）。
///
/// 入口说明 + 文字气泡组件。陌生人设定：
/// - 第一次必须由用户发起（[CompanionPersona.placeholderBody]）；
/// - 全程离线、模板生成（[CompanionPersona.privacyNote]）；
/// - R1~R3 安全边界（[CompanionPersona.safetyRules]）。
class CompanionPage extends ConsumerWidget {
  const CompanionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompanionSession session = ref.watch(companionStateProvider);

    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: 'AI 陪伴（实验）',
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 4),
              child: StateChip(tone: ChipTone.experimenting, label: '实验'),
            ),
          ],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 说明区
              Text(
                CompanionPersona.tagline,
                style: context.appText.subtitle,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                CompanionPersona.privacyNote,
                style: context.appText.caption,
              ),
              if (session.firstContactMade) ...<Widget>[
                const SizedBox(height: AppSpace.xs),
                Text(
                  CompanionPersona.awakeNote,
                  style: context.appText.caption,
                ),
              ],
              const SizedBox(height: AppSpace.md),

              // 文字气泡
              Expanded(
                child: CompanionBubble(),
              ),

              // 底部操作 + 边界说明
              const SizedBox(height: AppSpace.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '边界：${CompanionPersona.safetyRules.join(' ')}',
                      style: context.appText.caption,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(companionStateProvider.notifier).reset(),
                    child: const Text('重置'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
