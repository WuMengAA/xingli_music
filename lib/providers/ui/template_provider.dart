import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/templates/ui_template.dart';
import '../storage/storage_providers.dart';

/// 界面标准模板（cl08：设置 → 界面模板，选择后作为全站标准模板）。
///
/// 默认「液态玻璃」；prefs 键 `ui_template`（枚举 name）。
class TemplatePrefs extends StateNotifier<UiTemplate> {
  TemplatePrefs(this._prefs) : super(_load(_prefs));

  static UiTemplate _load(SharedPreferences prefs) {
    final String name = prefs.getString('ui_template') ?? '';
    return UiTemplate.values.firstWhere(
      (UiTemplate t) => t.name == name,
      orElse: () => UiTemplate.glass,
    );
  }

  final SharedPreferences _prefs;

  void set(UiTemplate template) {
    state = template;
    unawaited(_prefs.setString('ui_template', template.name));
  }
}

/// 当前界面标准模板。
final StateNotifierProvider<TemplatePrefs, UiTemplate> templateProvider =
    StateNotifierProvider<TemplatePrefs, UiTemplate>(
  (Ref ref) => TemplatePrefs(ref.read(prefsProvider)),
);
