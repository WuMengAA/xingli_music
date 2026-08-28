import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage_providers.dart';

/// 离线模式（cl08）：开启后**不依靠官方服务器**——不检查 OTA、不连官方
/// 中转（一起听/联机）、不上传远程日志。本地能力完全可用：
/// 本地音乐 / 场景 / 自建 Subsonic 音源 / 设置均不依赖网络。
///
/// prefs 键 `offline_mode`，默认关（在线优先）。
class OfflineModePrefs extends StateNotifier<bool> {
  OfflineModePrefs(this._prefs) : super(_prefs.getBool('offline_mode') ?? false);

  final SharedPreferences _prefs;

  void set(bool v) {
    state = v;
    unawaited(_prefs.setBool('offline_mode', v));
  }
}

/// 当前是否离线模式。
final StateNotifierProvider<OfflineModePrefs, bool> offlineModeProvider =
    StateNotifierProvider<OfflineModePrefs, bool>(
  (Ref ref) => OfflineModePrefs(ref.read(prefsProvider)),
);
