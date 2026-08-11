import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_dir_config.dart';
import '../color_memory/color_memory_providers.dart';

/// 自定义本地目录曲库列表（设置页增删启停，曲库聚合消费）
final localDirConfigsProvider =
    StateNotifierProvider<LocalDirConfigsNotifier, List<LocalDirConfig>>(
  (ref) => LocalDirConfigsNotifier(ref.watch(prefsProvider)),
);

class LocalDirConfigsNotifier extends StateNotifier<List<LocalDirConfig>> {
  final SharedPreferences _prefs;

  LocalDirConfigsNotifier(this._prefs) : super(const []) {
    _load();
  }

  static const String _key = 'local_dir_configs';

  void _load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null) {
      state = const [];
      return;
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      state = list
          .map((e) => LocalDirConfig.fromJson(e as Map<String, dynamic>))
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

  /// 添加一个目录（去重：已存在的路径不重复添加）
  Future<void> add(String path) async {
    final String p = path.trim();
    if (p.isEmpty) return;
    if (state.any((c) => c.path == p)) return;
    state = [...state, LocalDirConfig(path: p)];
    await _persist();
  }

  Future<void> remove(String path) async {
    state = state.where((c) => c.path != path).toList();
    await _persist();
  }

  Future<void> setEnabled(String path, bool enabled) async {
    state = state
        .map((c) => c.path == path ? c.copyWith(enabled: enabled) : c)
        .toList();
    await _persist();
  }
}
