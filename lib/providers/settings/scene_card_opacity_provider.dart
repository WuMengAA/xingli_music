import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage_providers.dart';

const String kSceneCardOpacity = 'scene_card_opacity';

/// 场景卡片背景浓度（深色叠加层不透明度，0.1~0.9，默认 0.25）。
///
/// 越低越通透——视频背景透出越明显；越高卡片越实、文字对比越稳。
/// 用户可在「个性 → 场景 → 场景卡片透明度」中自行调节，选择持久化保存。
final StateNotifierProvider<SceneCardOpacity, double> sceneCardOpacityProvider =
    StateNotifierProvider<SceneCardOpacity, double>(
  (Ref ref) => SceneCardOpacity(ref.read(prefsProvider)),
);

class SceneCardOpacity extends StateNotifier<double> {
  SceneCardOpacity(this._prefs)
      : super((_prefs.getDouble(kSceneCardOpacity) ?? 0.25).clamp(0.1, 0.9));
  final SharedPreferences _prefs;

  void set(double v) {
    final double c = v.clamp(0.1, 0.9);
    state = c;
    _prefs.setDouble(kSceneCardOpacity, c);
  }
}
