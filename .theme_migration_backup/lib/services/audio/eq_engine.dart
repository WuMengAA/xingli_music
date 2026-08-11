/// ════════════════════════════════════════════════════════════════════════
/// EQ 引擎（R7/R8/R9 重构）
/// ════════════════════════════════════════════════════════════════════════
///
/// - 逻辑 10 段图形 EQ：31/62/125/250/500/1k/2k/4k/8k/16k Hz
/// - Android：映射到 `AndroidEqualizer` 设备实际频段（按中心频率就近映射）
/// - 其余平台：模拟层（仅状态 + UI，诚实标注）
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 10 段标准频率（Hz），供 UI 与映射使用。
const List<double> kEqFrequencies = <double>[
  31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
];

/// 单档增益范围（dB）。
///
/// R-EQ：默认不爆音。±12dB 极值在部分预设组合下会产生削波/震耳感，
/// 收紧到 **±6dB**（公认安全的图形 EQ 上限，Hi-Fi 常规范围），
/// 配合温和预设曲线（见 kEqPresets），避免"耳朵被震聋"。
const double kEqMinGain = -6;
const double kEqMaxGain = 6;

/// 一组 EQ 预设（10 段增益，单位 dB）。
@immutable
class EqPreset {
  const EqPreset({
    required this.id,
    required this.name,
    required this.gains,
  });

  final String id;
  final String name;

  /// 10 段增益（与 [kEqFrequencies] 一一对应）。
  final List<double> gains;

  /// 安全访问第 i 档（越界返回 0）。
  double gainAt(int i) =>
      (i >= 0 && i < gains.length) ? gains[i] : 0.0;

  EqPreset copyWith({String? id, String? name, List<double>? gains}) =>
      EqPreset(id: id ?? this.id, name: name ?? this.name, gains: gains ?? this.gains);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'gains': gains,
      };

  factory EqPreset.fromJson(Map<String, dynamic> json) => EqPreset(
        id: json['id'] as String? ?? 'flat',
        name: json['name'] as String? ?? '平坦',
        gains: (json['gains'] as List<dynamic>?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            List<double>.filled(kEqFrequencies.length, 0),
      );
}

/// 7 组预设表（R9 ≥6；R-EQ 校准：峰值 ≤ +4.5dB、谷值 ≥ -3dB，
/// 温和曲线避免削波/震耳；默认 flat 全 0 不爆音）。
const List<EqPreset> kEqPresets = <EqPreset>[
  EqPreset(id: 'flat', name: '平坦', gains: <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  EqPreset(
    id: 'bass',
    name: '低音增强',
    gains: <double>[4.5, 4, 3, 1.5, 0, -0.5, -1, -1.5, -1.5, -2],
  ),
  EqPreset(
    id: 'vocal',
    name: '人声突出',
    gains: <double>[-1.5, -1, 0, 1.5, 3, 4, 3, 1.5, 0, -0.5],
  ),
  EqPreset(
    id: 'treble',
    name: '高音清亮',
    gains: <double>[-2, -1.5, -1, 0, 0, 0.5, 1.5, 3, 4.5, 4.5],
  ),
  EqPreset(
    id: 'pop',
    name: '流行',
    gains: <double>[-1.5, -1, 0, 2, 3, 3.5, 2.5, 1, 0, -0.5],
  ),
  EqPreset(
    id: 'rock',
    name: '摇滚',
    gains: <double>[4, 3.5, 2.5, 1, 0, -0.5, 0, 1.5, 2.5, 3.5],
  ),
  EqPreset(
    id: 'classical',
    name: '古典',
    gains: <double>[3, 2.5, 1.5, 0, -0.5, -0.5, 0, 1, 2, 3],
  ),
];

/// EQ 引擎抽象。
abstract class EqEngine {
  /// 当前平台是否支持真实 EQ（Android true；其余 false）。
  bool get supported;

  /// 平台不支持时的说明文案。
  String get unsupportedNote;

  /// Android：应用真 EQ 到当前音频管线。
  Future<void> apply(EqPreset preset);

  /// 其余平台：仅记录状态（不做 DSP）。
  void applySimulation(EqPreset preset);
}

/// 模拟层（iOS / 桌面）。
class SimulatedEqEngine implements EqEngine {
  SimulatedEqEngine();

  @override
  bool get supported => false;

  @override
  String get unsupportedNote =>
      '当前平台不支持真实 EQ（仅 Android 支持）。已保存预设状态，'
      '可在 Android 设备上体验真实均衡器效果。';

  @override
  Future<void> apply(EqPreset preset) async {
    // 模拟层不做 DSP；状态由 equalizerProviders 的 eqPresetProvider 维护。
  }

  @override
  void applySimulation(EqPreset preset) {
    // 模拟层仅记录状态（外部 provider 已持有），此处无副作用。
  }
}

/// Android：真实 EQ（just_audio `AndroidEqualizer`）。
class AndroidEqEngine implements EqEngine {
  AndroidEqEngine(this._equalizer);

  final AndroidEqualizer _equalizer;

  @override
  bool get supported => !kIsWeb && Platform.isAndroid;

  @override
  String get unsupportedNote => '';

  /// 最近一次成功应用的预设（播放开始时补应用用）。
  EqPreset? _lastApplied;
  EqPreset? get lastApplied => _lastApplied;

  @override
  Future<void> apply(EqPreset preset) async {
    _lastApplied = preset;
    try {
      await _equalizer.setEnabled(true);
      final AndroidEqualizerParameters params = await _equalizer.parameters;
      final List<AndroidEqualizerBand> bands = params.bands;
      if (bands.isEmpty) return;

      // 10 段逻辑频段 → 设备实际频段就近映射。
      // 设备频段数量不定（常见 5 段），按中心频率最近原则分配。
      for (int i = 0; i < kEqFrequencies.length; i++) {
        final double target = preset.gainAt(i).clamp(kEqMinGain, kEqMaxGain);
        final AndroidEqualizerBand band = _nearestBand(bands, kEqFrequencies[i]);
        await band.setGain(target);
      }
    } catch (_) {
      // 音频会话未就绪（R-04）：静默，由播放开始补应用。
    }
  }

  /// 在设备频段中找中心频率最接近 [freqHz] 的档位。
  AndroidEqualizerBand _nearestBand(
    List<AndroidEqualizerBand> bands,
    double freqHz,
  ) {
    AndroidEqualizerBand best = bands.first;
    double bestDist = double.infinity;
    for (final AndroidEqualizerBand b in bands) {
      final double d = (b.centerFrequency - freqHz).abs();
      if (d < bestDist) {
        bestDist = d;
        best = b;
      }
    }
    return best;
  }

  @override
  void applySimulation(EqPreset preset) {
    // Android 走真 EQ，不需要模拟层。
  }
}
