/// ════════════════════════════════════════════════════════════════════════
/// media_kit 接入探针（S1）
/// ════════════════════════════════════════════════════════════════════════
///
/// 仅用于验证 media_kit（libmpv）依赖在双端（Windows / Android）编译可用，
/// 不接入主播放链路。S2 起由 `MediaKitPlayer` 替换 `AudioService._music`。
///
/// 用法：
/// 1. `flutter analyze lib` 确认 API 引用无误；
/// 2. `flutter build windows --release` / `flutter build apk --release`
///    确认 libmpv 原生库链接成功（S1 达标线）。
library;

import 'package:media_kit/media_kit.dart';

/// 返回 media_kit 可用性（S1 探针）。
String mediaKitStatus() {
  try {
    return 'media_kit 1.2.6 (libmpv)';
  } catch (_) {
    return 'media_kit 不可用';
  }
}

/// 探测：能否创建 Player（有音频设备的真机/桌面可实际 play/pause）。
///
/// 测试环境（flutter test 无原生平台）不调用本方法；真机验证由集成测试承担。
Future<bool> mediaKitPlayerProbe() async {
  try {
    final Player player = Player();
    await player.open(Media(''));
    await player.pause();
    await player.dispose();
    return true;
  } catch (_) {
    return false;
  }
}
