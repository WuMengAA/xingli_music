import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/scene.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/session/session_providers.dart';
import '../../services/sensor/sensor_service.dart';

/// 传感器服务单例（v2 实验 F · Q5 已裁决）。
final Provider<SensorService> sensorServiceProvider = Provider<SensorService>(
  (Ref ref) {
    final SensorService svc = SensorService();
    ref.onDispose(svc.dispose);
    return svc;
  },
);

/// 环境光 lux 流（Android 有值；其余平台 null = 不支持）。
final StreamProvider<double?> lightLuxProvider = StreamProvider<double?>(
  (Ref ref) => ref.watch(sensorServiceProvider).lightLux(),
);

/// 陀螺仪流（rad/s；Android/iOS；不支持平台为空流）。
final StreamProvider<GyroscopeEvent> gyroscopeProvider = StreamProvider<GyroscopeEvent>(
  (Ref ref) => ref.watch(sensorServiceProvider).gyroscope(),
);

/// 心率流（bpm；多数设备无此传感器 → null = 无心率传感器）。
final StreamProvider<double?> heartRateProvider = StreamProvider<double?>(
  (Ref ref) => ref.watch(sensorServiceProvider).heartRate(),
);

/// 摇晃检测流（触发 `true` 表示检测到一次摇晃）。
final StreamProvider<bool> shakeDetectedProvider = StreamProvider<bool>(
  (Ref ref) => ref.watch(sensorServiceProvider).shakeDetected(),
);

/// 场景亮度遮罩（0.0~1.0）：lux 越低 → 遮罩越深（模拟暗场景）。
///
/// - lux >= 300：无遮罩（1.0 透明）
/// - lux <= 10：深遮罩（0.35 透明显得暗）
/// 桌面 lux = null → 默认无遮罩。
final Provider<double> sceneBrightnessMaskProvider = Provider<double>((Ref ref) {
  final double? lux = ref.watch(lightLuxProvider).valueOrNull;
  if (lux == null) return 1.0;
  final double t = ((lux - 10) / 290).clamp(0.0, 1.0);
  return 0.35 + 0.65 * t;
});

/// 摇一摇切换场景（实验 F 联动）。
///
/// 监听 [shakeDetectedProvider]，每次摇晃切换到下一场景（循环）。
/// 由实验页 watch 本 provider 以激活监听。
final Provider<void> shakeSceneLinkProvider = Provider<void>((Ref ref) {
  ref.listen<bool>(
    shakeDetectedProvider.select((AsyncValue<bool> v) => v.valueOrNull ?? false),
    (bool? prev, bool next) {
      if (!next) return;
      ref.read(sceneShakeNotifierProvider).nextScene();
    },
  );
  return;
});

/// 摇一摇联动开关（默认关，实验页内开启）。
final StateProvider<bool> shakeSceneEnabledProvider =
    StateProvider<bool>((Ref ref) => false);

/// 摇一摇后的提示文案（消费方 SnackBar）。
final StateProvider<String?> shakeSceneMessageProvider =
    StateProvider<String?>((Ref ref) => null);

/// 场景切换封装（供 shakeSceneLinkProvider 使用）。
final Provider<SceneShakeNotifier> sceneShakeNotifierProvider =
    Provider<SceneShakeNotifier>((Ref ref) => SceneShakeNotifier(ref));

/// 摇晃 → 切下一场景（循环）。
class SceneShakeNotifier {
  SceneShakeNotifier(this._ref);

  final Ref _ref;

  Future<void> nextScene() async {
    final List<Scene> scenes = _ref.read(sceneOrderProvider);
    if (scenes.isEmpty) return;
    final int current = _ref.read(currentSceneIndexProvider);
    final int next = (current + 1) % scenes.length;
    _ref.read(currentSceneIndexProvider.notifier).state = next;
    final Scene scene = scenes[next];
    await _ref.read(audioServiceProvider).switchSoundscape(scene);
    _ref.read(shakeSceneMessageProvider.notifier).state = '摇一摇 → 切换到「${scene.name}」';
  }
}
