/// ════════════════════════════════════════════════════════════════════════
/// VoiceHub 数据源 Provider（可选接入；自研 relay/P2P 电台层保留不动）
///
/// - 配置：服务器地址 + API Key（SharedPreferences 持久化）
/// - fetchSongs / fetchSchedules：拉取 VoiceHub 开放接口数据
/// - 状态含 loading/error，供 UI 展示；失败不抛，页内提示
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/voicehub/voicehub_client.dart';

/// VoiceHub 配置（空 baseUrl = 未启用）。
class VoiceHubConfig {
  const VoiceHubConfig({this.baseUrl = '', this.apiKey = ''});

  final String baseUrl;
  final String apiKey;

  bool get enabled => baseUrl.trim().isNotEmpty;

  VoiceHubConfig copyWith({String? baseUrl, String? apiKey}) =>
      VoiceHubConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
      );
}

/// VoiceHub 数据状态。
class VoiceHubState {
  const VoiceHubState({
    this.config = const VoiceHubConfig(),
    this.songs = const <VoiceHubSong>[],
    this.schedules = const <VoiceHubSchedule>[],
    this.loading = false,
    this.error = '',
    this.lastSync,
  });

  final VoiceHubConfig config;
  final List<VoiceHubSong> songs;
  final List<VoiceHubSchedule> schedules;
  final bool loading;
  final String error;
  final DateTime? lastSync;

  VoiceHubState copyWith({
    VoiceHubConfig? config,
    List<VoiceHubSong>? songs,
    List<VoiceHubSchedule>? schedules,
    bool? loading,
    String? error,
    DateTime? lastSync,
  }) =>
      VoiceHubState(
        config: config ?? this.config,
        songs: songs ?? this.songs,
        schedules: schedules ?? this.schedules,
        loading: loading ?? this.loading,
        error: error ?? this.error,
        lastSync: lastSync ?? this.lastSync,
      );
}

class VoiceHubNotifier extends StateNotifier<VoiceHubState> {
  VoiceHubNotifier() : super(const VoiceHubState());

  static const String _kBaseUrl = 'voicehub.baseUrl';
  static const String _kApiKey = 'voicehub.apiKey';

  /// 首 watch 自动加载配置（与天气/日历/ClassIsland 一致的约定）。
  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      config: VoiceHubConfig(
        baseUrl: prefs.getString(_kBaseUrl) ?? '',
        apiKey: prefs.getString(_kApiKey) ?? '',
      ),
    );
  }

  /// 保存配置并立即拉取一版数据。
  Future<void> configure(VoiceHubConfig cfg) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, cfg.baseUrl.trim());
    await prefs.setString(_kApiKey, cfg.apiKey.trim());
    state = state.copyWith(config: cfg.copyWith(
      baseUrl: cfg.baseUrl.trim(),
      apiKey: cfg.apiKey.trim(),
    ));
    if (cfg.enabled) await refresh();
  }

  VoiceHubClient? get _client {
    final VoiceHubConfig c = state.config;
    if (!c.enabled) return null;
    return VoiceHubClient(baseUrl: c.baseUrl, apiKey: c.apiKey);
  }

  /// 拉取点歌 + 排期（任一端点失败仅记 error，不抛）。
  Future<void> refresh() async {
    final VoiceHubClient? client = _client;
    if (client == null) return;
    state = state.copyWith(loading: true, error: '');
    try {
      final List<VoiceHubSong> songs = await client.fetchSongs(limit: 50);
      final List<VoiceHubSchedule> schedules =
          await client.fetchSchedules(limit: 50);
      state = state.copyWith(
        loading: false,
        songs: songs,
        schedules: schedules,
        lastSync: DateTime.now(),
      );
    } on VoiceHubException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: '拉取失败：$e');
    }
  }

  /// 搜索点歌（返回结果；失败返回空并记 error）。
  Future<List<VoiceHubSong>> search(String keyword) async {
    final VoiceHubClient? client = _client;
    if (client == null) return const <VoiceHubSong>[];
    try {
      return await client.fetchSongs(search: keyword, limit: 20);
    } on VoiceHubException catch (e) {
      state = state.copyWith(error: e.message);
      return const <VoiceHubSong>[];
    } catch (e) {
      state = state.copyWith(error: '搜索失败：$e');
      return const <VoiceHubSong>[];
    }
  }
}

/// VoiceHub provider（首 watch 自动 load 配置）。
final voiceHubProvider =
    StateNotifierProvider<VoiceHubNotifier, VoiceHubState>((ref) {
  final VoiceHubNotifier n = VoiceHubNotifier();
  Future<void>.microtask(n.load);
  return n;
});