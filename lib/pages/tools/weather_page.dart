/// ════════════════════════════════════════════════════════════════════════
/// 星璃天气页（Open-Meteo 数据源）
///
/// - 顶部：当前天气（温度 / 天气图标 / 体感 / 风速）+ 城市名 + 刷新
/// - 中部：7 日预报横向滚动（图标 + 最高/最低温 + 降水概率）
/// - 底部/右上：城市管理（搜索添加 / 切换默认城市）
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/tools/weather_provider.dart';

/// 天气页。
class WeatherPage extends ConsumerStatefulWidget {
  const WeatherPage({super.key});

  @override
  ConsumerState<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends ConsumerState<WeatherPage> {
  bool _searching = false;
  bool _locating = false;
  final TextEditingController _q = TextEditingController();
  List<WeatherCity> _results = const <WeatherCity>[];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _pickCity(WeatherCity city) async {
    await ref.read(weatherProvider.notifier).setDefaultCity(city);
    if (!mounted) return;
    setState(() {
      _results = const <WeatherCity>[];
      _q.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final WeatherState w = ref.watch(weatherProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('星璃天气'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(weatherProvider.notifier).refresh(),
          ),
          IconButton(
            tooltip: '城市管理',
            icon: const Icon(Icons.location_city),
            onPressed: () => _showCitySheet(c),
          ),
        ],
      ),
      body: _buildBody(c, w),
    );
  }

  Widget _buildBody(AppThemeColors c, WeatherState w) {
    if (w.loading && w.current == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (w.city == null && w.current == null) {
      // 未选择城市：引导搜索。
      return _EmptyCity(c);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _currentCard(c, w),
        const SizedBox(height: 16),
        _dailyRow(c, w.daily),
        const SizedBox(height: 8),
        if (w.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(w.error,
                style: TextStyle(color: c.accent, fontSize: 12)),
          ),
      ],
    );
  }

  /// 当前天气卡片（大温度 + 天气图标 + 城市名 + 风速）。
  Widget _currentCard(AppThemeColors c, WeatherState w) {
    final CurrentWeather? cur = w.current;
    final WeatherMeta meta =
        cur == null ? const WeatherMeta('🌡️', '加载中') : weatherMeta(cur.weatherCode);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[c.accentSoft, c.bgCard],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: <Widget>[
          Text(
            w.city?.name ?? '',
            style: c.textPrimary.style(fontSize: 20, w700: true),
          ),
          if (w.city != null && w.city!.admin1.isNotEmpty)
            Text('${w.city!.admin1} · ${w.city!.country}',
                style: c.textSecondary.style(fontSize: 12)),
          const SizedBox(height: 12),
          Text(meta.icon, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 4),
          Text(
            cur == null ? '--' : '${cur.temperature.round()}°',
            style: c.textPrimary.style(fontSize: 56, w700: true),
          ),
          Text(meta.label, style: c.textSecondary.style(fontSize: 14)),
          const SizedBox(height: 8),
          if (cur != null)
            Text('风速 ${cur.windSpeed.toStringAsFixed(1)} km/h',
                style: c.textSecondary.style(fontSize: 12)),
          if (w.lastUpdated != null)
            Text(
              '更新于 ${w.lastUpdated!.hour.toString().padLeft(2, '0')}:'
              '${w.lastUpdated!.minute.toString().padLeft(2, '0')}',
              style: c.textTertiary.style(fontSize: 11),
            ),
        ],
      ),
    );
  }

  /// 7 日预报横向滚动。
  Widget _dailyRow(AppThemeColors c, List<DailyWeather> days) {
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final DailyWeather d = days[i];
          final WeatherMeta m = weatherMeta(d.weatherCode);
          final bool today = i == 0;
          return Container(
            width: 76,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: today ? c.accent : c.border,
                width: today ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  today
                      ? '今天'
                      : '${d.date.month}/${d.date.day}',
                  style: c.textSecondary.style(fontSize: 12),
                ),
                Text(m.icon, style: const TextStyle(fontSize: 24)),
                Text('${d.tempMax.round()}°/${d.tempMin.round()}°',
                    style: c.textPrimary.style(fontSize: 13)),
                if (d.precipProb > 0)
                  Text('💧${d.precipProb}%',
                      style: c.textTertiary.style(fontSize: 10))
                else
                  const SizedBox(height: 14),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCitySheet(AppThemeColors c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // ⚠️ 必须用 StatefulBuilder：showModalBottomSheet 的 builder 是独立路由，
      // 页面 setState 不会重建它——否则搜索结果永远不显示（天气无法添加查询 bug）。
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext sheetCtx, StateSetter setSheet) {
          Future<void> doSearch(String q) async {
            setSheet(() => _searching = true);
            final List<WeatherCity> r =
                await ref.read(weatherProvider.notifier).search(q);
            if (!sheetCtx.mounted) return;
            setSheet(() {
              _results = r;
              _searching = false;
            });
          }

          Future<void> doLocate() async {
            setSheet(() => _locating = true);
            final WeatherCity? city =
                await ref.read(weatherProvider.notifier).locate();
            if (!sheetCtx.mounted) return;
            setSheet(() => _locating = false);
            if (city == null) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('定位失败（可能网络受限），请手动搜索城市'),
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }
            await ref
                .read(weatherProvider.notifier)
                .setDefaultCity(city);
            if (!sheetCtx.mounted) return;
            Navigator.of(sheetContext).pop();
            if (!mounted) return;
            setState(() {
              _results = const <WeatherCity>[];
              _q.clear();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已定位到 ${city.label}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('搜索城市', style: c.textPrimary.style(fontSize: 16, w700: true)),
                const SizedBox(height: 10),
                TextField(
                  controller: _q,
                  autofocus: true,
                  onSubmitted: doSearch,
                  decoration: InputDecoration(
                    hintText: '输入城市名（支持中文）',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                // 自动定位（IP 定位，无权限弹窗）。
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: doLocate,
                    icon: const Icon(Icons.my_location, size: 16),
                    label: Text(
                      _locating ? '定位中…' : '自动定位当前城市',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_results.isNotEmpty)
                  SizedBox(
                    height: 240,
                    child: ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (BuildContext context, int i) {
                        final WeatherCity city = _results[i];
                        return ListTile(
                          dense: true,
                          title: Text(city.label,
                              style: c.textPrimary.style(fontSize: 14)),
                          subtitle: Text(city.country,
                              style: c.textSecondary.style(fontSize: 12)),
                          trailing: const Icon(Icons.add_location_alt_outlined,
                              size: 18),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _pickCity(city);
                          },
                        );
                      },
                    ),
                  )
                else if (!_searching)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('输入城市名后回车搜索，或点上方自动定位',
                        style: c.textTertiary.style(fontSize: 12)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 未选择城市引导卡。
class _EmptyCity extends StatelessWidget {
  const _EmptyCity(this.c);

  final AppThemeColors c;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text('🌤️', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 12),
          Text('还没有城市', style: c.textPrimary.style(fontSize: 18, w700: true)),
          const SizedBox(height: 6),
          Text('点右上角「城市管理」搜索添加',
              style: c.textSecondary.style(fontSize: 13)),
        ],
      ),
    );
  }
}

/// 颜色 → 文本样式的便捷扩展（本文件内使用）。
extension _ColorStyle on Color {
  TextStyle style({double fontSize = 14, bool w700 = false}) => TextStyle(
        color: this,
        fontSize: fontSize,
        fontWeight: w700 ? FontWeight.w700 : null,
      );
}
