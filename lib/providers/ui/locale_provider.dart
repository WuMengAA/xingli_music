import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage_providers.dart';

/// 应用界面语言（cl07 i18n）。
///
/// 默认中文；prefs 键 `locale`（ISO 639-1 语言码，如 `zh` / `en`）。
/// 切换即时生效（MaterialApp.locale 变化 → 本地化子树重建）。
class LocalePrefs extends StateNotifier<Locale> {
  LocalePrefs(this._prefs) : super(_load(_prefs));

  static Locale _load(SharedPreferences prefs) {
    final String code = prefs.getString('locale') ?? 'zh';
    return Locale(code);
  }

  final SharedPreferences _prefs;

  void set(Locale locale) {
    if (locale.languageCode == state.languageCode) return;
    state = locale;
    unawaited(_prefs.setString('locale', locale.languageCode));
  }
}

/// 当前界面语言。
final StateNotifierProvider<LocalePrefs, Locale> localeProvider =
    StateNotifierProvider<LocalePrefs, Locale>(
  (Ref ref) => LocalePrefs(ref.read(prefsProvider)),
);
