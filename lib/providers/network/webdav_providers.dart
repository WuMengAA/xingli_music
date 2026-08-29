import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/webdav_config.dart';
import '../../services/log_service.dart';
import '../../services/music_sources/music_source.dart';
import '../../services/network/webdav_client.dart';
import '../../services/network/webdav_source.dart';
import '../storage/storage_providers.dart';

/// WebDAV 配置列表（持久化 key：`webdav_configs_v1`）。
final StateNotifierProvider<WebDavConfigsNotifier, List<WebDavConfig>>
    webdavConfigsProvider = StateNotifierProvider<WebDavConfigsNotifier,
        List<WebDavConfig>>(
  (ref) => WebDavConfigsNotifier(ref.watch(prefsProvider)),
);

class WebDavConfigsNotifier extends StateNotifier<List<WebDavConfig>> {
  WebDavConfigsNotifier(this._prefs) : super(<WebDavConfig>[]) {
    _load();
  }

  static const String _key = 'webdav_configs_v1';
  final SharedPreferences _prefs;

  void _load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      state = list
          .map((dynamic e) =>
              WebDavConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      LogService.instance.w('webdav', '配置解析失败: $e');
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _key,
      jsonEncode(state.map((WebDavConfig c) => c.toJson()).toList()),
    );
  }

  Future<void> add(WebDavConfig c) async {
    state = <WebDavConfig>[...state, c];
    await _persist();
  }

  Future<void> update(WebDavConfig c) async {
    state = state
        .map((WebDavConfig e) => e.id == c.id ? c : e)
        .toList();
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((WebDavConfig e) => e.id != id).toList();
    await _persist();
  }
}

/// 每个配置生成一个解析源（供 activeSourcesProvider 聚合，见 audio_providers）。
final Provider<List<MusicSource>> webdavSourcesProvider =
    Provider<List<MusicSource>>(
  (ref) {
    final List<WebDavConfig> configs = ref.watch(webdavConfigsProvider);
    return <MusicSource>[
      for (final WebDavConfig c in configs)
        WebDavSource(
          WebDavClient(
            baseUrl: c.baseUrl,
            username: c.username,
            password: c.password,
          ),
          sourceId: c.id,
        ),
    ];
  },
);

/// 生成 WebDAV 播放占位 uri：`webdav://<base64url(path)>`。
String webdavPlaceholderUri(String path) =>
    'webdav://${base64Url.encode(utf8.encode(path))}';