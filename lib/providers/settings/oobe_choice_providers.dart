/// ════════════════════════════════════════════════════════════════════════
/// OOBE 选择 / 询问类 Provider（cl75）
/// ════════════════════════════════════════════════════════════════════════
///
/// 初始化流程「选择 / 询问」两步收集的用户偏好，全部即时写入 provider，
/// 并由 [settingsSyncProvider] 持久化到 [SettingsRepository]，冷启动由
/// [restoreSettings] 灌回。与现有 themeMode / themeSkin / graphicsQuality
/// 等 provider 同一套「运行期写回」机制。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 音频质量偏好（0=高品 · 1=标准 · 2=省流；默认 1=标准）。
///
/// 对应网易云 `level`（standard/higher/exhigh/lossless），源层可按此选档。
final audioQualityProvider = StateProvider<int>((ref) => 1);

/// 音频质量档标签。
const Map<int, String> kAudioQualityLabels = <int, String>{
  0: '高品',
  1: '标准',
  2: '省流',
};

/// 是否允许匿名体验改进（默认 false）。
final analyticsConsentProvider = StateProvider<bool>((ref) => false);

/// 主要聆听场景（多选，[kListenSourceOptions] 的子集）。
final listenSourcesProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

/// 可选聆听场景。
const List<String> kListenSourceOptions = <String>[
  '睡眠',
  '专注',
  '学习',
  '放松',
  '运动',
  '游戏',
];
