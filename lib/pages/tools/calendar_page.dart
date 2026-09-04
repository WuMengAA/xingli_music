/// ════════════════════════════════════════════════════════════════════════
/// 星璃日历页
///
/// - 月视图：7 列网格（周一起始），今天高亮、事件/节日徽标
/// - 点击某日：查看该日事件（新增/删除）
/// - 顶部：年月切换（上/下月、回到今天）
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/tools/calendar_provider.dart';

/// 日历页。
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _shown; // 当前展示的月（取 1 日）

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _shown = DateTime(now.year, now.month);
    // 事件加载由 calendarProvider 首 watch 自动完成（无需手动 load）。
  }

  void _shift(int delta) {
    // ⚠️ 限制翻月范围 [1900, 2100]：农历表只覆盖该区间，越过会下标越界。
    final DateTime next = DateTime(_shown.year, _shown.month + delta);
    if (next.year < 1900 || next.year > 2100) return;
    setState(() => _shown = next);
  }

  void _goToday() {
    final DateTime now = DateTime.now();
    setState(() => _shown = DateTime(now.year, now.month));
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final List<CalendarEvent> events = ref.watch(calendarProvider);
    final DateTime today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('星璃日历'),
        actions: <Widget>[
          IconButton(
            tooltip: '今天',
            icon: const Icon(Icons.today),
            onPressed: _goToday,
          ),
          IconButton(
            tooltip: '下个月',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shift(1),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _monthHeader(c),
          _weekdayRow(c),
          Expanded(child: _grid(c, today, events)),
        ],
      ),
    );
  }

  Widget _monthHeader(AppThemeColors c) {
    // 农历年（取该月 1 日的农历干支年）。
    final LunarDate anchor = solarToLunar(DateTime(_shown.year, _shown.month, 1));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: <Widget>[
          Text('${_shown.year} 年 ${_shown.month} 月',
              style: c.textPrimary.style(fontSize: 18, w700: true)),
          const SizedBox(width: 8),
          Text('${anchor.yearName}年 ${anchor.zodiac}年',
              style: c.textSecondary.style(fontSize: 12)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shift(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shift(1),
          ),
        ],
      ),
    );
  }

  Widget _weekdayRow(AppThemeColors c) {
    const List<String> week = <String>['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: <Widget>[
        for (final String w in week)
          Expanded(
            child: Center(
              child: Text(w,
                  style: c.textSecondary.style(fontSize: 12)),
            ),
          ),
      ],
    );
  }

  Widget _grid(AppThemeColors c, DateTime today, List<CalendarEvent> events) {
    final int firstWeekday =
        DateTime(_shown.year, _shown.month, 1).weekday; // 1=周一
    final int lead = firstWeekday - 1;
    final int daysInMonth = DateTime(_shown.year, _shown.month + 1, 0).day;

    final List<Widget> cells = <Widget>[
      for (int i = 0; i < lead; i++) const SizedBox.shrink(),
      for (int d = 1; d <= daysInMonth; d++)
        _dayCell(c, today, events, DateTime(_shown.year, _shown.month, d)),
    ];

    return GridView.count(
      crossAxisCount: 7,
      padding: const EdgeInsets.all(8),
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }

  Widget _dayCell(AppThemeColors c, DateTime today, List<CalendarEvent> events,
      DateTime day) {
    final bool isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    final String holiday = fixedHolidayOf(day);
    final LunarDate lunar = solarToLunar(day);
    final String lunarLabel =
        lunar.isFestival ? lunar.festivalName : lunar.dayName;
    final int eventCount = events
        .where((e) =>
            e.date.year == day.year &&
            e.date.month == day.month &&
            e.date.day == day.day)
        .length;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showDaySheet(c, day),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isToday ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '${day.day}',
              style: TextStyle(
                color: isToday ? Colors.white : c.textPrimary,
                fontSize: 15,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (holiday.isNotEmpty)
              Text(holiday,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isToday ? Colors.white70 : c.accent,
                    fontSize: 8,
                  ))
            else if (lunar.isFestival)
              Text(lunarLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isToday ? Colors.white70 : c.accent,
                    fontSize: 8,
                  ))
            else if (eventCount > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.circle, size: 5, color: c.accent),
                  const SizedBox(width: 2),
                  Text('$eventCount',
                      style: TextStyle(
                          color: isToday ? Colors.white70 : c.textSecondary,
                          fontSize: 8)),
                ],
              )
            else
              Text(lunarLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isToday ? Colors.white70 : c.textTertiary,
                    fontSize: 8,
                  )),
          ],
        ),
      ),
    );
  }

  /// 某日详情：事件列表 + 新增/删除。
  void _showDaySheet(AppThemeColors c, DateTime day) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        final String holiday = fixedHolidayOf(day);
        final LunarDate lunar = solarToLunar(day);
        final List<CalendarEvent> dayEvents =
            ref.read(calendarProvider.notifier).eventsOn(day);
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheet) {
            void refresh() =>
                setSheet(() => dayEvents
                  ..clear()
                  ..addAll(
                      ref.read(calendarProvider.notifier).eventsOn(day)));
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        '${day.month} 月 ${day.day} 日'
                        '${holiday.isNotEmpty ? ' · $holiday' : ''}',
                        style:
                            c.textPrimary.style(fontSize: 16, w700: true),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '添加事件',
                        icon: const Icon(Icons.add),
                        onPressed: () => _addEvent(c, day).then((_) {
                          if (mounted) refresh();
                        }),
                      ),
                    ],
                  ),
                  // 农历信息：干支年 / 生肖 / 农历日期（含节日）。
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${lunar.yearName}年（${lunar.zodiac}年） · '
                      '农历${lunar.monthName}${lunar.dayName}'
                      '${lunar.isFestival ? ' · ${lunar.festivalName}' : ''}',
                      style: c.textTertiary.style(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (dayEvents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text('这一天没有事件',
                            style: c.textTertiary.style(fontSize: 13)),
                      ),
                    )
                  else
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: dayEvents.length,
                        itemBuilder: (BuildContext context, int i) {
                          final CalendarEvent e = dayEvents[i];
                          return ListTile(
                            dense: true,
                            title: Text(e.title,
                                style:
                                    c.textPrimary.style(fontSize: 14)),
                            subtitle: e.note.isEmpty
                                ? null
                                : Text(e.note,
                                    style: c.textSecondary
                                        .style(fontSize: 12)),
                            trailing: IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline,
                                  size: 18),
                              onPressed: () async {
                                await ref
                                    .read(calendarProvider.notifier)
                                    .remove(e.id);
                                if (mounted) refresh();
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 添加事件（标题必填；备注可选）。
  Future<void> _addEvent(AppThemeColors c, DateTime day) async {
    final TextEditingController title = TextEditingController();
    final TextEditingController note = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: Text('添加事件 · ${day.month}/${day.day}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(hintText: '事件标题'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: const InputDecoration(hintText: '备注（可选）'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dctx).pop();
              unawaited(ref
                  .read(calendarProvider.notifier)
                  .add(title: title.text, date: day, note: note.text));
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    title.dispose();
    note.dispose();
  }
}

/// 颜色 → 文本样式便捷扩展（本文件内使用）。
extension _ColorStyle on Color {
  TextStyle style({double fontSize = 14, bool w700 = false}) => TextStyle(
        color: this,
        fontSize: fontSize,
        fontWeight: w700 ? FontWeight.w700 : null,
      );
}
