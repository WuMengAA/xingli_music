/// ════════════════════════════════════════════════════════════════════════
/// 星璃日历 · Provider
///
/// - 本地事件（标题/日期/备注），SharedPreferences 持久化（calendar.events）
/// - 公历固定节日标注 + 农历转换（标准农历数据表 1900–2100，含农历节日）
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

// ════════════════════════════════════════════════════════════════════════
// 农历（Lunar）转换 · 标准农历数据表 1900–2100
// ════════════════════════════════════════════════════════════════════════

/// 农历结果。
class LunarDate {
  const LunarDate({
    required this.year,
    required this.month,
    required this.day,
    required this.isLeapMonth,
    required this.yearName, // 天干地支年（如「甲辰」）
    required this.zodiac, // 生肖
    required this.monthName,
    required this.dayName,
    required this.isFestival, // 是否农历节日
    required this.festivalName,
  });

  final int year;
  final int month;
  final int day;
  final bool isLeapMonth;
  final String yearName;
  final String zodiac;
  final String monthName;
  final String dayName;
  final bool isFestival;
  final String festivalName;
}

/// 农历数据表：每项 16 进制编码该农历年的月信息
/// （位 4-15：12 个月大小，0=29 天 1=30 天；位 1-4：闰月位置 0=无闰）。
const List<int> _lunarInfo = <int>[
  0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2, // 1900-1909
  0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977, // 1910-1919
  0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, // 1920-1929
  0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950, // 1930-1939
  0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557, // 1940-1949
  0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, // 1950-1959
  0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, // 1960-1969
  0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6, // 1970-1979
  0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570, // 1980-1989
  0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0, // 1990-1999
  0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, // 2000-2009
  0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930, // 2010-2019
  0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530, // 2020-2029
  0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, // 2030-2039
  0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, // 2040-2049
  0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0, // 2050-2059
  0x092e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4, // 2060-2069
  0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0, // 2070-2079
  0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160, // 2080-2089
  0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252, // 2090-2099
  0x0d520, // 2100
];

const List<String> _heavenlyStems = <String>['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
const List<String> _earthlyBranches = <String>['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
const List<String> _zodiacs = <String>['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
const List<String> _cnMonths = <String>['正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];
const List<String> _cnDays = <String>[
  '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
  '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十',
];

/// 农历节日（月/日 → 名称；含春节/元宵/端午/中秋/重阳/腊八/除夕（除夕按 12-29/30 特殊处理）。
const Map<int, Map<int, String>> kLunarFestivals = <int, Map<int, String>>{
  1: <int, String>{1: '春节', 15: '元宵节'},
  2: <int, String>{2: '龙抬头'},
  5: <int, String>{5: '端午节'},
  7: <int, String>{7: '七夕节', 15: '中元节'},
  8: <int, String>{15: '中秋节'},
  9: <int, String>{9: '重阳节'},
  12: <int, String>{8: '腊八节', 30: '除夕'},
};

/// 农历每月天数（含闰月）。
int _lunarYearDays(int year) {
  int sum = 348;
  for (int i = 0x8000; i > 0x8; i >>= 1) {
    if ((_lunarInfo[year - 1900] & i) != 0) sum += 1;
  }
  return sum + _leapMonthDays(year);
}

/// 闰月天数（0=无闰月）。
int _leapMonthDays(int year) {
  if (_leapMonth(year) != 0) {
    return (_lunarInfo[year - 1900] & 0x10000) != 0 ? 30 : 29;
  }
  return 0;
}

/// 闰月位置（0=无闰月）。
int _leapMonth(int year) => _lunarInfo[year - 1900] & 0xf;

/// 某农历年某月天数（month 1-12；leap 是否闰月）。
int _monthDays(int year, int month, {bool leap = false}) {
  if (leap && month == _leapMonth(year)) return _leapMonthDays(year);
  return (_lunarInfo[year - 1900] & (0x10000 >> month)) != 0 ? 30 : 29;
}

/// 公历 → 农历。基准：1900-01-31 = 农历 1900 年正月初一。
LunarDate solarToLunar(DateTime solar) {
  final DateTime base = DateTime(1900, 1, 31);
  int offset = DateTime(solar.year, solar.month, solar.day)
      .difference(base)
      .inDays;
  int year = 1900;
  while (year < 2100 && offset >= _lunarYearDays(year)) {
    offset -= _lunarYearDays(year);
    year++;
  }
  final int leap = _leapMonth(year);
  bool isLeap = false;
  int month = 1;
  while (month <= 12) {
    final int days = _monthDays(year, month, leap: month == leap);
    if (offset < days) break;
    offset -= days;
    if (month == leap) {
      isLeap = true;
      break;
    }
    month++;
  }
  final int day = offset + 1;

  // 干支年：以立春为界简化为公历年近似（农历年序号）。
  final int ganIdx = (year - 4) % 10;
  final int zhiIdx = (year - 4) % 12;
  final String yearName = '${_heavenlyStems[ganIdx]}${_earthlyBranches[zhiIdx]}';
  final String zodiac = _zodiacs[zhiIdx];

  // 节日：除夕按 12-29/30 两种可能。
  String festival = kLunarFestivals[month]?[day] ?? '';
  bool isFestival = festival.isNotEmpty;
  if (!isFestival && month == 12 && day >= 29 && _monthDays(year, 12) == day) {
    festival = '除夕';
    isFestival = true;
  }

  return LunarDate(
    year: year,
    month: month,
    day: day,
    isLeapMonth: isLeap,
    yearName: yearName,
    zodiac: zodiac,
    monthName: '${isLeap ? '闰' : ''}${_cnMonths[month - 1]}月',
    dayName: _cnDays[day - 1],
    isFestival: isFestival,
    festivalName: festival,
  );
}
