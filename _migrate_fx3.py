# -*- coding: utf-8 -*-
"""R26fx3：动作键合并（破坏/攻击 + 放置/使用）+ 放置手持修复 + 地形调优
（平原起伏/森林沙漠平滑/山地雄伟/群系边界混合/河流连贯/湖泊增多）
+ 画质预设 4 档（极低0.25/低0.5/中0.8/高1.0 + 极低剔除拉满）+ painter 渲染分辨率接线。"""
import io

def sub(s, old, new, must=1):
    n = s.count(old)
    assert n == must, f'ANCHOR FAIL ({n}): {old[:70]!r}'
    return s.replace(old, new)

# ═══════════ voxel_world_view3d.dart ═══════════
p = 'lib/widgets/voxel/voxel_world_view3d.dart'
s = io.open(p, encoding='utf-8').read()

# 1) GraphicsQuality 4 档重定义（极低/低/中/高 + renderScale 0.25/0.5/0.8/1.0）
s = sub(s,
"""  /// 性能：0.5 倍分辨率渲染 + 放大显示（帧率翻倍），视距/面数最低。
  perf('性能', viewDistanceChunks: 2, lodStartChunks: 1, lodStepChunks: 1,
      maxFaces: 6000, fog: false, water: false, texture: false, renderScale: 0.5),""",
"""  /// R26fx3 极低：所有剔除拉满 + 0.25 倍分辨率渲染（帧率最大化），
  /// 视距/面数最低、特效全关。能拉最低拉最低。
  perf('极低', viewDistanceChunks: 2, lodStartChunks: 1, lodStepChunks: 1,
      maxFaces: 4000, fog: false, water: false, texture: false, renderScale: 0.25),""")
s = sub(s,
"""  smooth('流畅', viewDistanceChunks: 4, lodStartChunks: 2, lodStepChunks: 2,
      maxFaces: 9000, fog: true, water: true, texture: false, renderScale: 1.0),""",
"""  smooth('低', viewDistanceChunks: 4, lodStartChunks: 2, lodStepChunks: 2,
      maxFaces: 9000, fog: true, water: true, texture: false, renderScale: 0.5),""")
s = sub(s,
"""  standard('标准', viewDistanceChunks: 6, lodStartChunks: 3, lodStepChunks: 2,
      maxFaces: 18000, fog: true, water: true, texture: false, renderScale: 1.0),""",
"""  standard('中', viewDistanceChunks: 6, lodStartChunks: 3, lodStepChunks: 2,
      maxFaces: 18000, fog: true, water: true, texture: false, renderScale: 0.8),""")
s = sub(s,
"""  /// 高清：启用 16×16 程序化贴图图集，最高视距/面数预算，1.0 分辨率。
  high('高清', viewDistanceChunks: 8, lodStartChunks: 4, lodStepChunks: 2,
      maxFaces: 24000, fog: true, water: true, texture: true, renderScale: 1.0);""",
"""  /// R26fx3 高：启用 16×16 程序化贴图图集（独家效果），最高视距/面数预算，
  /// 1.0 分辨率 + AO/阴影。
  high('高', viewDistanceChunks: 8, lodStartChunks: 4, lodStepChunks: 2,
      maxFaces: 24000, fog: true, water: true, texture: true, renderScale: 1.0);""")

# 2) painter 渲染分辨率接线（补 renderScaleProvider × renderRatioProvider）
s = sub(s,
"""      renderScale: _quality.renderScale * _frameDynScale,""",
"""      renderScale: _quality.renderScale *
          ref.read(renderScaleProvider) *
          ref.read(renderRatioProvider) *
          _frameDynScale,""")

# 3) _tryAttack void → bool
s = sub(s,
"""  /// 攻击准星方向最近的僵尸。
  void _tryAttack() {
    if (!_survival || _attackCd > 0 || _mobs.zombies.isEmpty) return;
    final Vec3 from = Vec3(
      _fpPos.x,
      _fpPos.y + (_crouching ? 1.15 : 1.62),
      _fpPos.z,
    );
    if (_mobs.hitNearest(
      from,
      _camera.forwardVector(),
      damage: 4 + _inv.tool.tier.level,
    )) {
      _attackCd = 0.45;
      _dirty = true;
    }
  }""",
"""  /// 攻击准星方向最近的僵尸；返回是否命中（供合并键先攻后挖）。
  bool _tryAttack() {
    if (!_survival || _attackCd > 0 || _mobs.zombies.isEmpty) return false;
    final Vec3 from = Vec3(
      _fpPos.x,
      _fpPos.y + (_crouching ? 1.15 : 1.62),
      _fpPos.z,
    );
    if (_mobs.hitNearest(
      from,
      _camera.forwardVector(),
      damage: 4 + _inv.tool.tier.level,
    )) {
      _attackCd = 0.45;
      _dirty = true;
      return true;
    }
    return false;
  }""")

