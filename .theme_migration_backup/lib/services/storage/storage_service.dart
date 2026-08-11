import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 结构化键值存储（对应规格 Module 6：SharedPreferences 键值层）
///
/// 对 [SharedPreferences] 做一层类型化封装，并额外提供 JSON 对象的读写，
/// 让"配色记忆 / 设置项"等简单持久化有统一入口，避免散落的 prefs 直读。
class StorageService {
  StorageService(this._prefs);
  final SharedPreferences _prefs;

  String? getString(String key) => _prefs.getString(key);
  Future<bool> setString(String key, String v) => _prefs.setString(key, v);

  bool? getBool(String key) => _prefs.getBool(key);
  Future<bool> setBool(String key, bool v) => _prefs.setBool(key, v);

  int? getInt(String key) => _prefs.getInt(key);
  Future<bool> setInt(String key, int v) => _prefs.setInt(key, v);

  double? getDouble(String key) => _prefs.getDouble(key);
  Future<bool> setDouble(String key, double v) => _prefs.setDouble(key, v);

  /// 读取 JSON 对象（解析失败返回 null）
  Map<String, dynamic>? getJson(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  /// 写入 JSON 对象
  Future<bool> setJson(String key, Map<String, dynamic> v) =>
      _prefs.setString(key, jsonEncode(v));

  Future<bool> remove(String key) => _prefs.remove(key);
}
