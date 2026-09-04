/// ════════════════════════════════════════════════════════════════════════
/// 工具面板（工具类功能整合归类 · 单入口）
///
/// 把散落在场景页 AppBar 的工具入口（天气 / 日历 / ClassIsland 联动）收敛为
/// 一个「工具」图标。面板内直接嵌各工具迷你卡：
///   - 天气：城市 + 当前温度 + 天气图标（点 → 天气页）
///   - 日历：今日农历（干支/生肖/农历日期）+ 今日事件数（点 → 日历页）
///   - ClassIsland：当前课 / 下一节（点 → 联动页）
/// 一屏同时看到三类信息（信息密度↑），点卡片直达详情（操作步骤↓）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/tools/calendar_provider.dart';
import '../../providers/tools/classisland_provider.dart';
import '../../providers/tools/weather_provider.dart';
import 'calendar_page.dart';
import 'classisland_page.dart';
import 'weather_page.dart';

/// 工具面板页。
class ToolsPanelPage extends ConsumerWidget {
  const ToolsPanelPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    final DateTime now = DateTime.now();

    // ── 三工具状态（只读，勿触发网络请求）──────────────
    final WeatherState w = ref.watch(weatherProvider);
    final List<CalendarEvent> events = ref.watch(calendarProvider);
    final ClassIslandState ciState = ref.watch(classislandProvider);
    final ClassPeriod? current = ciState.currentClassAt(now);
    final ClassPeriod? next = ciState.nextClassAt(now);

    // 今日农历（含节日）。
    final LunarDate lunar = solarToLunar(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('工具'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // ── 今日概览条（公历 + 农历 + 干支年）──────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${now.month} 月 ${now.day} 日 · '
                        '周${'一二三四五六日'[now.weekday - 1]}',
                        style: c.textPrimary.style(fontSize: 16, w700: true),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '农历${lunar.monthName}${lunar.dayName}'
                        '${lunar.isFestival ? ' · ${lunar.festivalName}' : ''}'
                        ' · ${lunar.yearName}年',
                        style: c.textSecondary.style(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text('🐾${lunar.zodiac}', style: c.textTertiary.style(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 天气迷你卡 ─────────────────────────────
          _ToolTile(
            icon: Icons.wb_sunny_outlined,
            title: '天气',
            subtitle: w.city == null
                ? '未设置城市'
                : '${w.city!.name} '
                    '${w.current == null ? '--' : '${w.current!.temperature.round()}°'} '
                    '${w.current == null ? '' : weatherMeta(w.current!.weatherCode).icon}',
            onTap: () => _push(context, const WeatherPage()),
          ),
          const SizedBox(height: 8),

          // ── 日历迷你卡 ─────────────────────────────
          _ToolTile(
            icon: Icons.calendar_month_outlined,
            title: '日历',
            subtitle:
                '今日事件 ${events.where((e) => e.date.year == now.year && e.date.month == now.month && e.date.day == now.day).length} 个',
            onTap: () => _push(context, const CalendarPage()),
          ),
          const SizedBox(height: 8),

          // ── ClassIsland 迷你卡 ──────────────────────
          _ToolTile(
            icon: Icons.school_outlined,
            title: 'ClassIsland',
            subtitle: !ciState.connected
                ? '未连接集控'
                : '当前 ${current?.name ?? '无'} · 下一节 ${next?.name ?? '无'}',
            onTap: () => _push(context, const ClassIslandPage()),
          ),
          const SizedBox(height: 16),

          // ── 操作提示（少步骤：说明快捷路径）──────────
          Text(
            '提示：以上工具也已聚合在场景页顶部「工具」按钮；'
            '常用播放操作在底部 Dock 音乐卡。',
            style: c.textTertiary.style(fontSize: 11),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    unawaited(Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    ));
  }
}

/// 工具入口行（图标 + 标题 + 一行摘要 + 箭头）。
class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Material(
      color: c.bgCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: c.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: c.textPrimary.style(fontSize: 15, w700: true)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: c.textSecondary.style(fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
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
