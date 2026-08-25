import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage_providers.dart';

const String kSceneCardOpacity = 'scene_card_opacity';
const String kSceneCardOpacityMigrated = 'scene_card_opacity_migrated_v1';

/// 场景卡片实色浓度（0.1~1.0，默认 1.0 实底）。
///
/// cl13 用户裁决「场景卡片做成真的卡片」：默认 1.0 = 完全实底（不透明卡），
/// 文字对比最稳；调低则渐变透出、恢复半透明观感。0.9 上限放开到 1.0 使
/// 「实底」成为可达状态。
///
/// 迁移逻辑：cl13 之前旧版本可能存了 <1.0 的值。只要还没迁移过，自动
/// 重置为 1.0，保证「真的卡片」首次展示就是实底；迁移后用户仍可自行
/// 调低。
final StateNotifierProvider<SceneCardOpacity, double> sceneCardOpacityProvider =
    StateNotifierProvider<SceneCardOpacity, double>(
  (Ref ref) => SceneCardOpacity(ref.read(prefsProvider)),
);

class SceneCardOpacity extends StateNotifier<double> {
  SceneCardOpacity(this._prefs) : super(1.0) {
    final bool migrated = _prefs.getBool(kSceneCardOpacityMigrated) ?? false;
    if (!migrated) {
      // 首次迁移：强制改为实底，并标记迁移完成。
      _prefs.setDouble(kSceneCardOpacity, 1.0);
      _prefs.setBool(kSceneCardOpacityMigrated, true);
      state = 1.0;
    } else {
      state = (_prefs.getDouble(kSceneCardOpacity) ?? 1.0).clamp(0.1, 1.0);
    }
  }
  final SharedPreferences _prefs;

  void set(double v) {
    final double c = v.clamp(0.1, 1.0);
    state = c;
    _prefs.setDouble(kSceneCardOpacity, c);
  }
}
