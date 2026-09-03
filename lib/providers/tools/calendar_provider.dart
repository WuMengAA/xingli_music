/// ════════════════════════════════════════════════════════════════════════
/// 星璃日历 · Provider
///
/// - 本地事件（标题/日期/备注），SharedPreferences 持久化（calendar.events）
/// - 公历固定节日标注（安全列表；农历节日依赖农历算法，暂不内置）
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 日历事件。
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    this.note = '',
  });

  final String id;
  final String title;
  final DateTime date;
  final String note;

  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        note: j['note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'date':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'note': note,
      };
}

/// 公历固定节日（月/日 → 名称；闰年 2/29 不标注）。
const Map<int, Map<int, String>> kFixedHolidays = <int, Map<int, String>>{
  1: <int, String>{1: '元旦'},
  2: <int, String>{14: '情人节'},
  3: <int, String>{8: '妇女节', 12: '植树节'},
  4: <int, String>{1: '愚人节'},
  5: <int, String>{1: '劳动节', 4: '青年节'},
  6: <int, String>{1: '儿童节'},
  7: <int, String>{1: '建党节'},
  8: <int, String>{1: '建军节'},
  9: <int, String>{10: '教师节'},
  10: <int, String>{1: '国庆节', 31: '万圣夜'},
  12: <int, String>{24: '平安夜', 25: '圣诞节'},
};

/// 取某日的固定节日名（无则空串）。
String fixedHolidayOf(DateTime d) =>
    kFixedHolidays[d.month]?[d.day] ?? '';

class CalendarNotifier extends StateNotifier<List<CalendarEvent>> {
  CalendarNotifier() : super(const <CalendarEvent>[]);

  static const String _kEvents = 'calendar.events';

  /// 启动时从 SharedPreferences 加载。
  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString(_kEvents) ?? '';
    if (raw.isEmpty) {
      state = const <CalendarEvent>[];
      return;
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      state = <CalendarEvent>[
        for (final dynamic e in list)
          CalendarEvent.fromJson(e as Map<String, dynamic>),
      ]..sort((a, b) => a.date.compareTo(b.date));
    } catch (_) {
      state = const <CalendarEvent>[];
    }
  }

  Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kEvents, jsonEncode(<Map<String, dynamic>>[
      for (final CalendarEvent e in state) e.toJson(),
    ]));
  }

  /// 新增事件。
  Future<void> add({
    required String title,
    required DateTime date,
    String note = '',
  }) async {
    if (title.trim().isEmpty) return;
    final List<CalendarEvent> next = <CalendarEvent>[
      ...state,
      CalendarEvent(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title.trim(),
        date: DateTime(date.year, date.month, date.day),
        note: note,
      ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    state = next;
    await _persist();
  }

  /// 删除事件。
  Future<void> remove(String id) async {
    state = <CalendarEvent>[
      for (final CalendarEvent e in state)
        if (e.id != id) e,
    ];
    await _persist();
  }

  /// 某日的全部事件。
  List<CalendarEvent> eventsOn(DateTime d) =>
      state.where((e) =>
          e.date.year == d.year &&
          e.date.month == d.month &&
          e.date.day == d.day).toList();

  /// 某月的全部事件（月视图徽标用）。
  List<CalendarEvent> eventsIn(int year, int month) =>
      state.where((e) => e.date.year == year && e.date.month == month).toList();
}

final calendarProvider =
    StateNotifierProvider<CalendarNotifier, List<CalendarEvent>>(
  (ref) => CalendarNotifier(),
);
