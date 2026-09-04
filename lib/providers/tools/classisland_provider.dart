/// ════════════════════════════════════════════════════════════════════════
/// ClassIsland 集控联动 · Provider
///
/// 对接 ClassIsland 集控体系（学校/机构统一配置下发）的通用客户端：
/// - 配置集控服务器 URL + 班级标识（SharedPreferences 持久化）
/// - 周期拉取课表/时间表（GET {base}/api/classisland/status）
/// - 上报本应用状态（POST {base}/api/classisland/report，可选）
/// - 无服务器时提供「本地演示模式」课表便于预览 UI
///
/// 约定 JSON（集控服务端按此适配 ClassIsland 数据）：
///   GET → { code:0, data:{ date, classes:[{ start,end,name,teacher,room }] } }
///   POST report → { app, playing, title, artist }
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 一节课程。
class ClassPeriod {
  const ClassPeriod({
    required this.start,
    required this.end,
    required this.name,
    this.teacher = '',
    this.room = '',
  });

  /// "HH:mm"（24h）。
  final String start;
  final String end;
  final String name;
  final String teacher;
  final String room;

  factory ClassPeriod.fromJson(Map<String, dynamic> j) => ClassPeriod(
        start: j['start'] as String? ?? '08:00',
        end: j['end'] as String? ?? '08:45',
        name: j['name'] as String? ?? '',
        teacher: j['teacher'] as String? ?? '',
        room: j['room'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'start': start,
        'end': end,
        'name': name,
        'teacher': teacher,
        'room': room,
      };
}

class ClassIslandState {
  const ClassIslandState({
    this.baseUrl = '',
    this.classId = '',
    this.connected = false,
    this.loading = false,
    this.error = '',
    this.date = '',
    this.classes = const <ClassPeriod>[],
    this.lastSync,
  });

  final String baseUrl;
  final String classId;
  final bool connected;
  final bool loading;
  final String error;
  final String date;
  final List<ClassPeriod> classes;
  final DateTime? lastSync;

  ClassIslandState copyWith({
    String? baseUrl,
    String? classId,
    bool? connected,
    bool? loading,
    String? error,
    String? date,
    List<ClassPeriod>? classes,
    DateTime? lastSync,
  }) =>
      ClassIslandState(
        baseUrl: baseUrl ?? this.baseUrl,
        classId: classId ?? this.classId,
        connected: connected ?? this.connected,
        loading: loading ?? this.loading,
        error: error ?? this.error,
        date: date ?? this.date,
        classes: classes ?? this.classes,
        lastSync: lastSync ?? this.lastSync,
      );

  /// 当前时刻正在上的课（无则 null）。
  ClassPeriod? currentClassAt(DateTime now) {
    final int cur = now.hour * 60 + now.minute;
    for (final ClassPeriod p in classes) {
      final int s = _hm(p.start);
      final int e = _hm(p.end);
      if (cur >= s && cur < e) return p;
    }
    return null;
  }

  /// 下一节还没开始的课（无则 null）。
  ClassPeriod? nextClassAt(DateTime now) {
    final int cur = now.hour * 60 + now.minute;
    for (final ClassPeriod p in classes) {
      if (_hm(p.start) > cur) return p;
    }
    return null;
  }

  static int _hm(String t) {
    final List<String> parts = t.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}

class ClassIslandNotifier extends StateNotifier<ClassIslandState> {
  ClassIslandNotifier() : super(const ClassIslandState());

  static const String _kUrl = 'classisland.baseUrl';
  static const String _kClass = 'classisland.classId';
  Timer? _timer;

  /// 恢复配置并拉取一次。
  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String url = prefs.getString(_kUrl) ?? '';
    final String cls = prefs.getString(_kClass) ?? '';
    if (url.isEmpty) {
      state = const ClassIslandState();
      return;
    }
    state = state.copyWith(baseUrl: url, classId: cls);
    await sync();
    _startTimer();
  }

  /// 保存配置并立即拉取。
  Future<void> configure({required String baseUrl, String classId = ''}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUrl, baseUrl.trim());
    await prefs.setString(_kClass, classId.trim());
    state = state.copyWith(
        baseUrl: baseUrl.trim(), classId: classId.trim(), error: '');
    if (baseUrl.trim().isEmpty) {
      _stopTimer();
      state = state.copyWith(classes: const <ClassPeriod>[], connected: false);
      return;
    }
    await sync();
    _startTimer();
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => sync());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 拉取课表（GET {base}/api/classisland/status）。
  Future<void> sync() async {
    if (state.baseUrl.isEmpty) return;
    state = state.copyWith(loading: true, error: '');
    final Uri uri = Uri.parse(
        '${state.baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/classisland/status');
    try {
      final http.Response resp =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        state = state.copyWith(
            loading: false,
            connected: false,
            error: '集控返回 ${resp.statusCode}');
        return;
      }
      final dynamic data = jsonDecode(utf8.decode(resp.bodyBytes));
      final dynamic d = data is Map<String, dynamic> ? data['data'] : null;
      final List<ClassPeriod> classes = <ClassPeriod>[
        if (d is Map<String, dynamic> && d['classes'] is List<dynamic>)
          for (final dynamic c in d['classes'] as List<dynamic>)
            ClassPeriod.fromJson(c as Map<String, dynamic>),
      ]..sort((a, b) => a.start.compareTo(b.start));
      state = state.copyWith(
        loading: false,
        connected: classes.isNotEmpty,
        error: '',
        date: d is Map<String, dynamic> ? (d['date'] as String? ?? '') : '',
        classes: classes,
        lastSync: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
          loading: false, connected: false, error: '连接集控失败：$e');
    }
  }

  /// 上报播放状态（POST {base}/api/classisland/report，失败静默）。
  Future<void> report({
    required String playing,
    String title = '',
    String artist = '',
  }) async {
    if (state.baseUrl.isEmpty || !state.connected) return;
    final Uri uri = Uri.parse(
        '${state.baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/classisland/report');
    try {
      await http
          .post(
            uri,
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, String>{
              'app': 'xingli_music',
              'classId': state.classId,
              'playing': playing,
              'title': title,
              'artist': artist,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // 上报失败不影响播放。
    }
  }

  /// 单例（供无 ref 的音频层直调上报；Riverpod provider 委托给它）。
  static final ClassIslandNotifier instance = ClassIslandNotifier();

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}

/// ClassIsland 联动 provider（委托单例实例，保持同一状态源；
/// 音频层可用 [ClassIslandNotifier.instance] 直接上报）。
/// 首次 watch 时自动 load（工具面板等只读页面也能拉到配置，不会永远"未连接"）。
final classislandProvider =
    StateNotifierProvider<ClassIslandNotifier, ClassIslandState>((ref) {
  final ClassIslandNotifier n = ClassIslandNotifier.instance;
  Future<void>.microtask(n.load);
  return n;
});
