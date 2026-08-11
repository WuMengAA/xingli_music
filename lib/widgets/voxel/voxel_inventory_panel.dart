/// ════════════════════════════════════════════════════════════════════════
/// 背包 / 合成 / 生存 HUD 组件（R23w · GDD Phase 4）
/// ════════════════════════════════════════════════════════════════════════
///
/// 三个可复用组件：
/// - [VoxelHotbar]：底部 9 格快捷栏（选中高亮 + 数量角标）。
/// - [VoxelInventoryPanel]：36 格背包 + 拖拽换位 + 合成页。
/// - [VoxelVitalsHud]：生命 / 饥饿 / 经验条。
///
/// 全部只读外部状态 + 回调，不持有业务逻辑。
library;

import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';
import 'voxel_crafting.dart';
import 'voxel_inventory.dart';
import 'voxel_items.dart';
import 'voxel_survival.dart';
import 'voxel_world_types.dart';

/// 创造模式一键铺满背包的方块清单（也用作方块选择器的顺序）。
const List<Voxel> kCreativeBlocks = <Voxel>[
  // 基础
  Voxel.grass,
  Voxel.dirt,
  Voxel.stone,
  Voxel.sand,
  Voxel.wood,
  Voxel.leaves,
  Voxel.snow,
  Voxel.water,
  // 建筑
  Voxel.planks,
  Voxel.brick,
  Voxel.cobble,
  Voxel.glass,
  Voxel.slab,
  Voxel.stairs,
  Voxel.fence,
  // 功能
  Voxel.furnace,
  Voxel.campfire,
  Voxel.torch,
  Voxel.chest,
  // 物品 / 食物
  Voxel.apple,
  Voxel.bread,
  Voxel.gold,
  Voxel.diamond,
];

/// 物品格的显示色（沿用方块基色，食物 / 矿物有专门色）。
Color itemColorOf(Voxel v) => v == Voxel.air
    ? const Color(0x22FFFFFF)
    : Color(v.spec.base.toARGB32() | 0xFF000000);

/// 物品中文名（HUD / 提示用）。
String itemNameOf(Voxel v) => switch (v) {
      Voxel.air => '空',
      Voxel.grass => '草方块',
      Voxel.dirt => '泥土',
      Voxel.stone => '石头',
      Voxel.sand => '沙子',
      Voxel.water => '水',
      Voxel.wood => '原木',
      Voxel.leaves => '树叶',
      Voxel.snow => '雪',
      Voxel.planks => '木板',
      Voxel.brick => '红砖',
      Voxel.cobble => '圆石',
      Voxel.glass => '玻璃',
      Voxel.slab => '半砖',
      Voxel.stairs => '楼梯',
      Voxel.fence => '栅栏',
      Voxel.furnace => '熔炉',
      Voxel.campfire => '篝火',
      Voxel.torch => '火把',
      Voxel.chest => '箱子',
      Voxel.apple => '苹果',
      Voxel.bread => '面包',
      Voxel.gold => '金锭',
      Voxel.diamond => '钻石',
      Voxel.ironOre => '铁矿石',
      Voxel.coalOre => '煤矿石',
    };

/// 单个物品格。
/// R25 斜正交（isometric）体素图标：把方块物品画成立体小方块，
/// 顶部最亮、左面中、右面最暗，沿用 [itemColorOf] 基色，替代平面色块。
class _IsoVoxelIcon extends StatelessWidget {
  const _IsoVoxelIcon({required this.color, this.size = 26});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _IsoVoxelPainter(color),
      );
}

class _IsoVoxelPainter extends CustomPainter {
  _IsoVoxelPainter(this.base);
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final double u = s * 0.42; // 菱形半宽
    final double v = s * 0.24; // 菱形半高
    final double h = s * 0.46; // 立方高度
    final Offset c = Offset(size.width / 2, size.height * 0.62);

