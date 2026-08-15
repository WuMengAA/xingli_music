/// 全局播放统计 / 收藏 / 歌单 / 听歌历史 的 Riverpod 层（cl46）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../services/audio/audio_service.dart';
import '../../services/stats/similarity.dart';
import '../../services/stats/track_stats_db.dart';
import '../audio/audio_providers.dart';

/// 单曲计次阈值：播放超过该时长才算「一次播放」（避免误触/秒进即退）。
const int kCountPlayMinMs = 10000;

/// 结算落盘间隔：每 30 秒把累积播放时长写一次（防进程被杀丢失）。
const Duration kSettleInterval = Duration(seconds: 30);

/// 数据库单例。
final trackStatsDbProvider =
    Provider<TrackStatsDb>((Ref ref) => TrackStatsDb.instance);

/// 全部播放统计（排行）。
final playStatsProvider = FutureProvider<List<TrackStats>>(
  (Ref ref) => ref.watch(trackStatsDbProvider).allStats(),
);

/// 最近听歌历史（倒序，默认 100 条），供曲库「时光沉底」页展示（#421）。
final recentHistoryProvider = FutureProvider<List<ListenEntry>>(
  (Ref ref) => ref.watch(trackStatsDbProvider).recentHistory(limit: 100),
);

/// 播放统计 map（trackKey → stats），供卡片批量展示（避免逐卡查库）。
final statsMapProvider = FutureProvider<Map<String, TrackStats>>(
  (Ref ref) async {
    final List<TrackStats> all = await ref.watch(playStatsProvider.future);
    return <String, TrackStats>{
      for (final TrackStats s in all) s.trackKey: s,
    };
  },
);

/// 全局听歌总时长（毫秒）。
final totalPlayMsProvider = FutureProvider<int>(
  (Ref ref) => ref.watch(trackStatsDbProvider).totalPlayMs(),
);

/// 单曲统计（按 trackKey）。
final statOfProvider = FutureProvider.family<TrackStats?, String>(
  (Ref ref, String key) => ref.watch(trackStatsDbProvider).statOf(key),
);

/// 全局收藏列表。
final favoritesProvider = FutureProvider<List<FavoriteEntry>>(
  (Ref ref) => ref.watch(trackStatsDbProvider).favorites(),
);

/// 单曲是否已收藏。
final isFavoriteProvider = FutureProvider.family<bool, String>(
  (Ref ref, String key) async {
    final TrackStatsDb db = ref.watch(trackStatsDbProvider);
    final String canonical = await db.canonicalKey(await db.database, key);
    return db.isFavorite(canonical);
  },
);

/// 全局歌单列表。
final playlistsProvider = FutureProvider<List<Playlist>>(
  (Ref ref) => ref.watch(trackStatsDbProvider).playlists(),
);

/// 歌单内曲目（按歌单排序方式）。
final playlistTracksProvider =
    FutureProvider.family<List<PlaylistTrack>, int>(
  (Ref ref, int id) async {
    final TrackStatsDb db = ref.watch(trackStatsDbProvider);
    final List<Playlist> all = await db.playlists();
    final Playlist? pl =
        all.where((Playlist p) => p.id == id).firstOrNull;
    return db.playlistTracks(id, sortMode: pl?.sortMode ?? PlaylistSortMode.manual);
  },
);

/// 刷新全局数据（收藏 / 歌单 / 统计失效）。
void refreshTrackStats(WidgetRef ref) {
  ref.invalidate(playStatsProvider);
  ref.invalidate(totalPlayMsProvider);
  ref.invalidate(favoritesProvider);
  ref.invalidate(playlistsProvider);
}

// ════════════════════════════════════════════════════════════════════════
// 播放统计跟踪器：监听音频服务的切歌 / 播放状态 / 进度，自动落盘。
// ════════════════════════════════════════════════════════════════════════

class PlayStatsTracker {
  PlayStatsTracker(this._ref);

  final Ref _ref;

  Track? _current;
  int _accumMs = 0;
  int? _lastPosMs;
  Timer? _timer;
  StreamSubscription<Track?>? _trackSub;
  StreamSubscription<bool>? _stateSub;
  StreamSubscription<Duration?>? _posSub;
  TrackStatsDb? _db;

  /// 由 [trackStatsTrackerProvider] 在首次 watch 时调用。
  void start() {
    if (_started) return;
    _started = true;
    // 保存实例：dispose 时容器已销毁，不能再用 _ref.read 访问 provider。
    _db = _ref.read(trackStatsDbProvider);
    final AudioService audio = _ref.read(audioServiceProvider);
    _trackSub = audio.trackStream.listen(_onTrack);
    _stateSub = audio.playingStream.listen(_onPlaying);
    _posSub = audio.positionStream.listen(_onPos);
    _timer = Timer.periodic(kSettleInterval, (_) => _settle());
  }

  bool _started = false;

  void _onTrack(Track? t) {
    _settle();
    _current = t;
    _accumMs = 0;
    _lastPosMs = null;
  }

  void _onPlaying(bool playing) {
    if (!playing) {
      _settle();
      _lastPosMs = null;
    }
  }

