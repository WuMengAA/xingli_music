/// ════════════════════════════════════════════════════════════════════════
/// 生存状态：生命 / 饥饿 / 经验（R23w · GDD §3.3 / Phase 4）
/// ════════════════════════════════════════════════════════════════════════
///
/// 规则参考 MC 但做了简化，保证"能感知到、但不折磨人"：
/// - 生命 0~20（10 颗心）。
/// - 饥饿 0~20（10 个鸡腿）+ 饱和度（隐藏层，先扣饱和再扣饥饿）。
/// - 疲劳值随移动累积，每满 4.0 扣 1 点饱和/饥饿。
/// - 饥饿 ≥ 18 且未满血 → 缓慢回血（消耗饱和度）。
/// - 饥饿 = 0 → 持续掉血（最低留 1 血，不至于饿死得莫名其妙）。
/// - 经验：击杀 / 采矿获得，按 `7 + 2×等级` 升级。
///
/// 纯 Dart + [ChangeNotifier]，可单测。
library;

import 'package:flutter/foundation.dart';

import 'voxel_items.dart';
import 'voxel_world_types.dart';

/// 玩家生存状态。
class PlayerVitals extends ChangeNotifier {
  PlayerVitals();

  static const int maxHp = 20;
  static const int maxHunger = 20;

  int _hp = maxHp;
  int _hunger = maxHunger;
  double _saturation = 5;
  double _exhaustion = 0;
  int _xp = 0;
  int _level = 0;

  /// 护甲防护点数（0~20，由装备系统写入；伤害按比例减免）。
  int _armorPoints = 0;

  int get armorPoints => _armorPoints;

  /// 设置护甲防护点数（数据驱动，由装备系统调用）。
  void setArmorPoints(int p) {
    final int v = p.clamp(0, 20);
    if (v == _armorPoints) return;
    _armorPoints = v;
    notifyListeners();
  }

  /// 回血 / 掉血计时器（秒）。
  double _regenTimer = 0;

  int get hp => _hp;
  int get hunger => _hunger;
  double get saturation => _saturation;
  int get xp => _xp;
  int get level => _level;

  bool get isDead => _hp <= 0;

  /// 升到下一级还需要的经验。
  int get xpToNext => 7 + _level * 2;

  /// 当前等级进度 0~1。
  double get xpProgress => (_xp / xpToNext).clamp(0.0, 1.0);

  /// 每秒推进。[moved] 为本帧水平移动距离（格），[sprinting] 冲刺加倍消耗。
  void tick(double dt, {double moved = 0, bool sprinting = false}) {
    if (dt <= 0) return;
    bool changed = false;

    // 疲劳：走路 0.02/格、冲刺 0.10/格，基础代谢 0.015/秒。
    // R28：原公式（0.01/格 + 0.005/秒）下饱和度 5 要约 14 小时才掉 1 格，
    // 实际「饥饿值永不下降」。提速约 4~8×：步行满饥饿约 8~10 分钟掉光，
    // 冲刺更快——「能感知到、但不折磨人」。
    final double add =
        moved * (sprinting ? 0.10 : 0.02) + dt * 0.015;
    if (add > 0) {
      _exhaustion += add;
      while (_exhaustion >= 4.0) {
        _exhaustion -= 4.0;
        if (_saturation > 0) {
          _saturation = (_saturation - 1).clamp(0.0, 20.0);
        } else if (_hunger > 0) {
          _hunger--;
          changed = true;
        }
      }
    }

    // 回血 / 饿伤。
    _regenTimer += dt;
    if (_regenTimer >= 4.0) {
      _regenTimer = 0;
      if (_hunger >= 18 && _hp < maxHp) {
        _hp++;
        _saturation = (_saturation - 0.6).clamp(0.0, 20.0);
        _exhaustion += 1.0;
        changed = true;
      } else if (_hunger == 0 && _hp > 1) {
        _hp--;
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  /// 受伤（先经护甲减免，再扣血）。
  void damage(int d) {
    if (d <= 0 || _hp <= 0) return;
    final int mitigated = mitigateDamage(d, _armorPoints);
    _hp = (_hp - mitigated).clamp(0, maxHp);
    notifyListeners();
  }

  /// 治疗。
  void heal(int h) {
    if (h <= 0) return;
    final int v = (_hp + h).clamp(0, maxHp);
    if (v == _hp) return;
    _hp = v;
    notifyListeners();
  }

  /// 进食：回复饥饿 + 饱和度。返回是否吃下去了（已经饱了就不浪费）。
  bool eat(Voxel food) {
    final int v = foodValue(food);
    if (v <= 0) return false;
    if (_hunger >= maxHunger) return false;
    _hunger = (_hunger + v).clamp(0, maxHunger);
    _saturation = (_saturation + v * 0.6).clamp(0.0, _hunger.toDouble());
    notifyListeners();
    return true;
  }

  /// 获得经验（自动升级）。
  void addXp(int amount) {
    if (amount <= 0) return;
    _xp += amount;
    bool leveled = false;
    while (_xp >= xpToNext) {
      _xp -= xpToNext;
      _level++;
      leveled = true;
    }
    notifyListeners();
    if (leveled) {
      // 升级不额外奖励属性，纯粹作为进度反馈（GDD Phase 4 只要求 HUD 展示）。
    }
  }

  /// 复活：满血、半饱、经验清零（MC 死亡掉经验）。
  void respawn() {
    _hp = maxHp;
    _hunger = 12;
    _saturation = 2;
    _exhaustion = 0;
    _regenTimer = 0;
    _xp = 0;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hp': _hp,
        'hunger': _hunger,
        'sat': _saturation,
        'xp': _xp,
        'lv': _level,
        'arm': _armorPoints,
      };

  void loadJson(Map<String, dynamic> j) {
    _hp = ((j['hp'] as num?)?.toInt() ?? maxHp).clamp(0, maxHp);
    _hunger = ((j['hunger'] as num?)?.toInt() ?? maxHunger).clamp(0, maxHunger);
    _saturation = ((j['sat'] as num?)?.toDouble() ?? 5).clamp(0.0, 20.0);
    _xp = (j['xp'] as num?)?.toInt() ?? 0;
    _level = (j['lv'] as num?)?.toInt() ?? 0;
    _armorPoints = ((j['arm'] as num?)?.toInt() ?? 0).clamp(0, 20);
    notifyListeners();
  }
}