# 4) _primaryAction 合并（先攻后挖，生存/创造都能挖）
s = sub(s,
"""  void _primaryAction() {
    if (_bagOpen || _cameraMode) return;
    if (_viewMode != _ViewMode.firstPerson &&
        _viewMode != _ViewMode.thirdPerson) {
      return;
    }
    if (_survival) {
      _tryAttack();
    } else {
      final ((int, int, int), (int, int, int))? h = _raycast();
      if (h != null) _breakBlock(h.$1);
    }
  }""",
"""  /// R26fx3：破坏/攻击合并——先尝试攻击实体（命中即攻击），否则破坏方块。
  /// 生存/创造都能挖；有僵尸时先打僵尸。
  void _primaryAction() {
    if (_bagOpen || _cameraMode) return;
    if (_viewMode != _ViewMode.firstPerson &&
        _viewMode != _ViewMode.thirdPerson) {
      return;
    }
    if (_tryAttack()) return;
    final ((int, int, int), (int, int, int))? h = _raycast();
    if (h != null) _breakBlock(h.$1);
  }""")

# 5) 删 _mineBlock（合并回 _primaryAction）
s = sub(s,
"""  /// R26fx：挖掘（攻击/使用拆四键之一）——射线命中方块即破坏（生存/创造通用）。
  void _mineBlock() {
    if (_bagOpen || _cameraMode) return;
    if (_viewMode != _ViewMode.firstPerson &&
        _viewMode != _ViewMode.thirdPerson) {
      return;
    }
    final ((int, int, int), (int, int, int))? h = _raycast();
    if (h != null) _breakBlock(h.$1);
  }

""", "")

# 6) 动作键 2×3 → 2×2（攻击/放置 + 蹲降/跳）
old_actions = """          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _BigActionButton(
                    icon: Icons.flash_on_rounded,
                    label: '攻击',
                    // 攻击实体（生存打怪 / 创造空放）。
                    onPress: () {
                      _tryAttack();
                      _acting = true;
                      _dirty = true;
                    },
                    onRelease: () {
                      _acting = false;
                      _resetMining();
                      _dirty = true;
                    },
                  ),
                  const SizedBox(width: 10),
                  _BigActionButton(
                    icon: Icons.construction_rounded,
                    label: '挖掘',
                    // 挖掘方块（射线命中即破坏，生存/创造通用）。
                    onPress: () {
                      _mineBlock();
                      _acting = true;
                      _dirty = true;
                    },
                    onRelease: () {
                      _acting = false;
                      _resetMining();
                      _dirty = true;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _BigActionButton(
                    icon: Icons.back_hand_rounded,
                    label: '使用',
                    // 使用手持物品（食物进食等）。
                    onPress: _eatHeld,
                    onRelease: () {},
                  ),
                  const SizedBox(width: 10),
                  _BigActionButton(
                    icon: Icons.add_box_rounded,
                    label: '放置',
                    // 放置方块（进食归「使用」键）。
                    onPress: () => _placeAt(eatFood: false),
                    onRelease: () {},
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 蹲/降：飞行中 = 下降（修复「飞行无法下降」），地面 = 蹲下。
                  _BigActionButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    label: _flyMode ? '降' : '蹲',
                    onPress: () => setState(() {
                      if (_flyMode) {
                        _held.add(_Nav.down);
                      } else {
                        _crouching = true;
                      }
                    }),
                    onRelease: () => setState(() {
                      if (_flyMode) {
                        _held.remove(_Nav.down);
                      } else {
                        _crouching = false;
                      }
                    }),
                  ),
                  const SizedBox(width: 10),
                  _BigActionButton(
                    icon: Icons.arrow_upward_rounded,
                    label: _submerged
                        ? '游↑'
                        : (_survival ? '跳' : (_flyMode ? '升' : '跳')),
                    // R26p-camera：生存 = 点击跳跃；创造 = 双击切换飞行，飞行中按住上升。
                    onPress: _onJumpButtonDown,
                    onRelease: _onJumpButtonUp,
                  ),
                ],
              ),
            ],
          ),"""
