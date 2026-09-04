/// ════════════════════════════════════════════════════════════════════════
/// 集控插件 · 本地控制服务（被集控端）
///
/// 星璃作为 ClassIsland 集控体系的被控端：在本机启动一个 localhost HTTP
/// 服务，接收集控端（学校/机构后台或本机脚本）下发的命令与状态查询。
///
/// 协议（POST http://127.0.0.1:{port}/api/control，JSON）：
///   { action, payload }（port 固定 43218，可被集成到集控端插件）
///
/// 动作：
///   report          → 返回应用状态（当前曲目/播放态/音量/天气城市）
///   set_weather     → 设置天气默认城市 { payload:{ name, latitude, longitude, country, admin1 } }
///   set_volume      → 设置音量 { payload:{ volume: 0.0~1.0 } }
///   play / pause    → 播放 / 暂停（payload 可省略）
///   notice          → 应用内横幅通知 { payload:{ text } }
///
/// 安全性：仅绑定 127.0.0.1（本机），不对外网开放；可选鉴权——配置 token 后
/// 请求需带 `X-Control-Token` 头（未配置 = 免鉴权本机信任边界）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/audio/audio_providers.dart';
import '../../providers/tools/weather_provider.dart';
import '../../widgets/notification/app_notify.dart';

/// 集控本地服务端口（固定，便于集控端插件接入）。
const int kControlPort = 43218;

/// 集控鉴权：请求头 `X-Control-Token` 需匹配本机配置的 token（未配置则免鉴权）。
const String kControlTokenHeader = 'X-Control-Token';
const String _kTokenPrefsKey = 'control.token';

/// 集控服务状态（是否已监听 + 端口）。
class ControlServerState {
  const ControlServerState({
    this.running = false,
    this.port = kControlPort,
    this.error = '',
  });

  final bool running;
  final int port;
  final String error;
}

/// 集控服务（单例）。
class ControlServer {
  ControlServer._();

  static final ControlServer instance = ControlServer._();

  HttpServer? _server;
  bool _running = false;
  String _error = '';
  String _token = '';
  WidgetRef? _ref;

  bool get running => _running;
  int get port => kControlPort;
  String get error => _error;

  /// 当前鉴权 token（空 = 未启用鉴权）。集控端请求需带 `X-Control-Token`。
  String get token => _token;

  /// 设置鉴权 token 并持久化（空串 = 关闭鉴权）。
  Future<void> setToken(String value) async {
    _token = value.trim();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenPrefsKey, _token);
  }

  /// 启动时恢复鉴权 token。
  Future<void> _loadToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kTokenPrefsKey) ?? '';
  }

  /// 启动服务并挂上 Riverpod 引用（处理命令用）。
  /// 可在 app 启动后（ProviderScope 就绪）调用；幂等。
  Future<void> start(WidgetRef ref) async {
    _ref = ref;
    if (_running) return;
    await _loadToken();
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4,
          kControlPort, shared: true);
      _running = true;
      _error = '';
      _server!.listen(_handle);
    } catch (e) {
      _running = false;
      _error = '集控服务启动失败：$e';
    }
  }

  Future<void> stop() async {
    _running = false;
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      // 鉴权：配置了 token 时校验请求头，避免本机其它进程乱调集控接口。
      if (_token.isNotEmpty &&
          req.headers.value(kControlTokenHeader) != _token) {
        _respond(req, 401, '{"ok":false,"error":"unauthorized"}');
        return;
      }
      if (req.method == 'POST' &&
          req.uri.path == '/api/control') {
        final String body = await utf8.decoder.bind(req).join();
        await _route(req, body);
        return;
      }
      _respond(req, 404, '{"ok":false,"error":"not found"}');
    } catch (e) {
      _respond(req, 500, '{"ok":false,"error":"$e"}');
    }
  }

  Future<void> _route(HttpRequest req, String body) async {
    final WidgetRef? ref = _ref;
    dynamic data;
    try {
      data = jsonDecode(body);
    } catch (_) {
      _respond(req, 400, '{"ok":false,"error":"bad json"}');
      return;
    }
    final String action =
        data is Map<String, dynamic> ? (data['action'] as String? ?? '') : '';
    final dynamic payload =
        data is Map<String, dynamic> ? data['payload'] : null;

    switch (action) {
      case 'report':
        final String status = _reportStatus(ref);
        _respond(req, 200, '{"ok":true,$status}');
        break;
      case 'set_weather':
        await _setWeather(ref, payload);
        _respond(req, 200, '{"ok":true}');
        break;
      case 'set_volume':
        await _setVolume(ref, payload);
        _respond(req, 200, '{"ok":true}');
        break;
      case 'play':
        await ref?.read(audioServiceProvider).resume();
        _respond(req, 200, '{"ok":true}');
        break;
      case 'pause':
        await ref?.read(audioServiceProvider).pauseOnly();
        _respond(req, 200, '{"ok":true}');
        break;
      case 'notice':
        // 集控横幅：走全局通知条（右上角 ≤1/3 宽弹条，AppShell 常驻渲染），
        // 样式与 App 内通知统一，不再用底部 SnackBar。
        if (payload is Map<String, dynamic> &&
            payload['text'] is String &&
            ref != null) {
          appNotifyRef(ref, payload['text'] as String, title: '集控');
        }
        _respond(req, 200, '{"ok":true}');
        break;
      default:
        _respond(req, 400,
            '{"ok":false,"error":"unknown action: $action"}');
    }
  }

  String _reportStatus(WidgetRef? ref) {
    if (ref == null) return '"app":"xingli_music"';
    final String playing = ref.read(audioServiceProvider).musicPlaying ? '1' : '0';
    final double volume = ref.read(musicVolumeProvider);
    final WeatherState w = ref.read(weatherProvider);
    final String city = w.city?.name ?? '';
    return '"app":"xingli_music","playing":$playing,'
        '"volume":$volume,"city":"$city"';
  }

  Future<void> _setWeather(WidgetRef? ref, dynamic payload) async {
    if (ref == null || payload is! Map<String, dynamic>) return;
    final WeatherCity city = WeatherCity(
      name: payload['name'] as String? ?? '',
      latitude: (payload['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (payload['longitude'] as num?)?.toDouble() ?? 0,
      country: payload['country'] as String? ?? '',
      admin1: payload['admin1'] as String? ?? '',
    );
    if (city.name.isEmpty) return;
    await ref.read(weatherProvider.notifier).setDefaultCity(city);
  }

  Future<void> _setVolume(WidgetRef? ref, dynamic payload) async {
    if (ref == null || payload is! Map<String, dynamic>) return;
    final double v = (payload['volume'] as num?)?.toDouble() ?? -1;
    if (v < 0 || v > 1) return;
    ref.read(musicVolumeProvider.notifier).state = v;
    await ref.read(audioServiceProvider).setMusicVolume(v);
  }

  void _respond(HttpRequest req, int code, String body) {
    // 防双写：若响应已关闭（例如 _route 内部已回包后又抛异常），直接忽略，
    // 避免 double-close 抛错把 500 响应变成连接错误。
    if (req.response.headers.contentType != null) return;
    req.response
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(body);
    req.response.close();
  }
}
