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
/// 安全性：仅绑定 127.0.0.1（本机），不对外网开放；无鉴权（本机信任边界）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio/audio_providers.dart';
import '../../providers/tools/weather_provider.dart';

/// 集控本地服务端口（固定，便于集控端插件接入）。
const int kControlPort = 43218;

/// 全局导航/通知 key（供无 context 的集控服务弹通知用；
/// 在 app 根 MaterialApp 注入 navigatorKey 时生效）。
final GlobalKey<ScaffoldMessengerState> kControlMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

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
  WidgetRef? _ref;

  bool get running => _running;
  int get port => kControlPort;
  String get error => _error;

  /// 启动服务并挂上 Riverpod 引用（处理命令用）。
  /// 可在 app 启动后（ProviderScope 就绪）调用；幂等。
  Future<void> start(WidgetRef ref) async {
    _ref = ref;
    if (_running) return;
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
        if (payload is Map<String, dynamic> &&
            payload['text'] is String &&
            kControlMessengerKey.currentState != null) {
          kControlMessengerKey.currentState!.showSnackBar(
            SnackBar(
              content: Text(payload['text'] as String),
              duration: const Duration(seconds: 3),
            ),
          );
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
    req.response
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(body);
    req.response.close();
  }
}
