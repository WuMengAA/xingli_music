import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_compat/liquid_glass_compat.dart';

void main() {
  group('spring physics', () {
    test('临界阻尼：单调趋近无超调', () {
      final s = SpringCritical1D(value: 0, omegaN: kToggleValueOmegaN);
      var max = 0.0;
      var prev = 0.0;
      for (var i = 0; i < 120; i++) {
        s.step(1.0, 1 / 60);
        expect(s.value, greaterThanOrEqualTo(prev - 1e-9),
            reason: '临界阻尼不得回退（超调）');
        prev = s.value;
        if (s.value > max) max = s.value;
      }
      expect(max, lessThanOrEqualTo(1.0001), reason: '临界阻尼不应超过目标');
      expect(s.value, closeTo(1.0, 0.01));
    });

    test('欠阻尼：有超调且振荡收敛', () {
      final s = Spring1D(value: 0);
      var overshot = false;
      for (var i = 0; i < 240; i++) {
        s.step(1.0, 1 / 60);
        if (s.value > 1.0) overshot = true;
      }
      expect(overshot, isTrue, reason: '欠阻尼应越过目标');
      expect(s.value, closeTo(1.0, 0.02));
      expect(s.velocity.abs(), lessThan(0.05), reason: '收敛后速度衰减');
    });

    test('数值闭式解与解析式一致（x0=0, v0=0 → 目标定向）', () {
      final r = springStepUnderdamped(0.0, 0.0, 1.0, 0.0);
      expect(r.value, closeTo(0.0, 1e-9));
      expect(r.velocity, closeTo(0.0, 1e-9));
    });

    test('阈值：临近目标但仍有速度 → 仍运动；静止后 step 返回 false', () {
      // 0.999 距目标 0.001 < 0.003，但第一步仍获得速度 → 仍算运动。
      final s = SpringCritical1D(value: 0.999, velocity: 0);
      var moving = s.step(1.0, 1 / 60);
      expect(moving, isTrue,
          reason: '靠近目标但速度未衰减完时不应判静止');
      // 持续推进直到静止：126 步（2.1s）内必然收敛。
      var steps = 1;
      var settled = false;
      for (; steps < 600; steps++) {
        if (!s.step(1.0, 1 / 60)) {
          settled = true;
          break;
        }
      }
      expect(settled, isTrue, reason: '临界阻尼应在有限步内静止');
      expect(steps, lessThan(200));
      expect(s.value, closeTo(1.0, kSpringThreshold + 1e-6));
      // 静止后继续 step 保持 false。
      expect(s.step(1.0, 1 / 60), isFalse);
    });
  });
}