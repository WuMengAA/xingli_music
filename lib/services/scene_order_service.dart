import 'dart:math';

import '../models/scene.dart';

/// 有秩序的随机感 · 场景顺序生成器
///
/// 每次打开空间，场景排列顺序都不同（由会话种子驱动），
/// 同时满足两条约束：
///  - 相邻场景保持"情绪距离"：不紧挨、也不极端跳变（欢快不挨低沉）
///  - 不出现连续三个同类场景
class SceneOrderService {
  /// 相邻场景情绪距离的下限：太近 = 两个场景没区别
  static const double minAdjacentDistance = 0.10;

  /// 相邻场景情绪距离的上限：太远 = 情绪跳变，欢快直接挨低沉
  static const double maxAdjacentDistance = 0.55;

  /// 情绪坐标（valence, energy）间的欧氏距离
  static double emotionalDistance(Scene a, Scene b) {
    final dv = a.valence - b.valence;
    final de = a.energy - b.energy;
    return sqrt(dv * dv + de * de);
  }

  /// 场景类型（按 valence 分"低沉 / 明亮"），用于避免连续同类
  static bool isBright(Scene s) => s.valence >= 0.5;

  /// 生成一组合格场景顺序（有界重试，找不到完美解就取违规最少的）
  static List<Scene> generate(
    List<Scene> universe,
    int seed, {
    int maxAttempts = 24,
  }) {
    final rng = Random(seed);

    List<Scene> best = List.of(universe)..shuffle(rng);
    int bestScore = _score(best);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final candidate = List.of(universe)..shuffle(rng);
      final s = _score(candidate);
      if (s == 0) return candidate;
      if (s < bestScore) {
        best = candidate;
        bestScore = s;
      }
    }
    return best;
  }

  /// 违规数：0 = 完全合规，越低越好
  static int _score(List<Scene> order) {
    int violations = 0;

    // 相邻情绪距离约束
    for (int i = 0; i < order.length - 1; i++) {
      final d = emotionalDistance(order[i], order[i + 1]);
      if (d < minAdjacentDistance) violations++;
      if (d > maxAdjacentDistance) violations++;
    }

    // 连续三个同类场景约束
    for (int i = 0; i <= order.length - 3; i++) {
      final a = isBright(order[i]);
      final b = isBright(order[i + 1]);
      final c = isBright(order[i + 2]);
      if (a == b && b == c) violations++;
    }

    return violations;
  }
}
