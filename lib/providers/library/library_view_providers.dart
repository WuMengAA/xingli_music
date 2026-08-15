import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/color_memory/color_memory_providers.dart';
import '../../services/log_service.dart';

/// 曲库浏览样式（#421：卡片式 / 列表式）。
enum LibraryViewStyle { card, list }

/// 当前浏览样式（持久化到 prefs，key：`library_view_style_v1`）。
final StateNotifierProvider<LibraryViewStyleNotifier, LibraryViewStyle>
    libraryViewStyleProvider =
    StateNotifierProvider<LibraryViewStyleNotifier, LibraryViewStyle>(
  (Ref ref) => LibraryViewStyleNotifier(ref.watch(prefsProvider)),
);

class LibraryViewStyleNotifier extends StateNotifier<LibraryViewStyle> {
  LibraryViewStyleNotifier(this._prefs) : super(LibraryViewStyle.card) {
    _load();
  }

  static const String _key = 'library_view_style_v1';
  final SharedPreferences _prefs;

  void _load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null) return;
    for (final LibraryViewStyle s in LibraryViewStyle.values) {
      if (s.name == raw) {
        state = s;
        return;
      }
    }
  }

  Future<void> setStyle(LibraryViewStyle style) async {
    state = style;
    final bool ok = await _prefs.setString(_key, style.name);
    if (!ok) {
      LogService.instance.w('library', '视图样式持久化失败');
    }
  }
}
