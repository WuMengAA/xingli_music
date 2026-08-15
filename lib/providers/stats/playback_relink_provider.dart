/// 重播直链重匹配（cl51-A）。
///
/// 「再次播放则搜索近似链接、失效则搜索近似名称、时长、歌手，自动匹配」：
/// 播放某曲前，把「只带占位符 / 仅元数据」的 [Track] 重匹配为一首
/// **可直接播放**的直链曲目，优先级：
///
/// 1. 已是 http(s) 直链 → 原样返回（无需处理）；
/// 2. 命中 `resolved_links` 缓存且未过期 → 直接用上次解析出的直链
///    （再次播放走近似链接，更快、更省流量）；
/// 3. 缓存缺失/过期 → 调该曲来源 `resolveStreamUrl` 重新解析，
///    成功则写回缓存并返回直链；
/// 4. 源解析失败 / 源不可用 → 聚合搜索（网易云 + B站），按
///    **近似名称 + 时长 + 歌手** 自动匹配最优曲目（并尽力解析成直链）。
///
/// 匹配到替代曲目时视为「自动匹配成功」返回；全部失败则回退原曲，
/// 由上层走既有播放错误提示（不静默吞错）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../services/music_sources/music_source.dart';
import '../../services/stats/track_stats_db.dart';
import '../audio/audio_providers.dart';
import '../sources/bilibili_provider.dart';
import '../sources/netease_provider.dart';
import 'track_stats_providers.dart';

/// 按播放记录推导的播放顺序（最近播放在前、去重）。
///
/// 供上下歌切换使用：顺序 / 倒序模式下，下一首按「播放记录」走而不是
/// 字母序，满足「默认播放下一首按播放记录」。可后续叠加手动排序。
final recordPlayOrderProvider = FutureProvider<List<String>>((Ref ref) async {
  final List<ListenEntry> history =
      await ref.watch(recentHistoryProvider.future);
  final List<String> order = <String>[];
  final Set<String> seen = <String>{};
  // 历史已按 played_at 倒序，遍历即得「最近→最早」。
  for (final ListenEntry e in history) {
    if (seen.add(e.trackKey)) order.add(e.trackKey);
  }
  return order;
});

/// 重播直链重匹配入口：返回一首可直接播放的 [Track]。
Future<Track> relinkForPlayback(Ref ref, Track track) async {
  // 1) 已是直链 → 无需处理。
  if (track.uri.startsWith('http')) return track;

  final TrackStatsDb db = ref.read(trackStatsDbProvider);
  final String key = trackKeyOf(track.title, track.artist, track.sourceId);

  // 2) 缓存未过期 → 直接用上次解析出的直链。
  final ResolvedLink? cached = await db.resolvedLinkOf(key);
  if (cached != null && !cached.isExpired && cached.url.startsWith('http')) {
    return track.copyWith(uri: cached.url);
  }

  // 3) 源重新解析（按 sourceId 反查源）。
  final Track? bySource = await _resolveFromSource(ref, track);
  if (bySource != null) {
    await db.saveResolvedLink(key, bySource.uri,
        expireAtMs: _expireAtFor(track.sourceId));
    return bySource;
  }

  // 4) 聚合搜索自动匹配（名称 / 时长 / 歌手）。
  final Track? matched = await _aggregateMatch(ref, track);
  if (matched != null) {
    final Track? resolved = await _resolveFromSource(ref, matched);
    final Track finalTrack =
        resolved ?? (matched.uri.startsWith('http') ? matched : matched);
    if (finalTrack.uri.startsWith('http')) {
      await db.saveResolvedLink(key, finalTrack.uri,
          expireAtMs: _expireAtFor(matched.sourceId));
    }
    return finalTrack;
  }

  return track;
}

/// 直链缓存过期时间：有签名 TTL 的源按源 TTL（网易云 20 分钟），
/// 其余源直链稳定 → 永不过期（0）。
int _expireAtFor(String sourceId) {
  final DateTime now = DateTime.now();
  switch (sourceId) {
    case 'netease':
      return now.add(const Duration(minutes: 20)).millisecondsSinceEpoch;
    case 'bilibili':
      return now.add(const Duration(minutes: 20)).millisecondsSinceEpoch;
    default:
      return 0;
  }
}

/// 按 sourceId 反查源并解析直链；失败/源缺失返回 null。
Future<Track?> _resolveFromSource(Ref ref, Track track) async {
  if (track.uri.startsWith('http')) return track;
  for (final MusicSource s in ref.read(activeSourcesProvider)) {
    if (s.sourceId != track.sourceId) continue;
    try {
      final String url = await s.resolveStreamUrl(track);
      if (url.startsWith('http')) return track.copyWith(uri: url);
    } catch (_) {
      // 解析失败继续尝试下一逻辑（聚合搜索兜底）。
    }
    break; // 已匹配到源：无论成败都不再尝试其它源。
  }
  return null;
}

/// 聚合搜索自动匹配：网易云 + B站按名称搜索，再按 时长/歌手 打分取最优。
///
/// 返回 null 表示未找到可信匹配（交给上层回退原曲/报错）。
Future<Track?> _aggregateMatch(Ref ref, Track target) async {
  final List<Track> candidates = <Track>[];
  final String q = target.title.trim();
  if (q.isEmpty) return null;

  // 网易云（未登录返回空，不打接口）。
  try {
    final List<Track> ne =
        await ref.read(neteaseSearchProvider(q).future).catchError((_) => const <Track>[]);
    candidates.addAll(ne);
  } catch (_) {}
  // B站。
  try {
    final List<Track> bi =
        await ref.read(bilibiliSearchProvider(q).future).catchError((_) => const <Track>[]);
    candidates.addAll(bi);
  } catch (_) {}

  if (candidates.isEmpty) return null;

  // 打分：名称相似（核心）> 歌手一致 > 时长接近。
  final String nTitle = _normalize(target.title);
  final String nArtist = _normalize(target.artist);
  final int? targetMs = target.duration?.inMilliseconds;

  Track? best;
  double bestScore = 0;
  for (final Track c in candidates) {
    double s = _titleScore(nTitle, _normalize(c.title));
    if (s <= 0) continue; // 名称完全不相似，直接排除。
    if (nArtist.isNotEmpty &&
        (_normalize(c.artist) == nArtist ||
            _normalize(c.artist).contains(nArtist))) {
      s += 2.0;
    }
    final int? cMs = c.duration?.inMilliseconds;
    if (targetMs != null && cMs != null) {
      final int diff = (cMs - targetMs).abs();
      if (diff < 5000) {
        s += 1.5;
      } else if (diff < 15000) {
        s += 0.8;
      } else if (diff < 30000) {
        s += 0.3;
      }
    }
    if (s > bestScore) {
      bestScore = s;
      best = c;
    }
  }
  return bestScore >= 2.0 ? best : null;
}

/// 名称相似度：完全相等 1.0；一方包含另一方按长度比例；否则 0。
double _titleScore(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1.0;
  if (a.contains(b) || b.contains(a)) {
    final int shorter = a.length < b.length ? a.length : b.length;
    final int longer = a.length < b.length ? b.length : a.length;
    return 0.5 + 0.5 * (shorter / longer);
  }
  return 0;
}

/// 名称/歌手归一化：小写、去空白与常见标点。
String _normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\-_（）()\[\]【】、，。.!！?？:：/\\·~～&+]+'), '');
