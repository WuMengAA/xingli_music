import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 全局设置仓库（R10/R11）
/// ════════════════════════════════════════════════════════════════════════
///
/// 所有用户操作的**唯一持久化入口**（收口 shared_preferences，禁止散落
/// 直接调用 SP）。冷启动时由 main() 读取并恢复（R10），运行中由
/// [SettingsSync] 监听各 provider 写回（R11）。
///
/// 持久化清单（R10 八项 + 扩展）：
///  - 音量：musicVolume / soundscapeVolume / musicMuted / soundscapeMuted
///  - 白噪音：whiteNoiseEnabled / whiteNoiseVolume
///  - 当前场景：currentSceneId
///  - 播放模式：playMode
///  - 主题：themeMode / themeSkin
///  - EQ：eqEnabled / eqPresetId / eqGains
///  - 均衡模式：balanceMode
///  - 上次曲目：lastTrackUri / lastTrackTitle / lastTrackArtist / lastPositionMs
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String kMusicVolume = 'settings.musicVolume';
  static const String kSoundscapeVolume = 'settings.soundscapeVolume';
  static const String kMusicMuted = 'settings.musicMuted';
  static const String kSoundscapeMuted = 'settings.soundscapeMuted';
  static const String kWhiteNoiseEnabled = 'settings.whiteNoiseEnabled';
  static const String kWhiteNoiseVolume = 'settings.whiteNoiseVolume';
  static const String kCurrentSceneId = 'settings.currentSceneId';
  static const String kPlayMode = 'settings.playMode';
  static const String kThemeMode = 'settings.themeMode';
  static const String kThemeSkin = 'settings.themeSkin';
  static const String kEqEnabled = 'settings.eqEnabled';
  static const String kEqPresetId = 'settings.eqPresetId';
  static const String kEqGains = 'settings.eqGains';
  static const String kBalanceMode = 'settings.balanceMode';
  static const String kPerformanceMode = 'settings.performanceMode';
  static const String kLastTrackUri = 'settings.lastTrackUri';
  static const String kLastTrackTitle = 'settings.lastTrackTitle';
  static const String kLastTrackArtist = 'settings.lastTrackArtist';
  static const String kLastPositionMs = 'settings.lastPositionMs';

  // ── 音量 ─────────────────────────────────────────
  double get musicVolume => _prefs.getDouble(kMusicVolume) ?? 0.7;
  Future<void> setMusicVolume(double v) => _prefs.setDouble(kMusicVolume, v);

  double get soundscapeVolume => _prefs.getDouble(kSoundscapeVolume) ?? 0.25;
  Future<void> setSoundscapeVolume(double v) =>
      _prefs.setDouble(kSoundscapeVolume, v);

  bool get musicMuted => _prefs.getBool(kMusicMuted) ?? false;
  Future<void> setMusicMuted(bool v) => _prefs.setBool(kMusicMuted, v);

  bool get soundscapeMuted => _prefs.getBool(kSoundscapeMuted) ?? false;
  Future<void> setSoundscapeMuted(bool v) =>
      _prefs.setBool(kSoundscapeMuted, v);

  // ── 白噪音 ───────────────────────────────────────
  bool get whiteNoiseEnabled => _prefs.getBool(kWhiteNoiseEnabled) ?? false;
  Future<void> setWhiteNoiseEnabled(bool v) =>
      _prefs.setBool(kWhiteNoiseEnabled, v);

  double get whiteNoiseVolume => _prefs.getDouble(kWhiteNoiseVolume) ?? 0.3;
  Future<void> setWhiteNoiseVolume(double v) =>
      _prefs.setDouble(kWhiteNoiseVolume, v);

  // ── 场景 / 播放 ──────────────────────────────────
  String? get currentSceneId => _prefs.getString(kCurrentSceneId);
  Future<void> setCurrentSceneId(String? id) =>
      id == null ? _prefs.remove(kCurrentSceneId) : _prefs.setString(kCurrentSceneId, id);

  String get playMode => _prefs.getString(kPlayMode) ?? 'order';
  Future<void> setPlayMode(String v) => _prefs.setString(kPlayMode, v);

  // ── 主题 ─────────────────────────────────────────
  String get themeMode => _prefs.getString(kThemeMode) ?? 'system';
  Future<void> setThemeMode(String v) => _prefs.setString(kThemeMode, v);

  String get themeSkin => _prefs.getString(kThemeSkin) ?? 'starlight';
  Future<void> setThemeSkin(String v) => _prefs.setString(kThemeSkin, v);

  // ── EQ ───────────────────────────────────────────
  bool get eqEnabled => _prefs.getBool(kEqEnabled) ?? false;
  Future<void> setEqEnabled(bool v) => _prefs.setBool(kEqEnabled, v);

  String get eqPresetId => _prefs.getString(kEqPresetId) ?? 'flat';
  Future<void> setEqPresetId(String v) => _prefs.setString(kEqPresetId, v);

  List<double> get eqGains {
    final String? raw = _prefs.getString(kEqGains);
    if (raw == null) return const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    }
  }

  Future<void> setEqGains(List<double> gains) =>
      _prefs.setString(kEqGains, jsonEncode(gains));

  // ── 均衡模式 ─────────────────────────────────────
  String get balanceMode => _prefs.getString(kBalanceMode) ?? 'normal';
  Future<void> setBalanceMode(String v) => _prefs.setString(kBalanceMode, v);

  // ── 性能模式（低端设备优化）─────────────────────
  String get performanceMode =>
      _prefs.getString(kPerformanceMode) ?? 'balanced';
  Future<void> setPerformanceMode(String v) =>
      _prefs.setString(kPerformanceMode, v);

  // ── 上次曲目 ─────────────────────────────────────
  String? get lastTrackUri => _prefs.getString(kLastTrackUri);
  String? get lastTrackTitle => _prefs.getString(kLastTrackTitle);
  String? get lastTrackArtist => _prefs.getString(kLastTrackArtist);
  int get lastPositionMs => _prefs.getInt(kLastPositionMs) ?? 0;
  Future<void> setLastTrack({
    required String uri,
    required String title,
    String? artist,
    int positionMs = 0,
  }) async {
    await _prefs.setString(kLastTrackUri, uri);
    await _prefs.setString(kLastTrackTitle, title);
    if (artist != null) await _prefs.setString(kLastTrackArtist, artist);
    await _prefs.setInt(kLastPositionMs, positionMs);
  }
}
