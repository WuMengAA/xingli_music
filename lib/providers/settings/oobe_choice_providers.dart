/// ════════════════════════════════════════════════════════════════════════
/// OOBE 选择 / 询问类 Provider（cl75）
/// ════════════════════════════════════════════════════════════════════════
///
/// 初始化流程「选择 / 询问」两步收集的用户偏好，全部即时写入 provider，
/// 并由 [settingsSyncProvider] 持久化到 [SettingsRepository]，冷启动由
/// [restoreSettings] 灌回。与现有 themeMode / themeSkin / graphicsQuality
/// 等 provider 同一套「运行期写回」机制。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage_providers.dart';

/// 音频质量偏好（0=高品 · 1=标准 · 2=省流；默认 1=标准）。
///
/// 对应网易云 `level`（standard/higher/exhigh/lossless），源层可按此选档。
final audioQualityProvider = StateProvider<int>((ref) => 1);

/// 音频质量档标签。
const Map<int, String> kAudioQualityLabels = <int, String>{
  0: '高品',
  1: '标准',
  2: '省流',
};

/// 是否允许匿名体验改进（默认 false）。
final analyticsConsentProvider = StateProvider<bool>((ref) => false);

/// 主要聆听场景（多选，[kListenSourceOptions] 的子集）。
final listenSourcesProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

/// 可选聆听场景。
const List<String> kListenSourceOptions = <String>[
  '睡眠',
  '专注',
  '学习',
  '放松',
  '运动',
  '游戏',
];

/// 最多可选流派数（cl05：防「选择瘫痪」）。
const int kMaxGenres = 3;

/// 可选音乐流派（cl05）。
const List<String> kGenreOptions = <String>[
  '摇滚',
  '古典',
  '电子',
  '民谣',
  '爵士',
  '流行',
  '说唱',
  '轻音乐',
];

/// 音乐流派偏好（多选 ≤[kMaxGenres]，cl05）。
///
/// 用 SharedPreferences 直接持久化（键 `genre_prefs`，逗号分隔），
/// 独立于场景偏好（listenSources），不依赖 settingsSync。
class GenrePrefs extends StateNotifier<Set<String>> {
  GenrePrefs(this._prefs)
      : super(Set<String>.from(
          (_prefs.getString('genre_prefs') ?? '')
              .split(',')
              .where((String s) => s.isNotEmpty),
        ));

  final SharedPreferences _prefs;

  /// 切换一个流派；超出上限返回 false（上层可提示）。
  bool toggle(String genre) {
    final Set<String> next = Set<String>.from(state);
    if (next.contains(genre)) {
      next.remove(genre);
    } else {
      if (next.length >= kMaxGenres) return false;
      next.add(genre);
    }
    state = next;
    unawaited(_prefs.setString('genre_prefs', next.join(',')));
    return true;
  }
}

/// 当前流派偏好（空集合表示未选择）。
final StateNotifierProvider<GenrePrefs, Set<String>> genrePrefsProvider =
    StateNotifierProvider<GenrePrefs, Set<String>>(
  (Ref ref) => GenrePrefs(ref.read(prefsProvider)),
);
