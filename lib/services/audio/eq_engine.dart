import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// EQ 预设 id（Q4 已裁决：3 档 + 4 组预设）。
enum EqPresetId { flat, bass, vocal, treble }

/// 一组 EQ 预设（低频 / 中频 / 高频，单位 dB）。
///
/// 架构 §3.2.4：默认 `flat(0,0,0)` / `bass(+6,0,-3)` / `vocal(-2,+4,-1)`
/// / `treble(-3,0,+6)`。
@immutable
class EqPreset {
  const EqPreset({
    required this.id,
    required this.name,
    required this.low,
    required this.mid,
    required this.high,
  });

  final String id;
  final String name;
  final double low;
  final double mid;
  final double high;

  EqPreset copyWith({double? low, double? mid, double? high}) => EqPreset(
        id: id,
        name: name,
        low: low ?? this.low,
        mid: mid ?? this.mid,
        high: high ?? this.high,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'low': low,
        'mid': mid,
        'high': high,
      };

  factory EqPreset.fromJson(Map<String, dynamic> json) => EqPreset(
        id: json['id'] as String? ?? 'flat',
        name: json['name'] as String? ?? '平坦',
        low: (json['low'] as num?)?.toDouble() ?? 0,
        mid: (json['mid'] as num?)?.toDouble() ?? 0,
        high: (json['high'] as num?)?.toDouble() ?? 0,
      );
}

/// 4 组预设表（Q4 落盘）。
const List<EqPreset> kEqPresets = <EqPreset>[
  EqPreset(id: 'flat', name: '平坦', low: 0, mid: 0, high: 0),
  EqPreset(id: 'bass', name: '低音增强', low: 6, mid: 0, high: -3),
  EqPreset(id: 'vocal', name: '人声突出', low: -2, mid: 4, high: -1),
  EqPreset(id: 'treble', name: '高音清亮', low: -3, mid: 0, high: 6),
];

/// EQ 引擎抽象（Q4 落盘 / A3 已裁决）。
///
/// - Android：`supported == true`，走 just_audio `AndroidEqualizer` 真 EQ
///   （需以 `AudioPipeline(androidAudioEffects: [eq])` 装配到播放器）。
/// - iOS / 桌面：`supported == false`，仅状态 + UI + 可选整体增益微调，
///   **不做 DSP**，页面诚实标注「当前平台不支持真实 EQ」。
abstract class EqEngine {
  /// 当前平台是否支持真实 EQ（Android true；其余 false）。
  bool get supported;

  /// 平台不支持时的说明文案。
  String get unsupportedNote;

  /// Android：应用真 EQ 到当前音频管线。
  ///
  /// 注意 R-04：`AndroidEqualizer` 需要播放中才能访问音频会话；
  /// 无播放时仅记录状态（由 [equalizerProviders] 在播放开始时补应用）。
  Future<void> apply(EqPreset preset);

  /// 其余平台：仅记录状态 + 可选整体增益微调（不做 DSP）。
  void applySimulation(EqPreset preset);
}

/// 模拟层（iOS / 桌面）。
///
/// 诚实标注：当前平台不支持真实 EQ。仅维护状态供 UI 展示，
/// 并提供可选的整体音乐增益微调（轻量，非 DSP）。
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
      // 三档映射：低频 = 第 0 带，高频 = 最后一带，中频 = 中间带。
      final double midGain = preset.mid;
      for (int i = 0; i < bands.length; i++) {
        final double target = _bandTarget(i, bands.length, preset);
        await bands[i].setGain(target);
      }
      // 保留 mid 供中间带（若只有 1~2 带则全部按低/高近似）。
      if (midGain != 0 && bands.length > 1 && bands.length < 3) {
        // 双带设备：中频折中到低/高之间
        await bands[0].setGain((preset.low + midGain) / 2);
        await bands[bands.length - 1].setGain((preset.high + midGain) / 2);
      }
    } catch (_) {
      // 音频会话未就绪（R-04）：静默，由播放开始补应用。
    }
  }

  double _bandTarget(int i, int count, EqPreset p) {
    if (count <= 1) return (p.low + p.mid + p.high) / 3;
    if (i == 0) return p.low;
    if (i == count - 1) return p.high;
    return p.mid;
  }

  @override
  void applySimulation(EqPreset preset) {
    // Android 走真 EQ，不需要模拟层。
  }
}
