import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/server_config.dart';
import '../../providers/color_memory/color_memory_providers.dart';

/// 外部连接配置列表（设置页增删改，曲库聚合消费）
///
/// 密码随配置一起存于本地 SharedPreferences。本地个人音乐空间场景下足够；
/// 若日后需要系统级加密存储，可换 flutter_secure_storage（需 VS 安装 ATL 组件）。
final serverConfigsProvider =
    StateNotifierProvider<ServerConfigNotifier, List<ServerConfig>>(
  (ref) => ServerConfigNotifier(ref.watch(prefsProvider)),
);

class ServerConfigNotifier extends StateNotifier<List<ServerConfig>> {
  final SharedPreferences _prefs;

  ServerConfigNotifier(this._prefs) : super(const []) {
    _load();
  }

  static const String _key = 'server_configs';

  void _load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null) {
      state = const [];
      return;
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      state = list
          .map((e) => ServerConfig.fromJson(e as Map<String, dynamic>))
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

  Future<void> addOrUpdate(ServerConfig cfg) async {
    final int idx = state.indexWhere((c) => c.name == cfg.name);
    if (idx >= 0) {
      final List<ServerConfig> next = [...state];
      next[idx] = cfg;
      state = next;
    } else {
      state = [...state, cfg];
    }
    await _persist();
  }

  Future<void> remove(String name) async {
    state = state.where((c) => c.name != name).toList();
    await _persist();
  }

  Future<void> setEnabled(String name, bool enabled) async {
    state = state
        .map((c) => c.name == name ? c.copyWith(enabled: enabled) : c)
        .toList();
    await _persist();
  }
}
