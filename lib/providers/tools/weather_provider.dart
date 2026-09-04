/// ════════════════════════════════════════════════════════════════════════
/// 星璃天气 · Provider（Open-Meteo，免费无 key）
///
/// - 城市搜索：Open-Meteo Geocoding API（支持中文城市名）
/// - 实时天气 + 7 日预报：Open-Meteo Forecast API
/// - 城市列表/默认城市用 SharedPreferences 持久化
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 城市（地理编码结果）。
class WeatherCity {
  const WeatherCity({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.country,
    this.admin1 = '',
  });

  final String name;
  final double latitude;
  final double longitude;
  final String country;
  final String admin1;

  factory WeatherCity.fromJson(Map<String, dynamic> j) => WeatherCity(
        name: j['name'] as String? ?? '',
        latitude: (j['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (j['longitude'] as num?)?.toDouble() ?? 0,
        country: j['country'] as String? ?? '',
        admin1: j['admin1'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'country': country,
        'admin1': admin1,
      };

  String get label => admin1.isEmpty ? name : '$name · $admin1';
}

/// 单日天气。
class DailyWeather {
  const DailyWeather({
    required this.date,
    required this.weatherCode,
    required this.tempMax,
    required this.tempMin,
    this.precipProb = 0,
  });

  final DateTime date;
  final int weatherCode;
  final double tempMax;
  final double tempMin;
  final int precipProb;
}

/// 实时天气。
class CurrentWeather {
  const CurrentWeather({
    required this.temperature,
    required this.weatherCode,
    required this.windSpeed,
    this.isDay = true,
  });

  final double temperature;
  final int weatherCode;
  final double windSpeed;
  final bool isDay;
}

/// WMO 天气代码 → 图标/文案。
class WeatherMeta {
  const WeatherMeta(this.icon, this.label);

  final String icon;
  final String label;
}

WeatherMeta weatherMeta(int code) {
  switch (code) {
    case 0:
      return const WeatherMeta('☀️', '晴');
    case 1:
    case 2:
      return const WeatherMeta('🌤️', '多云');
    case 3:
      return const WeatherMeta('☁️', '阴');
    case 45:
    case 48:
      return const WeatherMeta('🌫️', '雾');
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
      return const WeatherMeta('🌦️', '毛毛雨');
    case 61:
    case 63:
    case 65:
    case 66:
    case 67:
      return const WeatherMeta('🌧️', '雨');
    case 71:
    case 73:
    case 75:
    case 77:
      return const WeatherMeta('🌨️', '雪');
    case 80:
    case 81:
    case 82:
      return const WeatherMeta('🌧️', '阵雨');
    case 85:
    case 86:
      return const WeatherMeta('🌨️', '阵雪');
    case 95:
      return const WeatherMeta('⛈️', '雷暴');
    case 96:
    case 99:
      return const WeatherMeta('⛈️', '雷暴伴冰雹');
    default:
      return const WeatherMeta('🌡️', '未知');
  }
}

class WeatherState {
  const WeatherState({
    this.city,
    this.current,
    this.daily = const <DailyWeather>[],
    this.loading = false,
    this.error = '',
    this.lastUpdated,
  });

  final WeatherCity? city;
  final CurrentWeather? current;
  final List<DailyWeather> daily;
  final bool loading;
  final String error;
  final DateTime? lastUpdated;

  WeatherState copyWith({
    WeatherCity? city,
    CurrentWeather? current,
    List<DailyWeather>? daily,
    bool? loading,
    String? error,
    DateTime? lastUpdated,
  }) =>
      WeatherState(
        city: city ?? this.city,
        current: current ?? this.current,
        daily: daily ?? this.daily,
        loading: loading ?? this.loading,
        error: error ?? this.error,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
}

class WeatherNotifier extends StateNotifier<WeatherState> {
  WeatherNotifier() : super(const WeatherState());

  static const String _kCities = 'weather.cities';
  static const String _kDefaultCity = 'weather.defaultCity';

  /// 已保存的城市列表。
  Future<List<WeatherCity>> savedCities() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString(_kCities) ?? '';
    if (raw.isEmpty) return const <WeatherCity>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return <WeatherCity>[
        for (final dynamic e in list)
          WeatherCity.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const <WeatherCity>[];
    }
  }

  /// 当前默认城市（无则返回 null）。
  Future<WeatherCity?> defaultCity() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString(_kDefaultCity) ?? '';
    if (raw.isEmpty) return null;
    try {
      return WeatherCity.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 保存默认城市并拉取天气。
  Future<void> setDefaultCity(WeatherCity city) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultCity, jsonEncode(city.toJson()));
    final List<WeatherCity> cities = await savedCities();
    if (!cities.any((c) =>
        (c.latitude - city.latitude).abs() < 1e-4 &&
        (c.longitude - city.longitude).abs() < 1e-4)) {
      await prefs.setString(
          _kCities, jsonEncode(<Map<String, dynamic>>[
        for (final WeatherCity c in <WeatherCity>[city, ...cities]) c.toJson(),
      ]));
    }
    await refresh(city: city);
  }

  /// 启动时加载默认城市天气（无城市则静默）。
  Future<void> loadDefault() async {
    final WeatherCity? city = await defaultCity();
    if (city == null) return;
    await refresh(city: city);
  }

  /// 城市搜索（Open-Meteo Geocoding，支持中文）。
  Future<List<WeatherCity>> search(String query) async {
    if (query.trim().isEmpty) return const <WeatherCity>[];
    final Uri uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(query.trim())}&count=8&language=zh&format=json');
    try {
      final http.Response resp =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return const <WeatherCity>[];
      final dynamic data = jsonDecode(utf8.decode(resp.bodyBytes));
      final List<dynamic>? results = data['results'] as List<dynamic>?;
      if (results == null) return const <WeatherCity>[];
      return <WeatherCity>[
        for (final dynamic e in results)
          WeatherCity.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const <WeatherCity>[];
    }
  }

  /// 自动定位（IP 定位，免费无权限）：优先 ip-api.com，失败降级 ipapi.co。
  /// 返回 null 表示全部源失败（页面提示手动搜索）；成功返回城市供
  /// [setDefaultCity] 使用。
  Future<WeatherCity?> locate() async {
    // 源 1：ip-api.com（字段精简、免费无 key，但 http 明文）。
    final WeatherCity? c1 = await _locateVia(
      Uri.parse(
          'http://ip-api.com/json/?lang=zh-CN&fields=status,country,regionName,city,lat,lon'),
      parse: (Map<String, dynamic> d) {
        if (d['status'] != 'success') return null;
        final String city = d['city'] as String? ?? '';
        if (city.isEmpty) return null;
        return WeatherCity(
          name: city,
          latitude: (d['lat'] as num?)?.toDouble() ?? 0,
          longitude: (d['lon'] as num?)?.toDouble() ?? 0,
          country: d['country'] as String? ?? '',
          admin1: d['regionName'] as String? ?? '',
        );
      },
    );
    if (c1 != null) return c1;

    // 源 2：ipapi.co（https 明文备用，字段结构不同）。
    return _locateVia(
      Uri.parse('https://ipapi.co/json/'),
      parse: (Map<String, dynamic> d) {
        final String city = d['city'] as String? ?? '';
        if (city.isEmpty) return null;
        return WeatherCity(
          name: city,
          latitude: (d['latitude'] as num?)?.toDouble() ?? 0,
          longitude: (d['longitude'] as num?)?.toDouble() ?? 0,
          country: d['country_name'] as String? ?? '',
          admin1: d['region'] as String? ?? '',
        );
      },
    );
  }

  Future<WeatherCity?> _locateVia(
    Uri uri, {
    required WeatherCity? Function(Map<String, dynamic>) parse,
  }) async {
    try {
      final http.Response resp =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final dynamic data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data is! Map<String, dynamic>) return null;
      return parse(data);
    } catch (_) {
      return null;
    }
  }

  /// 拉取实时 + 7 日预报。
  Future<void> refresh({WeatherCity? city}) async {
    final WeatherCity? target = city ?? state.city;
    if (target == null) return;
    state = state.copyWith(loading: true, error: '', city: target);
    final Uri uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${target.latitude}&longitude=${target.longitude}'
        '&current=temperature_2m,weather_code,wind_speed_10m,is_day'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
        '&timezone=auto&forecast_days=7');
    try {
      final http.Response resp =
          await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        state = state.copyWith(
            loading: false, error: '天气服务异常（${resp.statusCode}）');
        return;
      }
      final dynamic data = jsonDecode(utf8.decode(resp.bodyBytes));
      // 空安全：current/daily 缺失或非对象时降级（不崩、不清旧数据）。
      final Map<String, dynamic> cur =
          data is Map<String, dynamic> && data['current'] is Map<String, dynamic>
              ? data['current'] as Map<String, dynamic>
              : const <String, dynamic>{};
      final Map<String, dynamic> daily = data is Map<String, dynamic> &&
              data['daily'] is Map<String, dynamic>
          ? data['daily'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final List<DailyWeather> days = <DailyWeather>[];
      final List<dynamic> dates = daily['time'] as List<dynamic>? ?? const [];
      final List<dynamic> codes = daily['weather_code'] as List<dynamic>? ?? const [];
      final List<dynamic> maxs = daily['temperature_2m_max'] as List<dynamic>? ?? const [];
      final List<dynamic> mins = daily['temperature_2m_min'] as List<dynamic>? ?? const [];
      final List<dynamic> probs = daily['precipitation_probability_max'] as List<dynamic>? ?? const [];
      for (int i = 0; i < dates.length; i++) {
        days.add(DailyWeather(
          date: DateTime.tryParse(dates[i] as String? ?? '') ?? DateTime.now(),
          weatherCode: (codes[i] as num?)?.toInt() ?? 0,
          tempMax: (maxs[i] as num?)?.toDouble() ?? 0,
          tempMin: (mins[i] as num?)?.toDouble() ?? 0,
          precipProb: (probs[i] as num?)?.toInt() ?? 0,
        ));
      }
      state = cur.isEmpty
          ? state.copyWith(loading: false, error: '天气数据异常（无 current）')
          : state.copyWith(
              loading: false,
              current: CurrentWeather(
                temperature: (cur['temperature_2m'] as num?)?.toDouble() ?? 0,
                weatherCode: (cur['weather_code'] as num?)?.toInt() ?? 0,
                windSpeed: (cur['wind_speed_10m'] as num?)?.toDouble() ?? 0,
                isDay: (cur['is_day'] as num?)?.toInt() == 1,
              ),
              daily: days,
              lastUpdated: DateTime.now(),
            );
    } catch (e) {
      state = state.copyWith(loading: false, error: '获取天气失败：$e');
    }
  }
}

final weatherProvider =
    StateNotifierProvider<WeatherNotifier, WeatherState>(
  (ref) => WeatherNotifier(),
);
