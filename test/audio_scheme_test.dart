/// R26skel-b5：声音分类通道方案回归（主/音乐/背景/音效/白噪音预算）。
library;

import 'package:flutter_test/flutter_test.dart';

import '../lib/providers/audio/audio_scheme.dart';

void main() {
  test('桌面端方案 = 用户定版预算（音乐2/4 背景2/2 音效4/8 白噪8/4）', () {
    final s = schemeFor(AudioDeviceClass.desktop);
    expect(s.music.maxTracks, 2);
    expect(s.music.maxChannels, 4);
    expect(s.background.maxTracks, 2);
    expect(s.background.maxChannels, 2);
    expect(s.sfx.maxTracks, 4);
    expect(s.sfx.maxChannels, 8);
    expect(s.whiteNoise.maxTracks, 8);
    expect(s.whiteNoise.maxChannels, 4);
  });

  test('移动端声道减半、紧凑端音轨/声道双降', () {
    final m = schemeFor(AudioDeviceClass.mobile);
    expect(m.sfx.maxChannels, 4); // 8→4
    expect(m.music.maxChannels, 2); // 4→2
    final c = schemeFor(AudioDeviceClass.compact);
    expect(c.music.maxTracks, 1); // 2→1
    expect(c.sfx.maxTracks, 2); // 4→2
    expect(c.whiteNoise.maxChannels, 2); // 4→2
  });

  test('设备类别检测：非 web 环境按平台兜底 desktop（web 视口逻辑仅 web 生效）', () {
    // `flutter test` 环境 kIsWeb=false → 走 io 平台分支；Windows/macOS/Linux
    // 恒为 desktop。web 上窄视口才判 compact（本测试环境无法触达）。
    expect(detectAudioDeviceClass(), AudioDeviceClass.desktop);
    expect(detectAudioDeviceClass(webViewportWidth: 1200),
        AudioDeviceClass.desktop);
  });
}
