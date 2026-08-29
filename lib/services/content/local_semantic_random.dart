/// 星璃 · 本地语义随机（T4）
///
/// 与服务端 `content.random`（编辑精选）**并存**的离线替代方案：不依赖网络，
/// 基于「语义词库 + 曲目文本重合度 + 随机抖动」从本地曲库推荐曲目。
///
/// 设计要点：
/// - 每个场景 mood 映射一组语义关键词（等同义词扩展：静默→安静/冥想/钢琴…）；
/// - 曲目按「标题/歌手/专辑」与关键词的重合次数打分（查标题权重最大）；
/// - 打分后叠一层低幅随机扰动（[Random]），使同一场景每次结果不同——
///   「语义相关但不重复」，这正是区别于固定启发式的「随机」所在；
/// - 纯 Dart、无 Flutter 依赖，便于单测。
library;

import 'dart:math';

import '../../models/scene.dart';
import '../../models/track.dart';

/// 场景 mood → 语义关键词（中文氛围词 + 常见英文对应）。
///
/// 覆盖内置场景的常见 mood；未收录的 mood 回退到场景名/描述分词。
const Map<String, List<String>> kSemanticLexicon = <String, List<String>>{
  '静默': <String>['安静', '静谧', '无声', '平静', '冥想', '钢琴', 'quiet', 'calm', 'silence', 'piano', 'ambient'],
  '湿润': <String>['雨', '雨声', '水滴', '湿润', '朦胧', 'rain', 'water', 'mist', 'dew'],
  '呼吸': <String>['呼吸', '缓慢', '慢速', '放松', '飘', 'breathe', 'slow', 'relax', 'drift'],
  '温暖': <String>['温暖', '阳光', '治愈', '舒适', '暖', 'warm', 'sun', 'cozy', 'heal', 'soft'],
  '余晖': <String>['黄昏', '日落', '余晖', '晚霞', '暮色', 'dusk', 'sunset', 'glow', 'evening'],
  '寂静': <String>['深夜', '夜', '星', '月光', '孤', 'night', 'midnight', 'moon', 'star', 'lonely'],
  '深邃': <String>['深邃', '深空', '宇宙', '空间', '神秘', 'deep', 'space', 'cosmos', 'mystery'],
  '欢快': <String>['欢快', '活泼', '轻快', '明亮', '舞', 'happy', 'cheerful', 'bright', 'jazz', 'dance'],
  '悠扬': <String>['悠扬', '绵长', '旋律', '悠远', 'melody', 'flow', 'ethereal'],
  '激情': <String>['激情', '激昂', '摇滚', '强烈', 'power', 'rock', 'intense', 'epic'],
};

/// 语义随机推荐器。
class LocalSemanticRandom {
  const LocalSemanticRandom();

  /// 从 [all] 中按场景 [scene] 语义推荐 [count] 首。
  ///
  /// [seed] 可注入固定随机源（测试用）；缺省用真随机，每次结果不同。
  List<Track> recommend(
    List<Track> all,
    Scene scene, {
    int count = 30,
    Random? seed,
  }) {
    if (all.isEmpty) return const <Track>[];
    final Random rng = seed ?? Random();
    final List<String> keywords = _keywordsFor(scene);

    // ▢ 1. 逐曲打分：语义命中 + 随机抖动（±2，拉开同分曲目差异）。
    final List<(Track, int)> scored = all
        .map((Track t) => (t, _score(t, keywords) + rng.nextInt(5) - 2))
        .toList(growable: false);

    // ▢ 2. 按分数降序；同分保持原相对顺序（稳定排序）。
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    // ▢ 3. 满分为 0 说明词库没命中任何曲目 → 退化为纯随机洗牌，
    //     保证「随机」语义始终成立（而不是永远返回同一批）。
    final bool anyHit = scored.any((s) => s.$2 > 2);
    if (!anyHit) {
      scored.shuffle(rng);
    }
    return scored.take(count).map((s) => s.$1).toList(growable: false);
  }

  /// 场景 → 关键词：先取 mood 词库，再并入场景名/描述里的中文词。
  List<String> _keywordsFor(Scene scene) {
    final List<String> kws = <String>[
      ...?kSemanticLexicon[scene.mood],
    ];
    // 场景名/描述按 2-4 字滑动切词（简单中文分词，够用即可）。
    final String text = '${scene.name}${scene.desc}';
    for (int i = 0; i + 2 <= text.length; i++) {
      final String piece = text.substring(i, i + 2);
      if (RegExp(r'[\u4e00-\u9fff]').hasMatch(piece)) kws.add(piece);
    }
    return kws.where((String k) => k.isNotEmpty).toSet().toList(growable: false);
  }

  /// 单曲与关键词集合的重合得分：标题命中 ×2、歌手 ×1、专辑 ×1。
  int _score(Track t, List<String> keywords) {
    if (keywords.isEmpty) return 0;
    int s = 0;
    final String title = t.title.toLowerCase();
    final String artist = t.artist.toLowerCase();
    final String album = (t.album ?? '').toLowerCase();
    for (final String k in keywords) {
      final String kw = k.toLowerCase();
      if (title.contains(kw)) s += 2;
      if (artist.contains(kw)) s += 1;
      if (album.contains(kw)) s += 1;
    }
    return s;
  }
}