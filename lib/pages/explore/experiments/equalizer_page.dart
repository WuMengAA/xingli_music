/// 音效均衡器页（I 批重构）：外壳页，主体复用 [EqualizerPanel]。
///
/// - Android：经 [EqEngine] 真 EQ（`AndroidEqualizer`）；
/// - Windows + media_kit：mpv `af=equalizer` 滤镜真 DSP；
/// - 其余：模拟层（状态 + UI），页面诚实标注。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_chip.dart';
import '../../../widgets/playback/equalizer_panel.dart';

class EqualizerPage extends ConsumerWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '音效均衡器',
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 4),
              child: StateChip(tone: ChipTone.experimenting, label: '实验'),
            ),
          ],
          body: const EqualizerPanel(),
        ),
      ),
    );
  }
}
