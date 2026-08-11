import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 使用行为结构化存储（对应规格 Module 6：sqflite 结构化层）
///
/// 用于"习惯性交互"：不打扰用户，仅在使用行为发生时自然记录
/// （如场景驻留、配色选择），为配色记忆 / 意境推荐提供数据。
class UsageRepository {
  UsageRepository(this._db);
  final Database _db;

  static const String _table = 'usage_events';

  /// 打开（或新建）数据库并建立表结构
  static Future<Database> open() async {
    final String path = p.join(await getDatabasesPath(), 'stellara_usage.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            payload TEXT,
            ts INTEGER NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_usage_events_type ON $_table(type)');
      },
    );
  }

  /// 记录一次使用行为事件
  Future<void> logEvent({
    required String type,
    required Map<String, dynamic> payload,
    DateTime? at,
  }) async {
    await _db.insert(_table, {
      'type': type,
      'payload': jsonEncode(payload),
      'ts': (at ?? DateTime.now()).millisecondsSinceEpoch,
    });
  }

  /// 读取某类型最近的事件（按时间倒序）
  Future<List<Map<String, dynamic>>> recent({
    required String type,
    int limit = 50,
  }) async {
    final List<Map<String, dynamic>> rows = await _db.query(
      _table,
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'ts DESC',
      limit: limit,
    );
    return rows.map((r) {
      final String? raw = r['payload'] as String?;
      return <String, dynamic>{
        'id': r['id'],
        'type': r['type'],
        'ts': r['ts'],
        'payload': raw == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(raw) as Map),
      };
    }).toList();
  }

  /// 清空（可指定类型，默认全部）
  Future<int> clear({String? type}) {
    if (type == null) return _db.delete(_table);
    return _db.delete(_table, where: 'type = ?', whereArgs: [type]);
  }
}