new_actions = """          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // R26fx3：破坏/攻击合并（一个键：先攻后挖，生存创造都能挖）。
                  _BigActionButton(
                    icon: Icons.flash_on_rounded,
                    label: '攻击',
                    onPress: () {
                      _primaryAction();
                      _acting = true;
                      _dirty = true;
                    },
                    onRelease: () {
                      _acting = false;
                      _resetMining();
                      _dirty = true;
                    },
                  ),
                  const SizedBox(width: 10),
                  // R26fx3：放置/使用合并（手持食物=吃，方块=放置）。
                  _BigActionButton(
                    icon: Icons.add_box_rounded,
                    label: '放置',
                    onPress: _placeAt,
                    onRelease: () {},
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 蹲/降：飞行中 = 下降，地面 = 蹲下。
                  _BigActionButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    label: _flyMode ? '降' : '蹲',
                    onPress: () => setState(() {
                      if (_flyMode) {
                        _held.add(_Nav.down);
                      } else {
                        _crouching = true;
                      }
                    }),
                    onRelease: () => setState(() {
                      if (_flyMode) {
                        _held.remove(_Nav.down);
                      } else {
                        _crouching = false;
                      }
                    }),
                  ),
                  const SizedBox(width: 10),
                  _BigActionButton(
                    icon: Icons.arrow_upward_rounded,
                    label: _submerged
                        ? '游↑'
                        : (_survival ? '跳' : (_flyMode ? '升' : '跳')),
                    onPress: _onJumpButtonDown,
                    onRelease: _onJumpButtonUp,
                  ),
                ],
              ),
            ],
          ),"""
s = sub(s, old_actions, new_actions)

# 7) _placeAt 放置用手持物品（非 _mcSelected）
s = sub(s,
"""    widget.world.setVoxel(px, py, pz, _mcSelected);
    _invalidateChunkAt(px, pz);
    // G4：放置水 → 登记水源，后续由 20tps 扩散（MC 式，四周 9 格）。
    if (_mcSelected == Voxel.water) {
      widget.world.addWaterSource(px, py, pz);
    }""",
"""    // R26fx3：放置**手持物品**（修复「拿木板却放石头/拿食物放不了」——
    // 旧实现用独立 _mcSelected，与背包不同步）。
    final Voxel toPlace = held.item;
    if (toPlace == Voxel.air) return;
    widget.world.setVoxel(px, py, pz, toPlace);
    _invalidateChunkAt(px, pz);
    // G4：放置水 → 登记水源，后续由 20tps 扩散（MC 式，四周 9 格）。
    if (toPlace == Voxel.water) {
      widget.world.addWaterSource(px, py, pz);
    }""")

# 8) _syncInventoryForMode 同步 _mcSelected
s = sub(s,
"""    } else {
      _inv.fillCreative(kCreativeBlocks);
    }
  }""",
"""    } else {
      _inv.fillCreative(kCreativeBlocks);
    }
    // R26fx3：同步当前选中方块（否则放置用过期/默认 stone）。
    _mcSelected = _inv.at(_inv.selected).item;
  }""")

io.open(p, 'w', encoding='utf-8').write(s)
print('view3d OK')

# ═══════════ voxel_world_types.dart（kBiomes 地形参数）═══════════
p2 = 'lib/widgets/voxel/voxel_world_types.dart'
t = io.open(p2, encoding='utf-8').read()
t = sub(t,
"""    baseHeight: 40,
    amplitude: 7,""",
"""    baseHeight: 40,
    amplitude: 12,""")
t = sub(t,
"""    baseHeight: 44,
    amplitude: 11,""",
"""    baseHeight: 44,
    amplitude: 8,""")
t = sub(t,
"""    baseHeight: 38,
    amplitude: 9,""",
"""    baseHeight: 38,
    amplitude: 6,""")
t = sub(t,
"""    baseHeight: 50,
    amplitude: 34,""",
"""    baseHeight: 58,
    amplitude: 48,""")
t = sub(t,
"""    baseHeight: 60,
    amplitude: 42,""",
"""    baseHeight: 68,
    amplitude: 52,""")
io.open(p2, 'w', encoding='utf-8').write(t)
print('biomes OK')

# ═══════════ voxel_world.dart（群系边界混合 + 河流 + 湖泊）═══════════
p3 = 'lib/widgets/voxel/voxel_world.dart'
u = io.open(p3, encoding='utf-8').read()

