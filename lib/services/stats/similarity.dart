/// 自动收录机制的相似度工具（cl46）。
///
/// 判定两首歌「是否同一首」：歌手需完全一致（归一化后），且歌名相似度
/// 超过阈值（容忍 `(Live)`、`伴奏`、空格、全角等变体）。
library;

import '../../models/track_stats.dart';

/// 歌名相似度阈值（0~1）：归一化后编辑距离占比。
const double kTitleSimilarityThreshold = 0.7;

/// 归一化歌名：小写、去空白与标点、全角转半角。
String normalizeTitle(String s) {
  final StringBuffer sb = StringBuffer();
  for (final int code in s.toLowerCase().codeUnits) {
    // 保留中文/字母/数字，剔除空白与标点。
    final bool keep = (code >= 0x30 && code <= 0x39) || // 0-9
        (code >= 0x61 && code <= 0x7a) || // a-z
        (code >= 0x4e00 && code <= 0x9fff); // CJK
    if (keep) sb.writeCharCode(code);
  }
  return sb.toString();
}

/// 归一化歌手：与歌名一致，但歌手还可能包含「feat.」「×」等，仅保留主体。
String normalizeArtist(String s) {
  final String a = s
      .split(RegExp(r'feat\.?|ft\.?|×|,|、|/'))
      .first
      .trim()
      .toLowerCase();
  return a;
}

/// 编辑距离（Levenshtein），O(n×m)。
int levenshtein(String a, String b) {
  if (a == b) return 0;
  final List<int> prev =
      List<int>.generate(b.length + 1, (int i) => i);
  final List<int> cur = List<int>.filled(b.length + 1, 0);
  for (int i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (int j = 1; j <= b.length; j++) {
      final int cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = _min3(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
    }
    for (int j = 0; j <= b.length; j++) {
      prev[j] = cur[j];
    }
  }
  return cur[b.length];
}

int _min3(int a, int b, int c) => a < b ? (a < c ? a : c) : (b < c ? b : c);

/// 归一化后歌名相似度（0~1）。
double titleSimilarity(String a, String b) {
  final String na = normalizeTitle(a);
  final String nb = normalizeTitle(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;
  final int d = levenshtein(na, nb);
  final int maxLen = na.length > nb.length ? na.length : nb.length;
  return 1 - d / maxLen;
}

/// 两首曲目是否「候选同一首」：歌手（归一化后）完全一致，且歌名相似度过阈值。
bool isSimilarCandidate(String titleA, String artistA,
    String titleB, String artistB) {
  final String na = normalizeArtist(artistA);
  final String nb = normalizeArtist(artistB);
  // 歌手至少有一方非空时才要求歌手匹配；双方都空则仅看歌名。
  final bool artistOk =
      na.isEmpty && nb.isEmpty ? true : na == nb;
  if (!artistOk) return false;
  final double sim = titleSimilarity(titleA, titleB);
  if (sim < kTitleSimilarityThreshold) return false;
  // 完全相同不算候选（已被 trackKey 精确归并覆盖）。
  return normalizeTitle(titleA) != normalizeTitle(titleB);
}

/// 用 [ListenEntry] 与已收录 [TrackStats] 判断是否为归并候选。
bool isSimilarEntry(ListenEntry entry, TrackStats stats) =>
    isSimilarCandidate(entry.title, entry.artist, stats.title, stats.artist);
