import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/light_tokens.dart';
import '../../../models/scene.dart';
import '../../../providers/audio/audio_providers.dart';
import '../../../providers/scene/scene_providers.dart';
import '../../../providers/session/session_providers.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_chip.dart';

/// 实验 E · 心情分析（v2 M2 · P0-M2-3）。
///
/// 问卷（5 题心情状态选择）→ 计算情绪坐标（valence / energy）→
/// 匹配最接近的内置场景并切换（联动音景）。
/// 隐私：问卷数据仅本地计算，不上传（P1-M2-6）。
class MoodAnalysisPage extends ConsumerStatefulWidget {
  const MoodAnalysisPage({super.key});

  @override
  ConsumerState<MoodAnalysisPage> createState() => _MoodAnalysisPageState();
}

class _MoodAnalysisPageState extends ConsumerState<MoodAnalysisPage> {
  final List<int> _answers = <int>[2, 2, 2, 2, 2];

  static const List<String> _questions = <String>[
    '此刻你的心情是？',
    '现在的精力水平？',
    '你想听什么样的氛围？',
    '今天更想安静还是热闹？',
    '你的情绪更偏向？',
  ];

  static const List<List<String>> _options = <List<String>>[
    <String>['低落', '平静', '愉悦', '兴奋'],
    <String>['疲惫', '一般', '有精神', '充沛'],
    <String>['空灵', '自然', '温暖', '明亮'],
    <String>['安静', '轻柔', '适中', '热闹'],
    <String>['偏消极', '中性', '偏积极', '非常积极'],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '心情分析',
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 4),
              child: StateChip(tone: ChipTone.stable, label: '实验'),
            ),
          ],
          body: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              const Text(
                '隐私说明：问卷结果仅在本机计算，用于匹配场景，不会上传。',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpace.md),
              for (int i = 0; i < _questions.length; i++) _questionBlock(i),
              const SizedBox(height: AppSpace.lg),
              FilledButton.icon(
                onPressed: _analyzeAndSwitch,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('分析并匹配场景'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionBlock(int i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${i + 1}. ${_questions[i]}', style: AppTextStyles.body),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            children: <Widget>[
              for (int j = 0; j < _options[i].length; j++)
                ChoiceChip(
                  label: Text(_options[i][j]),
                  selected: _answers[i] == j,
                  onSelected: (_) =>
                      setState(() => _answers[i] = j),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeAndSwitch() async {
    // 5 题 0~3 → valence / energy（0~1）
    // valence 与 energy 相关但不相同：奇数题偏 valence，偶数题偏 energy
    final double valence =
        (_answers[0] + _answers[2] + _answers[4]) / 9.0;
    final double energy =
        (_answers[1] + _answers[3]) / 6.0;

    final List<Scene> scenes = ref.read(sceneOrderProvider);
    if (scenes.isEmpty) return;
    Scene? best;
    double bestDist = double.infinity;
    for (final Scene s in scenes) {
      final double d = (s.valence - valence).abs() + (s.energy - energy).abs();
      if (d < bestDist) {
        bestDist = d;
        best = s;
      }
    }
    if (best == null) return;

    final int index = scenes.indexOf(best);
    ref.read(currentSceneIndexProvider.notifier).state = index;
    await ref.read(audioServiceProvider).switchSoundscape(best);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('根据你的心情，切换到场景「${best.name}」'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
