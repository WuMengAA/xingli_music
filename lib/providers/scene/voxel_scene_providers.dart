import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/voxel.dart';
import '../../providers/color_memory/color_memory_providers.dart';
import '../../services/log_service.dart';

/// 2.5D 音效场景列表（持久化 key：`voxel_sound_scenes_v1`）。
///
/// A2 已裁决：2.5D 音效保存为**独立音效层**（不入 `Scene.soundscapePath`，
/// 避免污染既有场景数据）。
final StateNotifierProvider<VoxelScenesNotifier, List<VoxelSoundScene>>
    voxelSoundScenesProvider =
    StateNotifierProvider<VoxelScenesNotifier, List<VoxelSoundScene>>(
  (Ref ref) => VoxelScenesNotifier(ref.watch(prefsProvider)),
);

class VoxelScenesNotifier extends StateNotifier<List<VoxelSoundScene>> {
  VoxelScenesNotifier(this._prefs) : super(const <VoxelSoundScene>[]) {
    _load();
  }

  static const String _key = 'voxel_sound_scenes_v1';
  final SharedPreferences _prefs;

  void _load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null) {
      state = const <VoxelSoundScene>[];
      return;
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      state = list
          .map((dynamic e) =>
              VoxelSoundScene.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      LogService.instance.w('voxel', '音效场景解析失败: $e');
      state = const <VoxelSoundScene>[];
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _key,
      jsonEncode(state.map((VoxelSoundScene s) => s.toJson()).toList()),
    );
  }

  /// 保存（覆盖或新增）。
  Future<void> save(VoxelSoundScene scene) async {
    final List<VoxelSoundScene> rest =
        state.where((VoxelSoundScene s) => s.id != scene.id).toList();
    state = <VoxelSoundScene>[...rest, scene];
    await _persist();
  }

  /// 删除。
  Future<void> remove(String id) async {
    state = state.where((VoxelSoundScene s) => s.id != id).toList();
    await _persist();
  }

  VoxelSoundScene? byId(String id) {
    for (final VoxelSoundScene s in state) {
      if (s.id == id) return s;
    }
    return null;
  }
}
