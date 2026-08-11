import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/light_tokens.dart';
import '../../../providers/audio/equalizer_providers.dart';
import '../../../services/audio/eq_engine.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_chip.dart';

/// 实验 C · 音效均衡器（v2 重构 · R7/R8/R9）。
///
/// - 10 段图形 EQ（31/62/125/250/500/1k/2k/4k/8k/16k Hz，±12dB）；
/// - 7 组预设（平坦/低音增强/人声突出/高音清亮/流行/摇滚/古典）；
/// - Android：经 [EqEngine] 真 EQ（`AndroidEqualizer`）；
/// - iOS / 桌面：模拟层（状态 + UI），页面诚实标注。
class EqualizerPage extends ConsumerWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EqEngine engine = ref.watch(eqEngineProvider);
    final EqPreset preset = ref.watch(eqPresetProvider);
    final bool enabled = ref.watch(eqEnabledProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '音效均衡器',
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 4),
              child: StateChip(tone: ChipTone.experimenting, label: '实验'),
            ),
          ],
          body: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              // 总开关
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用均衡器', style: AppTextStyles.body),
                subtitle: Text(
                  engine.supported ? 'Android 真 EQ · 10 段' : '模拟层（仅状态 + UI）',
                  style: AppTextStyles.artist,
                ),
                value: enabled,
                onChanged: (bool v) {
                  ref.read(eqEnabledProvider.notifier).state = v;
                  if (v) {
                    applyEqPreset(ref, ref.read(eqPresetProvider));
                  }
                },
              ),
              const SizedBox(height: AppSpace.md),

              // 平台标注（诚实标注）
              if (!engine.supported)
                Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    engine.unsupportedNote,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),

              const SizedBox(height: AppSpace.md),

              // 10 段图形 EQ
              Text('10 段均衡（Hz）', style: AppTextStyles.body),
              const SizedBox(height: AppSpace.xs),
              SizedBox(
                height: 220,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < kEqFrequencies.length; i++)
                      Expanded(
                        child: _BandSlider(
                          freq: kEqFrequencies[i],
                          value: preset.gainAt(i),
                          onChanged: (double v) {
                            final List<double> gains = List<double>.from(
                              preset.gains.length == kEqFrequencies.length
                                  ? preset.gains
                                  : List<double>.filled(
                                      kEqFrequencies.length, 0),
                            );
                            gains[i] = v;
                            final EqPreset next = EqPreset(
                              id: 'custom',
                              name: '自定义',
                              gains: gains,
                            );
                            ref.read(eqCustomGainsProvider.notifier).state = gains;
                            _update(ref, next);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),

              // 预设
              Text('预设', style: AppTextStyles.body),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                children: <Widget>[
                  for (final EqPreset p in kEqPresets)
                    ChoiceChip(
                      label: Text(p.name),
                      selected: p.id == preset.id,
                      onSelected: (_) {
                        ref.read(eqPresetProvider.notifier).state = p;
                        ref.read(eqCustomGainsProvider.notifier).state =
                            List<double>.from(p.gains);
                        if (enabled) {
                          applyEqPreset(ref, p);
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                '当前：${preset.name} · '
                '62Hz ${preset.gainAt(1) > 0 ? '+' : ''}${preset.gainAt(1).toStringAsFixed(0)}dB · '
                '250Hz ${preset.gainAt(3) > 0 ? '+' : ''}${preset.gainAt(3).toStringAsFixed(0)}dB · '
                '1kHz ${preset.gainAt(5) > 0 ? '+' : ''}${preset.gainAt(5).toStringAsFixed(0)}dB · '
                '2kHz ${preset.gainAt(6) > 0 ? '+' : ''}${preset.gainAt(6).toStringAsFixed(0)}dB · '
                '8kHz ${preset.gainAt(8) > 0 ? '+' : ''}${preset.gainAt(8).toStringAsFixed(0)}dB',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _update(WidgetRef ref, EqPreset next) {
    if (ref.read(eqEnabledProvider)) {
      applyEqPreset(ref, next);
    } else {
      ref.read(eqPresetProvider.notifier).state = next;
    }
  }
}

/// 单档垂直滑块（±12 dB），频率标签在底部。
class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.freq,
    required this.value,
    required this.onChanged,
  });

  final double freq;
  final double value;
  final ValueChanged<double> onChanged;

  String get _label {
    if (freq >= 1000) return '${(freq / 1000).toStringAsFixed(0)}k';
    return freq.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: value.clamp(kEqMinGain, kEqMaxGain),
              min: kEqMinGain,
              max: kEqMaxGain,
              // ±6dB → 12 档（每档 1dB）
              divisions: 12,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          height: 18,
          child: Text(_label, style: AppTextStyles.caption),
        ),
      ],
    );
  }
}