# 1) 群系边界混合（4 角 baseHeight/amplitude 等权）
u = sub(u,
"""    final Biome biome = _biomeAtS(x, z, shiftX, shiftZ);
    final BiomeSpec spec = kBiomes[biome]!;
    // R26j：种子风格参数（由 shift 确定性派生，纯函数 → Isolate 与实例一致）。""",
"""    // R26fx3：群系边界平滑——4 角群系 baseHeight/amplitude 等权混合，
    // 消除硬边界「高低差」（森林/沙漠/山地交界不再悬崖式突变）。
    double mixBase = 0, mixAmp = 0;
    for (int dx = 0; dx <= 1; dx++) {
      for (int dz = 0; dz <= 1; dz++) {
        final BiomeSpec s2 =
            kBiomes[_biomeAtS(x + dx, z + dz, shiftX, shiftZ)]!;
        mixBase += s2.baseHeight * 0.25;
        mixAmp += s2.amplitude * 0.25;
      }
    }
    // R26j：种子风格参数（由 shift 确定性派生，纯函数 → Isolate 与实例一致）。""")
u = sub(u,
"""    double h = spec.baseHeight + spec.amplitude * ampMul * n + cont * 20.0 + elev;""",
"""    double h = mixBase + mixAmp * ampMul * n + cont * 20.0 + elev;""")

# 2) 河流连贯：走廊频率 0.008→0.006（更宽河道）、阈值 -0.18→-0.22（更多入河）
u = sub(u,
"""    final double fx = x * 0.008 + 300.0 + shiftX * 0.01;
    final double fz = z * 0.008 + 700.0 + shiftZ * 0.01;""",
"""    // R26fx3：走廊频率降低 → 河道更宽更连贯（不再断断续续）。
    final double fx = x * 0.006 + 300.0 + shiftX * 0.01;
    final double fz = z * 0.006 + 700.0 + shiftZ * 0.01;""")
u = sub(u,
"""      if (rv < -0.18) {""",
"""      if (rv < -0.22) {""")
u = sub(u,
"""    // 河道判定：走廊噪声低于阈值 → 在河道内。阈值 -0.18（成带不泛滥）。
    const double river = -0.18;""",
"""    // R26fx3：河道判定阈值放宽 -0.22 → 更多列入河、水流更连贯。
    const double river = -0.22;""")

# 3) 湖泊增多：概率 0.5→0.35、频率 0.05→0.07
u = sub(u,
"""        final double lake = _noise3(x.toDouble(), z.toDouble(), 0.0, 0.05);
        if (lake > 0.5) {
          final int waterTable = (32 + ((lake - 0.5) * 22).round())""",
"""        // R26fx3：湖泊概率提高（0.5→0.35）且更分散（频率 0.05→0.07）。
        final double lake = _noise3(x.toDouble(), z.toDouble(), 0.0, 0.07);
        if (lake > 0.35) {
          final int waterTable = (32 + ((lake - 0.35) * 22).round())""")

io.open(p3, 'w', encoding='utf-8').write(u)
print('world OK')

# ═══════════ settings_item_registry.dart（画质预设 4 档应用）═══════════
p4 = 'lib/core/settings_item_registry.dart'
v = io.open(p4, encoding='utf-8').read()
v = sub(v,
"""  ref.read(renderScaleProvider.notifier).state = q.renderScale;
  ref.read(renderRatioProvider.notifier).state = 1.0;""",
"""  // R26fx3：渲染分辨率倍率重置为 1.0（档位默认 renderScale 已含 0.25/0.5/0.8/1.0，
  // painter = q.renderScale × 手动倍率；不再双乘）。
  ref.read(renderScaleProvider.notifier).state = 1.0;
  ref.read(renderRatioProvider.notifier).state = 1.0;""")
v = sub(v,
"""  ref.read(fpsLimitProvider.notifier).state =
      q == GraphicsQuality.perf ? FpsLimit.fps24 : FpsLimit.fps60;
  final bool low = q == GraphicsQuality.perf || q == GraphicsQuality.smooth;""",
"""  ref.read(fpsLimitProvider.notifier).state =
      q == GraphicsQuality.perf ? FpsLimit.fps24 : FpsLimit.fps60;
  // R26fx3：极低档「所有剔除拉满」——视锥剔除也开（其他档位默认关）。
  ref.read(frustumCullEnabledProvider.notifier).state =
      q == GraphicsQuality.perf;
  ref.read(faceCullEnabledProvider.notifier).state = true;
  ref.read(occlusionCullEnabledProvider.notifier).state = true;
  ref.read(backFaceCullEnabledProvider.notifier).state = true;
  final bool low = q == GraphicsQuality.perf || q == GraphicsQuality.smooth;""")
io.open(p4, 'w', encoding='utf-8').write(v)
print('registry OK')
print('ALL DONE')
