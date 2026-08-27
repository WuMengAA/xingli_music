/// 搜索历史（持久化）。
///
/// 跨重启保留最近搜索关键词，存于 shared_preferences（cl64-5：搜索持久化）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索历史：最近优先、去重、上限 20 条，自动落地 shared_preferences。
final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>(
  (ref) => SearchHistoryNotifier(),
);

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super(const <String>[]) {
    _load();
  }

  static const String _key = 'search_history_v1';
  static const int _max = 20;

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? saved = prefs.getStringList(_key);
    if (saved != null && saved.isNotEmpty && !_same(saved, state)) {
      state = saved;
    }
  }

  bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 记录一次搜索（去重并置顶）。空串忽略。
  void add(String raw) {
    final String kw = raw.trim();
    if (kw.isEmpty) return;
    final List<String> next = <String>[
      kw,
      for (final String e in state.where((e) => e != kw)) e,
    ];
    if (next.length > _max) next.removeRange(_max, next.length);
    state = next;
    _persist();
  }

  /// 删除单条
  void remove(String kw) {
    state = state.where((e) => e != kw).toList();
    _persist();
  }

  /// 清空全部
  void clear() {
    state = const <String>[];
    _persist();
  }

  Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state);
  }
}
