import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/scene.dart';
import '../color_memory/color_memory_providers.dart';

/// 用户自定义/覆盖的场景（存 SharedPreferences，key 为场景 id）。
///
/// - 内置场景的自定义修改：以「覆盖副本」方式保存（id 不变，替换字段）
/// - 新增场景：id 以 'custom_' 开头
final customScenesProvider =
    StateNotifierProvider<CustomScenesNotifier, List<Scene>>(
  (ref) => CustomScenesNotifier(ref.watch(prefsProvider)),
);

class CustomScenesNotifier extends StateNotifier<List<Scene>> {
  final SharedPreferences _prefs;

  CustomScenesNotifier(this._prefs) : super(const []) {
    _load();
  }

  static const String _key = 'custom_scenes_v1';

  void _load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null) {
      state = const [];
      return;
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      state = list
          .map((e) => Scene.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      state = const [];
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _key,
      jsonEncode(state.map((c) => c.toJson()).toList()),
    );
  }

  /// 保存一个场景（覆盖或新增）。传入完整 Scene。
  Future<void> save(Scene scene) async {
    final List<Scene> rest = state.where((s) => s.id != scene.id).toList();
    state = [...rest, scene];
    await _persist();
  }

  /// 删除一个自定义场景（内置场景不支持删除）
  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _persist();
  }

  /// 取某个 id 的自定义覆盖（无则 null）
  Scene? byId(String id) {
    for (final Scene s in state) {
      if (s.id == id) return s;
    }
    return null;
  }
}
