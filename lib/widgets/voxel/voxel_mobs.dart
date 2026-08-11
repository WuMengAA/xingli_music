/// ════════════════════════════════════════════════════════════════════════
/// 敌对生物 + 掉落物（R23w · GDD §4.2 §5.1 / Phase 4）
/// ════════════════════════════════════════════════════════════════════════
///
/// - [Zombie]：夜间在玩家周围的黑暗地表刷新，追击、近身攻击，白天灼烧消失。
/// - [DroppedItem]：破坏方块产生的掉落物，受重力、落地后浮动旋转，靠近自动拾取。
/// - [MobWorld]：统一的生成 / 推进 / 拾取管理器，视图每帧调 [MobWorld.tick]。
///
/// 依赖 [VoxelWorld] 只读地形查询，不依赖 Flutter widgets（Color 除外），可单测。
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'voxel_camera.dart' show Vec3, VoxelEntity;
import 'voxel_items.dart';
import 'voxel_world.dart';
import 'voxel_world_types.dart';

/// 僵尸。
class Zombie {
  Zombie({required this.pos, this.hp = 20});

  /// 脚底位置（世界坐标）。
  Vec3 pos;

  /// 竖直速度（重力）。
  double vy = 0;

  int hp;

  /// 攻击冷却（秒）。
  double attackCd = 0;

  /// 受击闪红剩余时间（秒）。
  double hurtFlash = 0;

  /// 白日灼烧累计（秒）。
  double burn = 0;

  bool get alive => hp > 0;

  /// 碰撞箱半宽 / 身高。
  static const double halfWidth = 0.3;
  static const double height = 1.95;
}

/// 掉落物（方块小方块，落地后上下浮动）。
class DroppedItem {
  DroppedItem({required this.pos, required this.stack, this.life = 0});

  Vec3 pos;
  double vy = 0;

  /// 水平初速（破坏时向外弹一点）。
  double vx = 0;
  double vz = 0;

  ItemStack stack;

  /// 存在时长（秒；用于浮动动画与超时消失）。
  double life;

  bool onGround = false;

  /// 拾取冷却：刚掉出来 0.4 s 内不吸（否则挖一个立刻回背包看不到动画）。
  double pickupDelay = 0.4;

  /// 存在上限（秒），超时消失防止无限堆积。
  static const double maxLife = 180;
}

/// 生物 / 掉落物世界管理器。
class MobWorld {
  MobWorld({required this.world, int seed = 20260811})
      : _rng = math.Random(seed);

  final VoxelWorld world;
  final math.Random _rng;

  final List<Zombie> zombies = <Zombie>[];
  final List<DroppedItem> items = <DroppedItem>[];

  /// 僵尸数量上限（性能与体验兼顾）。
  static const int maxZombies = 8;

  /// 掉落物数量上限。
  static const int maxItems = 64;

  /// 刷怪冷却（秒）。
  double _spawnCd = 3;

  /// 重力加速度（格/秒²，与玩家一致）。
  static const double gravity = 24.0;

  /// 僵尸移动速度（格/秒）。
  static const double zombieSpeed = 2.1;

  /// 僵尸攻击距离与伤害。
  static const double attackRange = 1.35;
  static const int attackDamage = 3;

  /// 拾取半径。
  static const double pickupRange = 1.6;

  /// 推进一帧。
  ///
  /// [playerPos] 玩家脚底；[isNight] 夜间；[survival] 只有生存模式才刷怪。
  /// [onHitPlayer] 僵尸攻击到玩家时回调伤害；[onPickup] 拾取回调（返回是否装下）。
  void tick(
    double dt, {
    required Vec3 playerPos,
    required bool isNight,
    required bool survival,
    required void Function(int damage) onHitPlayer,
    required bool Function(ItemStack stack) onPickup,
  }) {
    if (dt <= 0) return;
    _tickItems(dt, playerPos, onPickup);
    if (!survival) {
      // 创造模式清场，免得切回来一堆怪。
      if (zombies.isNotEmpty) zombies.clear();
      return;
    }
    _tickZombies(dt, playerPos, isNight, onHitPlayer);
    _trySpawn(dt, playerPos, isNight);
  }

  // ── 掉落物 ────────────────────────────────────────────

  /// 在 [x],[y],[z] 处产出掉落物（破坏方块时调用）。
  void spawnDrops(int x, int y, int z, List<ItemStack> drops) {
    for (final ItemStack s in drops) {
      if (items.length >= maxItems) return;
      final DroppedItem d = DroppedItem(
        pos: Vec3(x + 0.5, y + 0.35, z + 0.5),
        stack: s,
      );
      // 向随机方向轻微弹出，避免多个掉落物完全重叠。
      final double a = _rng.nextDouble() * math.pi * 2;
      d.vx = math.cos(a) * 0.9;
      d.vz = math.sin(a) * 0.9;
      d.vy = 2.2;
      items.add(d);
    }
  }

