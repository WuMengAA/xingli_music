import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/light_tokens.dart';
import '../../../providers/audio/equalizer_providers.dart';
import '../../../services/audio/eq_engine.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_chip.dart';

/// 实验 C · 音效均衡器（v2 M2 · P0-M2-3，Q4 已裁决）。
///
/// - 低 / 中 / 高三档滑块（dB，-6 ~ +6）；
/// - 4 组预设（平坦 / 低音增强 / 人声突出 / 高音清亮）；
/// - Android：经 [EqEngine] 真 EQ（`AndroidEqualizer`）；
/// - iOS / 桌面：模拟层（状态 + UI + 可选增益微调），页面诚实标注
///   「当前平台不支持真实 EQ」（A3 已裁决）。
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
                  engine.supported ? 'Android 真 EQ' : '模拟层（仅状态 + UI）',
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

              // 三档滑块
              Text('低频', style: AppTextStyles.body),
              _BandSlider(
                value: preset.low,
                onChanged: (double v) => _update(ref, preset.copyWith(low: v)),
              ),
              Text('中频', style: AppTextStyles.body),
              _BandSlider(
                value: preset.mid,
                onChanged: (double v) => _update(ref, preset.copyWith(mid: v)),
              ),
              Text('高频', style: AppTextStyles.body),
              _BandSlider(
                value: preset.high,
                onChanged: (double v) => _update(ref, preset.copyWith(high: v)),
              ),

              const SizedBox(height: AppSpace.md),

              // 4 组预设
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
                        if (enabled) {
                          applyEqPreset(ref, p);
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                '当前：${preset.name}  '
                '低 ${preset.low > 0 ? '+' : ''}${preset.low}dB · '
                '中 ${preset.mid > 0 ? '+' : ''}${preset.mid}dB · '
                '高 ${preset.high > 0 ? '+' : ''}${preset.high}dB',
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

/// 单档滑块（-6 ~ +6 dB）。
class _BandSlider extends StatelessWidget {
  const _BandSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Slider(
            value: value,
            min: -6,
            max: 6,
            divisions: 24,
            label: '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)} dB',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)} dB',
            style: AppTextStyles.caption,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
