/// ════════════════════════════════════════════════════════════════════════
/// 电台历史记录：持久化的已播记录。
///
/// orderQueue 中的 played 项在退房时会被清空，因此单独持久化一条只增列表
/// 到 SharedPreferences，供「已播历史」与「直播间统计」使用。
///
/// 数据结构：时间戳 + Track（title/artist/uri）+ 点歌来源（DJ 自选/听众点歌）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/track.dart';

/// 单条已播记录。
class PlayedRecord {
  const PlayedRecord({
    required this.id,
    required this.track,
    required this.fromName,
    required this.source,
    required this.at,
  });
  final String id;
  final Track track;
  final String fromName;
  final String source; // 'dj' | 'listener'
  final DateTime at;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': track.title,
        'artist': track.artist,
        'uri': track.uri,
        'sourceId': track.sourceId,
        'fromName': fromName,
        'source': source,
        'at': at.millisecondsSinceEpoch,
      };

  factory PlayedRecord.fromJson(Map<String, dynamic> j) => PlayedRecord(
        id: j['id'] as String,
        track: Track(
          title: j['title'] as String,
          artist: j['artist'] as String? ?? '',
          uri: j['uri'] as String? ?? '',
          sourceId: j['sourceId'] as String? ?? '',
        ),
        fromName: j['fromName'] as String? ?? '',
        source: j['source'] as String? ?? 'listener',
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}

class _RadioHistoryNotifier extends StateNotifier<List<PlayedRecord>> {
  _RadioHistoryNotifier() : super(const <PlayedRecord>[]);

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('radio_played_records');
    if (raw == null) return;
    try {
      final List<dynamic> arr =
          jsonDecode(raw) as List<dynamic>;
      state = <PlayedRecord>[
        for (final dynamic it in arr)
          PlayedRecord.fromJson(it as Map<String, dynamic>),
      ];
    } on Exception {
      state = const <PlayedRecord>[];
    }
  }

  /// 追加一条已播记录并持久化；仅保留最近 100 条。
  Future<void> add(PlayedRecord r) async {
    state = <PlayedRecord>[r, ...state].take(100).toList();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'radio_played_records',
      jsonEncode(<Map<String, dynamic>>[
        for (final PlayedRecord it in state) it.toJson(),
      ]),
    );
  }
}

final radioHistoryProvider =
    StateNotifierProvider<_RadioHistoryNotifier, List<PlayedRecord>>(
  (ref) => _RadioHistoryNotifier(),
);