  void _tickItems(
    double dt,
    Vec3 playerPos,
    bool Function(ItemStack stack) onPickup,
  ) {
    for (int i = items.length - 1; i >= 0; i--) {
      final DroppedItem d = items[i];
      d.life += dt;
      if (d.pickupDelay > 0) d.pickupDelay -= dt;
      if (d.life > DroppedItem.maxLife) {
        items.removeAt(i);
        continue;
      }

      // 重力 + 水平阻尼。
      d.vy -= gravity * dt;
      double nx = d.pos.x + d.vx * dt;
      double ny = d.pos.y + d.vy * dt;
      double nz = d.pos.z + d.vz * dt;
      d.vx *= math.pow(0.02, dt).toDouble();
      d.vz *= math.pow(0.02, dt).toDouble();

      // 落地检测：脚下方块实心则停住。
      final int bx = nx.floor();
      final int bz = nz.floor();
      final int by = ny.floor();
      if (_solidAt(bx, by, bz)) {
        ny = by + 1.0;
        d.vy = 0;
        d.onGround = true;
      } else {
        d.onGround = false;
      }
      // 水平方向撞墙就退回。
      if (_solidAt(nx.floor(), ny.floor(), d.pos.z.floor())) nx = d.pos.x;
      if (_solidAt(d.pos.x.floor(), ny.floor(), nz.floor())) nz = d.pos.z;
      d.pos = Vec3(nx, ny, nz);

      // 自动拾取。
      if (d.pickupDelay <= 0) {
        final double dx = playerPos.x - d.pos.x;
        final double dy = (playerPos.y + 0.9) - d.pos.y;
        final double dz = playerPos.z - d.pos.z;
        if (dx * dx + dy * dy + dz * dz < pickupRange * pickupRange) {
          if (onPickup(d.stack)) items.removeAt(i);
        }
      }
    }
  }

  // ── 僵尸 ──────────────────────────────────────────────

  void _tickZombies(
    double dt,
    Vec3 playerPos,
    bool isNight,
    void Function(int damage) onHitPlayer,
  ) {
    for (int i = zombies.length - 1; i >= 0; i--) {
      final Zombie z = zombies[i];
      if (!z.alive) {
        zombies.removeAt(i);
        continue;
      }
      if (z.hurtFlash > 0) z.hurtFlash -= dt;
      if (z.attackCd > 0) z.attackCd -= dt;

      // 白天灼烧：3 秒掉 1 血，很快就烧没了（省得白天满地怪）。
      if (!isNight) {
        z.burn += dt;
        if (z.burn >= 3.0) {
          z.burn = 0;
          z.hp -= 1;
        }
      } else {
        z.burn = 0;
      }

      final double dx = playerPos.x - z.pos.x;
      final double dz = playerPos.z - z.pos.z;
      final double distSq = dx * dx + dz * dz;

      // 太远直接退场（省算力，也符合 MC 的距离卸载）。
      if (distSq > 64 * 64) {
        zombies.removeAt(i);
        continue;
      }

      double nx = z.pos.x;
      double nz = z.pos.z;
      if (distSq > 0.01 && distSq < 32 * 32) {
        final double d = math.sqrt(distSq);
        final double step = zombieSpeed * dt;
        nx += dx / d * step;
        nz += dz / d * step;
      }

      // 重力。
      z.vy -= gravity * dt;
      double ny = z.pos.y + z.vy * dt;

      // 落地。
      final int by = ny.floor();
      if (_solidAt(nx.floor(), by, nz.floor())) {
        ny = by + 1.0;
        z.vy = 0;
      }

      // 撞墙 → 尝试上台阶（1 格），上不去就贴墙。
      if (_solidAt(nx.floor(), ny.floor(), z.pos.z.floor()) ||
          _solidAt(nx.floor(), ny.floor() + 1, z.pos.z.floor())) {
        if (!_solidAt(nx.floor(), ny.floor() + 1, z.pos.z.floor()) &&
            !_solidAt(nx.floor(), ny.floor() + 2, z.pos.z.floor())) {
          ny += 1.0;
        } else {
          nx = z.pos.x;
        }
      }
      if (_solidAt(z.pos.x.floor(), ny.floor(), nz.floor()) ||
          _solidAt(z.pos.x.floor(), ny.floor() + 1, nz.floor())) {
        if (!_solidAt(z.pos.x.floor(), ny.floor() + 1, nz.floor()) &&
            !_solidAt(z.pos.x.floor(), ny.floor() + 2, nz.floor())) {
          ny += 1.0;
        } else {
          nz = z.pos.z;
        }
      }

      z.pos = Vec3(nx, ny.clamp(0.0, world.maxY - 2.0), nz);

      // 攻击。
      final double ady = (playerPos.y - z.pos.y).abs();
      if (distSq < attackRange * attackRange && ady < 2.0 && z.attackCd <= 0) {
        z.attackCd = 1.2;
        onHitPlayer(attackDamage);
      }
    }
  }