  void _onPos(Duration? pos) {
    if (pos == null) {
      _lastPosMs = null;
      return;
    }
    final int ms = pos.inMilliseconds;
    final int? last = _lastPosMs;
    _lastPosMs = ms;
    if (last == null) return;
    final int delta = ms - last;
    // 只累计顺滑前进（<3s），排除 seek / 切歌跳变。
    if (delta > 0 && delta < 3000) {
      _accumMs += delta;
    }
  }

  /// 结算当前曲：写统计 + 历史（重复调用安全：结算后清零累积）。
  Future<void> _settle() async {
    final Track? t = _current;
    final int ms = _accumMs;
    _accumMs = 0;
    if (t == null || ms <= 0) return;
    // dispose 后容器已销毁，不能再用 _ref.read/_ref.invalidate。
    final TrackStatsDb? db = _db;
    if (db == null) return;
    final String key = trackKeyOf(t.title, t.artist, t.sourceId);
    try {
      if (ms >= kCountPlayMinMs) {
        await db.addPlay(key, t.title, t.artist, t.sourceId, ms);
        if (!_disposed) {
          _ref.invalidate(playStatsProvider);
          _ref.invalidate(totalPlayMsProvider);
        }
      }
      // 历史无论长短都记录（自动收录数据源）。
      await db.addHistory(key, t.title, t.artist, t.sourceId, ms);
      if (!_disposed) _ref.invalidate(statOfProvider(key));
      // 历史列表（曲库「时光沉底」页）随每次结算刷新。
      if (!_disposed) _ref.invalidate(recentHistoryProvider);
    } catch (_) {
      // 写库失败不阻断播放（统计是附属能力）。
    }
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    try {
      unawaited(_settle());
    } catch (_) {}
    _trackSub?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _timer?.cancel();
  }
}

/// 播放统计跟踪器（App 启动处 watch 一次即开始记录）。
final trackStatsTrackerProvider = Provider<PlayStatsTracker>(
  (Ref ref) {
    final PlayStatsTracker t = PlayStatsTracker(ref);
    t.start();
    ref.onDispose(t.dispose);
    return t;
  },
);

/// 收藏切换（返回新的收藏状态）。
Future<bool> toggleFavoriteTrack(WidgetRef ref, Track track) async {
  final TrackStatsDb db = ref.read(trackStatsDbProvider);
  final String key = trackKeyOf(track.title, track.artist, track.sourceId);
  await db.toggleFavorite(key, track.title, track.artist, track.sourceId,
      track.coverUrl ?? track.coverPath);
  ref.invalidate(favoritesProvider);
  ref.invalidate(isFavoriteProvider(key));
  return db.isFavorite(key);
}

// ════════════════════════════════════════════════════════════════════════
// 自动收录：相似归并候选（听歌历史 vs 已收录主条目）
// ════════════════════════════════════════════════════════════════════════

/// 待用户确认的归并候选（无则为 null）。每次调用扫描最近历史，
/// 找到第一个「歌手一致 + 歌名相似但不同」的候选即返回。
final pendingMergeCandidateProvider =
    FutureProvider<MergeCandidate?>((Ref ref) async {
  final TrackStatsDb db = ref.watch(trackStatsDbProvider);
  final Database dbc = await db.database;
  final List<ListenEntry> history = await db.recentHistory(limit: 200);
  final List<TrackStats> stats = await db.allStats();
  if (stats.isEmpty) return null;
  for (final ListenEntry entry in history) {
    final String canonical = await db.canonicalKey(dbc, entry.trackKey);
    if (canonical != entry.trackKey) continue; // 已归并过
    if (await db.isMergeDismissed(entry.trackKey)) continue; // 用户已跳过
    for (final TrackStats s in stats) {
      if (s.trackKey == entry.trackKey) continue;
      if (isSimilarEntry(entry, s)) {
        return MergeCandidate(source: entry, canonical: s);
      }
    }
  }
  return null;
});

/// 确认归并：source 归并到 canonical（写入别名）+ 歌单联动。
Future<void> confirmMerge(WidgetRef ref, MergeCandidate c) async {
  final TrackStatsDb db = ref.read(trackStatsDbProvider);
  await db.addAlias(c.source.trackKey, c.canonical.trackKey);
  // 歌单联动：canonical 在哪些歌单，source 也加入同样的歌单。
  final List<Playlist> pls = await db.playlists();
  for (final Playlist pl in pls) {
    final List<PlaylistTrack> tracks =
        await db.playlistTracks(pl.id ?? -1);
    if (tracks.any((PlaylistTrack t) => t.trackKey == c.canonical.trackKey)) {
      await db.addToPlaylist(pl.id ?? -1, c.source.trackKey, c.source.title,
          c.source.artist, c.source.sourceId);
      ref.invalidate(playlistTracksProvider(pl.id ?? -1));
    }
  }
  ref.invalidate(pendingMergeCandidateProvider);
  refreshTrackStats(ref);
}

/// 用户选择「跳过」：记录 dismissed，不再就这首反复询问。
Future<void> dismissMergeCandidate(WidgetRef ref, MergeCandidate c) async {
  final TrackStatsDb db = ref.read(trackStatsDbProvider);
  await db.dismissMerge(c.source.trackKey);
  ref.invalidate(pendingMergeCandidateProvider);
}
