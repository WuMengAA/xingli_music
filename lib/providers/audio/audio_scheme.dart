/// ════════════════════════════════════════════════════════════════════
/// 音频通道方案（R26skel-b5：声音分类 + 设备自适应）
/// ════════════════════════════════════════════════════════════════════
///
/// 声音分五类（每类独立音量 + 独立混音预算）：
///   - 主音量（Master）：全局整体音量，默认 50%；
///   - 音乐（Music）：流媒体 / 本地曲目，默认 50%，**最多 2 音轨 · 4 声道**；
///   - 背景（Background）：世界内背景音乐 / 背景声（音景），默认 25%，
///     **最多 2 声轨 · 2 声道**；
///   - 音效（SFX）：世界内音效 / 按钮音效 / 提示音，默认 50%，
///     **最多 4 声轨 · 8 声道**；
///   - 白噪音（WhiteNoise）：局部（场景）25% / 全局 10%，唯一场景白噪音，
///     **最多 8 声轨 · 4 声道**。
///
/// [channelSchemeProvider] 按「自动检测的当前设备信息」选取最佳方案：
/// 桌面端给满预算，移动端砍声道（省功耗/兼容弱解码），手表/超窄屏再砍
/// 音轨数。设置页展示当前方案，可随时查看。
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

/// 一个声音分类的混音预算（最多音轨数 / 最多声道数）。
class ChannelBudget {
  const ChannelBudget({
    required this.id,
    required this.label,
    required this.maxTracks,
    required this.maxChannels,
  });

  final String id;
  final String label;

  /// 最多同时播放的音轨数。
  final int maxTracks;

  /// 最多声道数（立体声=2，四声道=4，八声道=8）。
  final int maxChannels;
}

/// 一套完整通道方案（五类的预算）。
class ChannelScheme {
  const ChannelScheme({
    required this.label,
    required this.music,
    required this.background,
    required this.sfx,
    required this.whiteNoise,
  });

  final String label;
  final ChannelBudget music;
  final ChannelBudget background;
  final ChannelBudget sfx;
  final ChannelBudget whiteNoise;

  List<ChannelBudget> get all =>
      <ChannelBudget>[music, background, sfx, whiteNoise];
}

/// 设备类别（自动检测）。
enum AudioDeviceClass {
  desktop('桌面端'),
  mobile('移动端'),
  compact('紧凑设备（手表/窄屏）');

  const AudioDeviceClass(this.label);

  final String label;
}

/// 检测当前设备类别。
///
/// 规则：Web 按视口宽度；桌面三平台 → desktop；Android/iOS → mobile；
/// mobile 且视口过窄（< 480 逻辑像素，如手表）→ compact。
AudioDeviceClass detectAudioDeviceClass({double? webViewportWidth}) {
  if (kIsWeb) {
    final double? w = webViewportWidth;
    if (w != null && w < 480) return AudioDeviceClass.compact;
    return AudioDeviceClass.desktop;
  }
  try {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return AudioDeviceClass.desktop;
    }
  } catch (_) {
    // 非 IO 平台（web 已在上方处理）→ 按 desktop 兜底。
    return AudioDeviceClass.desktop;
  }
  return AudioDeviceClass.mobile;
}

/// 按设备类别给出最佳通道方案。
ChannelScheme schemeFor(AudioDeviceClass cls) => switch (cls) {
      AudioDeviceClass.desktop => const ChannelScheme(
          label: '桌面端 · 满预算',
          music: ChannelBudget(id: 'music', label: '音乐', maxTracks: 2, maxChannels: 4),
          background: ChannelBudget(id: 'bg', label: '背景', maxTracks: 2, maxChannels: 2),
          sfx: ChannelBudget(id: 'sfx', label: '音效', maxTracks: 4, maxChannels: 8),
          whiteNoise: ChannelBudget(id: 'wn', label: '白噪音', maxTracks: 8, maxChannels: 4),
        ),
      AudioDeviceClass.mobile => const ChannelScheme(
          label: '移动端 · 声道减半（省功耗）',
          music: ChannelBudget(id: 'music', label: '音乐', maxTracks: 2, maxChannels: 2),
          background: ChannelBudget(id: 'bg', label: '背景', maxTracks: 2, maxChannels: 2),
          sfx: ChannelBudget(id: 'sfx', label: '音效', maxTracks: 4, maxChannels: 4),
          whiteNoise: ChannelBudget(id: 'wn', label: '白噪音', maxTracks: 8, maxChannels: 2),
        ),
      AudioDeviceClass.compact => const ChannelScheme(
          label: '紧凑设备 · 音轨/声道双降',
          music: ChannelBudget(id: 'music', label: '音乐', maxTracks: 1, maxChannels: 2),
          background: ChannelBudget(id: 'bg', label: '背景', maxTracks: 1, maxChannels: 2),
          sfx: ChannelBudget(id: 'sfx', label: '音效', maxTracks: 2, maxChannels: 2),
          whiteNoise: ChannelBudget(id: 'wn', label: '白噪音', maxTracks: 4, maxChannels: 2),
        ),
    };