  void _trySpawn(double dt, Vec3 playerPos, bool isNight) {
    _spawnCd -= dt;
    if (_spawnCd > 0) return;
    _spawnCd = 4.0;
    if (!isNight || zombies.length >= maxZombies) return;

    // 在玩家周围 18~34 格的环带上找一个可站立的地表点。
    for (int attempt = 0; attempt < 6; attempt++) {
      final double a = _rng.nextDouble() * math.pi * 2;
      final double r = 18 + _rng.nextDouble() * 16;
      final int x = (playerPos.x + math.cos(a) * r).round();
      final int zc = (playerPos.z + math.sin(a) * r).round();
      final int h = world.terrainHeightAt(x, zc);
      final int y = h + 1;
      if (y < 1 || y > world.maxY - 3) continue;
      // 需要两格净空 + 脚下实心。
      if (!_solidAt(x, y - 1, zc)) continue;
      if (_solidAt(x, y, zc) || _solidAt(x, y + 1, zc)) continue;
      // 不在水里刷。
      if (world.get(x, y - 1, zc) == Voxel.water) continue;
      zombies.add(Zombie(pos: Vec3(x + 0.5, y.toDouble(), zc + 0.5)));
      return;
    }
  }

  /// 对最靠近准星的僵尸造成伤害（玩家攻击）。返回是否命中。
  bool hitNearest(Vec3 from, Vec3 dir, {double range = 4.0, int damage = 4}) {
    Zombie? best;
    double bestT = double.infinity;
    for (final Zombie z in zombies) {
      final double cx = z.pos.x;
      final double cy = z.pos.y + Zombie.height * 0.5;
      final double cz = z.pos.z;
      final double dx = cx - from.x;
      final double dy = cy - from.y;
      final double dz = cz - from.z;
      final double t = dx * dir.x + dy * dir.y + dz * dir.z;
      if (t < 0 || t > range) continue;
      // 到视线的垂距。
      final double px = dx - dir.x * t;
      final double py = dy - dir.y * t;
      final double pz = dz - dir.z * t;
      final double perp2 = px * px + py * py + pz * pz;
      if (perp2 > 1.1 * 1.1) continue;
      if (t < bestT) {
        bestT = t;
        best = z;
      }
    }
    if (best == null) return false;
    best.hp -= damage;
    best.hurtFlash = 0.25;
    if (best.hp <= 0) {
      // 死亡掉落腐肉的替身：掉一块泥土意思一下（不新增方块类型）。
      spawnDrops(
        best.pos.x.floor(),
        best.pos.y.floor(),
        best.pos.z.floor(),
        const <ItemStack>[ItemStack(Voxel.dirt)],
      );
    }
    return true;
  }

  /// 世界里没有任何僵尸与掉落物（渲染时可跳过实体合并，省一次列表拷贝）。
  bool get isEmpty => zombies.isEmpty && items.isEmpty;

  /// 全部清空（换世界 / 退出）。
  void clear() {
    zombies.clear();
    items.clear();
  }

  bool _solidAt(int x, int y, int z) {
    if (y < 0 || y >= world.maxY) return false;
    final Voxel v = world.get(x, y, z);
    return v != Voxel.air && v != Voxel.water;
  }

  /// 转成渲染实体列表（僵尸用人形、掉落物用小方块）。
  List<VoxelEntity> toEntities() {
    final List<VoxelEntity> out = <VoxelEntity>[];
    for (final Zombie z in zombies) {
      out.add(VoxelEntity(
        position: z.pos,
        color: z.hurtFlash > 0
            ? const Color(0xFFFF6B6B)
            : const Color(0xFF4C8B4A),
        scale: 0.95,
        glow: z.hurtFlash > 0,
      ));
    }
    for (final DroppedItem d in items) {
      // 落地后上下浮动（人形渲染器的缩放很小 → 视觉上就是一小坨物品）。
      final double bob = math.sin(d.life * 2.4) * 0.06;
      out.add(VoxelEntity(
        position: Vec3(d.pos.x, d.pos.y + bob, d.pos.z),
        color: d.stack.item.spec.base,
        scale: 0.22,
      ));
    }
    return out;
  }
}
