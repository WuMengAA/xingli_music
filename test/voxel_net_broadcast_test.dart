/// 联机广播节流（cl79）· shouldBroadcastTransform 阈值矩阵单测。
///
/// 纯 Dart，不碰网络/引擎。覆盖：首次必发、静止不发、微动不发、
/// 越阈值必发、yaw 环绕（359°→0° 只差 1°）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/widgets/voxel/voxel_net_broadcast.dart';

void main() {
  group('shouldBroadcastTransform', () {
    test('首次（prev 为 null）必发', () {
      expect(
        shouldBroadcastTransform(null, null, null, null, null, 1, 2, 3, 0, 0),
        isTrue,
      );
    });

    test('完全静止不发', () {
      expect(
        shouldBroadcastTransform(1, 2, 3, 0.0, 0.0, 1, 2, 3, 0.0, 0.0),
        isFalse,
      );
    });

    test('微动（位移 ≤0.1m、视角 ≤1°）不发', () {
      // 位移 0.1m 正好在阈值上（>0.1 才发）→ 不发。
      expect(
        shouldBroadcastTransform(0, 0, 0, 0.0, 0.0, 0.1, 0, 0, 0.0, 0.0),
        isFalse,
      );
      // 视角 1° 在阈值上 → 不发。
      expect(
        shouldBroadcastTransform(0, 0, 0, 0.0, 0.0, 0, 0, 0, 1.0, 0.0),
        isFalse,
      );
    });

    test('位移超阈值必发', () {
      expect(
        shouldBroadcastTransform(0, 0, 0, 0.0, 0.0, 0.15, 0, 0, 0.0, 0.0),
        isTrue,
      );
      // 斜向位移，合位移 >0.1。
      expect(
        shouldBroadcastTransform(0, 0, 0, 0.0, 0.0, 0.08, 0, 0.08, 0.0, 0.0),
        isTrue,
      );
    });

    test('视角变化超阈值必发（yaw / pitch）', () {
      expect(
        shouldBroadcastTransform(0, 0, 0, 0.0, 0.0, 0, 0, 0, 1.5, 0.0),
        isTrue,
      );
      expect(
        shouldBroadcastTransform(0, 0, 0, 0.0, 0.0, 0, 0, 0, 0.0, 2.0),
        isTrue,
      );
    });

    test('yaw 环绕：359°→0° 只差 1°，不触发', () {
      expect(
        shouldBroadcastTransform(0, 0, 0, 359.0, 0.0, 0, 0, 0, 0.0, 0.0),
        isFalse,
      );
      // 359°→358°（1°）也不触发。
      expect(
        shouldBroadcastTransform(0, 0, 0, 359.0, 0.0, 0, 0, 0, 358.0, 0.0),
        isFalse,
      );
      // 359°→357°（2°）触发。
      expect(
        shouldBroadcastTransform(0, 0, 0, 359.0, 0.0, 0, 0, 0, 357.0, 0.0),
        isTrue,
      );
    });

    test('自定义阈值生效', () {
      // 位移 0.5m 但阈值放宽到 1.0 → 不发。
      expect(
        shouldBroadcastTransform(0, 0, 0, 0.0, 0.0, 0.5, 0, 0, 0.0, 0.0,
            moveThreshold: 1.0),
        isFalse,
      );
      // 视角 3° 但阈值放宽到 5° → 不发。
      expect(
        shouldBroadcastTransform(0, 0, 0, 0.0, 0.0, 0, 0, 0, 3.0, 0.0,
            angleThreshold: 5.0),
        isFalse,
      );
    });
  });
}