    // 等距投影：cube (x,z) ∈ [0,1]，y 向上。+x 右下，+z 左下。
    Offset p(double x, double z, double y) => Offset(
          c.dx + (x - z) * u,
          c.dy + (x + z) * v - y * h,
        );

    final Color top = Color.lerp(base, const Color(0xFFFFFFFF), 0.22)!;
    final Color left = Color.lerp(base, const Color(0xFF000000), 0.34)!;
    final Color right = Color.lerp(base, const Color(0xFF000000), 0.52)!;
    final Paint fill = Paint()..style = PaintingStyle.fill;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x55000000)
      ..strokeWidth = 1;

    final Path leftFace = Path()
      ..moveTo(p(0, 0, 0).dx, p(0, 0, 0).dy)
      ..lineTo(p(0, 1, 0).dx, p(0, 1, 0).dy)
      ..lineTo(p(0, 1, 1).dx, p(0, 1, 1).dy)
      ..lineTo(p(0, 0, 1).dx, p(0, 0, 1).dy)
      ..close();
    fill.color = left;
    canvas.drawPath(leftFace, fill);
    canvas.drawPath(leftFace, stroke);

    final Path rightFace = Path()
      ..moveTo(p(0, 0, 0).dx, p(0, 0, 0).dy)
      ..lineTo(p(1, 0, 0).dx, p(1, 0, 0).dy)
      ..lineTo(p(1, 0, 1).dx, p(1, 0, 1).dy)
      ..lineTo(p(0, 0, 1).dx, p(0, 0, 1).dy)
      ..close();
    fill.color = right;
    canvas.drawPath(rightFace, fill);
    canvas.drawPath(rightFace, stroke);

    final Path topFace = Path()
      ..moveTo(p(0, 1, 0).dx, p(0, 1, 0).dy)
      ..lineTo(p(1, 1, 0).dx, p(1, 1, 0).dy)
      ..lineTo(p(1, 1, 1).dx, p(1, 1, 1).dy)
      ..lineTo(p(0, 1, 1).dx, p(0, 1, 1).dy)
      ..close();
    fill.color = top;
    canvas.drawPath(topFace, fill);
    canvas.drawPath(topFace, stroke);
  }

  @override
  bool shouldRepaint(covariant _IsoVoxelPainter old) => old.base != base;
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.stack,
    this.selected = false,
    this.size = 42,
    this.showName = false,
    this.onTap,
  });

  final ItemStack stack;
  final bool selected;
  final double size;

  /// R26d：物品下方显示名称（背包面板开启；快捷栏关闭以免拥挤）。
  final bool showName;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0x59000000),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFFFFFF)
                    : const Color(0x40FFFFFF),
                width: selected ? 2 : 1,
              ),
            ),
            child: stack.isEmpty
                ? null
                : Stack(
                    children: <Widget>[
                      Center(
                        child: _IsoVoxelIcon(
                          color: itemColorOf(stack.item),
                          size: size * 0.64,
                        ),
                      ),
                      if (stack.count > 1)
                        Positioned(
                          right: 2,
                          bottom: 0,
                          child: Text(
                            '${stack.count}',
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFFFFFF),
                              shadows: <Shadow>[
                                Shadow(
                                    blurRadius: 3, color: Color(0xCC000000)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          if (showName && !stack.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: size + 4,
                child: Text(
                  itemNameOf(stack.item),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    color: Color(0xE6FFFFFF),
                    shadows: <Shadow>[
                      Shadow(blurRadius: 3, color: Color(0xCC000000)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 底部快捷栏（9 格）。
class VoxelHotbar extends StatelessWidget {
  const VoxelHotbar({
    super.key,
    required this.inventory,
    required this.onSelect,
    required this.onOpenBag,
    required this.survival,
    required this.onToggleSurvival,
  });

  final VoxelInventory inventory;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpenBag;
  final bool survival;
  final VoidCallback onToggleSurvival;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: inventory,
      builder: (BuildContext context, Widget? _) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _chip(
                icon: survival ? Icons.favorite_outline : Icons.flight_rounded,
                tip: survival ? '生存模式' : '创造模式',
                onTap: onToggleSurvival,
              ),
              const SizedBox(width: 6),
              for (int i = 0; i < VoxelInventory.hotbarSize; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _Slot(
                    stack: inventory.at(i),
                    selected: inventory.selected == i,
                    onTap: () => onSelect(i),
                  ),
                ),
              const SizedBox(width: 6),
              _chip(
                icon: Icons.backpack_outlined,
                tip: '背包 / 合成',
                onTap: onOpenBag,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip({
    required IconData icon,
    required String tip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0x660B1220),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x66FFFFFF)),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFFF2F5FA)),
        ),
      ),
    );
  }
}

/// 背包面板（36 格 + 拖拽换位 + 合成页）。
class VoxelInventoryPanel extends StatefulWidget {
  const VoxelInventoryPanel({
    super.key,
    required this.inventory,
    required this.hasTable,
    required this.onClose,
    required this.onCraft,
    required this.onEat,
  });

  final VoxelInventory inventory;

  /// 附近是否有工作台（箱子 / 熔炉代用）。
  final bool hasTable;

  final VoidCallback onClose;

  /// 点击配方合成。
  final ValueChanged<CraftRecipe> onCraft;

  /// 双击食物进食。
  final ValueChanged<int> onEat;

  @override
  State<VoxelInventoryPanel> createState() => _VoxelInventoryPanelState();
}

class _VoxelInventoryPanelState extends State<VoxelInventoryPanel> {
  bool _crafting = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC0A1018),
      child: SafeArea(
        child: AnimatedBuilder(
          animation: widget.inventory,
          builder: (BuildContext context, Widget? _) {
            return Column(
              children: <Widget>[
                _header(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: AppSpace.sm,
                    ),
                    child: _crafting ? _craftBody() : _bagBody(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.sm,
        0,
      ),
      child: Row(
        children: <Widget>[
          _tab('背包', !_crafting, () => setState(() => _crafting = false)),
          const SizedBox(width: 8),
          _tab('合成', _crafting, () => setState(() => _crafting = true)),
          const Spacer(),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded, color: Color(0xFFEFF3FA)),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0x33FFFFFF) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: active ? const Color(0x88FFFFFF) : const Color(0x22FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: const Color(0xFFEFF3FA),
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ── 背包页 ──────────────────────────────────────────

  Widget _bagBody() {
    final VoxelInventory inv = widget.inventory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '主仓（拖动交换位置，双击食物进食）',
          style: TextStyle(color: Color(0x99EFF3FA), fontSize: 12),
        ),
        const SizedBox(height: 8),
        _grid(VoxelInventory.hotbarSize, inv.size),
        const SizedBox(height: 14),
        const Text(
          '快捷栏',
          style: TextStyle(color: Color(0x99EFF3FA), fontSize: 12),
        ),
        const SizedBox(height: 8),
        _grid(0, VoxelInventory.hotbarSize),
      ],
    );
  }

  Widget _grid(int from, int to) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (int i = from; i < to; i++) _draggableSlot(i),
      ],
    );
  }

  Widget _draggableSlot(int index) {
    final ItemStack s = widget.inventory.at(index);
    final Widget slot = _Slot(
      stack: s,
      selected: index == widget.inventory.selected &&
          index < VoxelInventory.hotbarSize,
      // R26d：背包面板格子下方显示物品名（快捷栏格子不显示，避免拥挤）。
      showName: index >= VoxelInventory.hotbarSize,
      onTap: () {
        if (index < VoxelInventory.hotbarSize) {
          widget.inventory.selected = index;
        }
      },
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (DragTargetDetails<int> d) => d.data != index,
      onAcceptWithDetails: (DragTargetDetails<int> d) =>
          widget.inventory.swap(d.data, index),
      builder: (BuildContext context, List<int?> cand, List<dynamic> rej) {
        final Widget content = GestureDetector(
          onDoubleTap: () => widget.onEat(index),
          child: Opacity(
            opacity: cand.isNotEmpty ? 0.6 : 1,
            child: slot,
          ),
        );
        if (s.isEmpty) return content;
        return Draggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: _Slot(stack: s, size: 46),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: slot),
          child: content,
        );
      },
    );
  }

  // ── 合成页 ──────────────────────────────────────────

  Widget _craftBody() {
    final VoxelInventory inv = widget.inventory;
    final Map<Voxel, int> have = <Voxel, int>{};
    for (final ItemStack s in inv.slots) {
      if (s.isEmpty) continue;
      have[s.item] = (have[s.item] ?? 0) + s.count;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.hasTable
              ? '工作台已就绪（附近有箱子 / 熔炉）：3×3 配方可用'
              : '手搓模式：靠近箱子或熔炉可解锁 3×3 配方',
          style: TextStyle(
            color: widget.hasTable
                ? const Color(0xFF8BE28B)
                : const Color(0x99EFF3FA),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        for (final CraftRecipe r in kRecipes)
          _recipeRow(r, have, Crafting.canCraft(r, have, hasTable: widget.hasTable)),
      ],
    );
  }

  Widget _recipeRow(CraftRecipe r, Map<Voxel, int> have, bool ok) {
    return Opacity(
      opacity: ok ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: <Widget>[
            _Slot(stack: ItemStack(r.output, r.outputCount), size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${itemNameOf(r.output)} ×${r.outputCount}'
                    '${r.needsTable ? '（需工作台）' : ''}',
                    style: const TextStyle(
                      color: Color(0xFFEFF3FA),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    r.inputs.entries
                        .map((MapEntry<Voxel, int> e) =>
                            '${itemNameOf(e.key)}×${e.value}'
                            '(${have[e.key] ?? 0})')
                        .join(' + '),
                    style: const TextStyle(
                      color: Color(0x99EFF3FA),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: ok ? () => widget.onCraft(r) : null,
              child: const Text('合成'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 生存 HUD：生命 / 饥饿 / 经验。
class VoxelVitalsHud extends StatelessWidget {
  const VoxelVitalsHud({super.key, required this.vitals});

  final PlayerVitals vitals;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vitals,
      builder: (BuildContext context, Widget? _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _icons(
                  filled: vitals.hp / 2,
                  total: 10,
                  icon: Icons.favorite_rounded,
                  empty: Icons.favorite_border_rounded,
                  color: const Color(0xFFFF4D4D),
                ),
                const SizedBox(width: 14),
                _icons(
                  filled: vitals.hunger / 2,
                  total: 10,
                  icon: Icons.lunch_dining_rounded,
                  empty: Icons.lunch_dining_outlined,
                  color: const Color(0xFFE0A34A),
                ),
              ],
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 190,
              child: Row(
                children: <Widget>[
                  Text(
                    '${vitals.level}',
                    style: const TextStyle(
                      color: Color(0xFF7CE87C),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      shadows: <Shadow>[
                        Shadow(blurRadius: 3, color: Color(0xCC000000)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: vitals.xpProgress,
                        minHeight: 6,
                        backgroundColor: const Color(0x66000000),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF6BD46B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _icons({
    required double filled,
    required int total,
    required IconData icon,
    required IconData empty,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < total; i++)
          Icon(
            i < filled.floor()
                ? icon
                : (i < filled ? icon : empty),
            size: 13,
            color: i < filled ? color : const Color(0x66FFFFFF),
            shadows: const <Shadow>[
              Shadow(blurRadius: 3, color: Color(0xCC000000)),
            ],
          ),
      ],
    );
  }
}
