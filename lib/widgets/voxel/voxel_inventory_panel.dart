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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';
import '../../providers/voxel/hud_layout_provider.dart';
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
  Voxel.beef,
  Voxel.cookedBeef,
  Voxel.porkchop,
  Voxel.cookedPorkchop,
  Voxel.carrot,
  Voxel.potato,
  Voxel.bakedPotato,
  Voxel.chicken,
  Voxel.cookedChicken,
  Voxel.melonSlice,
  Voxel.cookie,
  Voxel.fish,
  Voxel.cookedFish,
  Voxel.gold,
  Voxel.diamond,
];

/// 物品格的显示色（沿用方块基色，食物 / 矿物有专门色）。
Color itemColorOf(Voxel v) => v == Voxel.air
    ? const Color(0x22FFFFFF)
    : Color(v.spec.base.toARGB32() | 0xFF000000);

/// 物品中文名（HUD / 提示用）。
///
/// R29：单一事实源 = [VoxelSpec.displayName]，不再维护独立 `switch`（原
/// 写法新增方块易漏改——用户「写死 4 次」的根因）。新增 [Voxel] 时只需在
/// [kVoxelSpecs] 填 `displayName` 即可，命名与渲染一处维护。
String itemNameOf(Voxel v) => v.spec.displayName;

/// 单个物品格。
/// R25 斜正交（isometric）体素图标：把方块物品画成立体小方块，
/// 顶部最亮、左面中、右面最暗，沿用 [itemColorOf] 基色，替代平面色块。
/// G5（用户确认）：按 [VoxelSpec.pattern] 在三面叠加 MC 式材质——草=顶绿
/// 侧褐、原木=侧竖纹、木板=横纹、砖=错缝、沙=细点、金/钻=反光棱等，
/// 让物品视图与 MC 一致（不再纯色）。
class _IsoVoxelIcon extends StatelessWidget {
  const _IsoVoxelIcon({required this.voxel, this.size = 26});
  final Voxel voxel;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _IsoVoxelPainter(voxel.spec),
      );
}

class _IsoVoxelPainter extends CustomPainter {
  _IsoVoxelPainter(this.spec);
  final VoxelSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final Color base = spec.base;
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

    final Color top = spec.top ??
        Color.lerp(base, const Color(0xFFFFFFFF), 0.22)!;
    final Color left = Color.lerp(base, const Color(0xFF000000), 0.34)!;
    final Color right = Color.lerp(base, const Color(0xFF000000), 0.52)!;
    final Paint fill = Paint()..style = PaintingStyle.fill;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x55000000)
      ..strokeWidth = 1;

    // 三个面的 Path（画纯色 + 材质线）。
    final Path leftFace = Path()
      ..moveTo(p(0, 0, 0).dx, p(0, 0, 0).dy)
      ..lineTo(p(0, 1, 0).dx, p(0, 1, 0).dy)
      ..lineTo(p(0, 1, 1).dx, p(0, 1, 1).dy)
      ..lineTo(p(0, 0, 1).dx, p(0, 0, 1).dy)
      ..close();
    final Path rightFace = Path()
      ..moveTo(p(0, 0, 0).dx, p(0, 0, 0).dy)
      ..lineTo(p(1, 0, 0).dx, p(1, 0, 0).dy)
      ..lineTo(p(1, 0, 1).dx, p(1, 0, 1).dy)
      ..lineTo(p(0, 0, 1).dx, p(0, 0, 1).dy)
      ..close();
    final Path topFace = Path()
      ..moveTo(p(0, 1, 0).dx, p(0, 1, 0).dy)
      ..lineTo(p(1, 1, 0).dx, p(1, 1, 0).dy)
      ..lineTo(p(1, 1, 1).dx, p(1, 1, 1).dy)
      ..lineTo(p(0, 1, 1).dx, p(0, 1, 1).dy)
      ..close();

    // 纯色三面。
    fill.color = left;
    canvas.drawPath(leftFace, fill);
    fill.color = right;
    canvas.drawPath(rightFace, fill);
    fill.color = top;
    canvas.drawPath(topFace, fill);

    // G5：按 pattern 叠材质线（顶面图案 + 侧面图案）。线条色 = 对应面加深。
    // 草方块无 pattern（spec.pattern=none），但其侧壁应有土色条 → 特判草。
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, s * 0.045);
    if (spec.id == Voxel.grass) {
      line.color = Color.lerp(base, const Color(0xFF6A4A2B), 0.55)!;
      canvas.drawLine(p(0, 0, 0.18), p(0, 1, 0.18), line); // 左面
      canvas.drawLine(p(0, 0, 0.18), p(1, 0, 0.18), line); // 右面
    }
    switch (spec.pattern) {
      case VoxelPattern.none:
        break;
      case VoxelPattern.planks:
        // 侧面横纹 2 条。
        line.color = Color.lerp(base, const Color(0xFF000000), 0.35)!;
        for (int i = 1; i <= 2; i++) {
          final double yy = 0.33 * i;
          canvas.drawLine(p(0, 0, yy), p(0, 1, yy), line);
          canvas.drawLine(p(0, 0, yy), p(1, 0, yy), line);
        }
        break;
      case VoxelPattern.brick:
        // 侧面横线 + 交错竖线（砖缝）。
        line.color = Color.lerp(base, const Color(0xFF000000), 0.42)!;
        canvas.drawLine(p(0, 0, 0.5), p(0, 1, 0.5), line);
        canvas.drawLine(p(0, 0, 0.5), p(1, 0, 0.5), line);
        canvas.drawLine(p(0, 0.5, 0), p(0, 0.5, 1), line);
        canvas.drawLine(p(0.5, 0, 0), p(0.5, 0, 1), line);
        break;
      case VoxelPattern.cobble:
        // 侧面少量暗点（圆石）。
        final Paint dot = Paint()..color = Color.lerp(
            base, const Color(0xFF000000), 0.4)!;
        for (final Offset d in <Offset>[
          Offset(0.25, 0.3), Offset(0.72, 0.62), Offset(0.45, 0.85),
        ]) {
          canvas.drawCircle(
              p(0, d.dx, d.dy).translate(0, 0), s * 0.05, dot);
          canvas.drawCircle(
              p(d.dx, 0, d.dy).translate(0, 0), s * 0.05, dot);
        }
        break;
      case VoxelPattern.sandDots:
        final Paint dot = Paint()..color = Color.lerp(
            base, const Color(0xFFFFFFFF), 0.25)!;
        for (final Offset d in <Offset>[
          Offset(0.3, 0.35), Offset(0.7, 0.7),
        ]) {
          canvas.drawCircle(
              p(0, d.dx, d.dy).translate(0, 0), s * 0.035, dot);
          canvas.drawCircle(
              p(d.dx, 0, d.dy).translate(0, 0), s * 0.035, dot);
        }
        break;
      case VoxelPattern.goldShine:
        // 顶面斜向高光。
        line.color = Color.lerp(base, const Color(0xFFFFFFFF), 0.5)!;
        canvas.drawLine(p(0.2, 1, 1), p(0.8, 1, 1), line);
        break;
      case VoxelPattern.diamondShine:
        // 顶面双棱反光。
        line.color = Color.lerp(base, const Color(0xFFFFFFFF), 0.55)!;
        canvas.drawLine(p(0.15, 0.85, 1), p(0.5, 1, 1), line);
        canvas.drawLine(p(0.5, 1, 1), p(0.85, 0.85, 1), line);
        break;
      case VoxelPattern.glassShine:
        line.color = Color.lerp(base, const Color(0xFFFFFFFF), 0.45)!;
        canvas.drawLine(p(0.25, 0.75, 1), p(0.75, 1, 1), line);
        break;
      case VoxelPattern.slabSplit:
      case VoxelPattern.stairsSteps:
        line.color = Color.lerp(base, const Color(0xFF000000), 0.35)!;
        canvas.drawLine(p(0, 0.5, 0), p(0, 0.5, 1), line);
        canvas.drawLine(p(0.5, 0, 0), p(0.5, 0, 1), line);
        break;
      case VoxelPattern.fenceBars:
        // 侧面竖条（栅栏）。
        line.color = Color.lerp(base, const Color(0xFF000000), 0.35)!;
        for (int i = 1; i <= 2; i++) {
          final double xx = 0.33 * i;
          canvas.drawLine(p(0, xx, 0), p(0, xx, 1), line);
          canvas.drawLine(p(xx, 0, 0), p(xx, 0, 1), line);
        }
        break;
      case VoxelPattern.furnaceFace:
      case VoxelPattern.campfireGlow:
      case VoxelPattern.torchGlow:
      case VoxelPattern.chestFace:
      case VoxelPattern.appleShine:
        // 简单高光/口线，足够识别。
        line.color = Color.lerp(base, const Color(0xFFFFFFFF), 0.35)!;
        canvas.drawLine(p(0.3, 0.7, 1), p(0.7, 0.7, 1), line);
        break;
    }

    // 轮廓描边（最后画，盖住材质线边缘）。
    canvas.drawPath(leftFace, stroke);
    canvas.drawPath(rightFace, stroke);
    canvas.drawPath(topFace, stroke);
  }

  @override
  bool shouldRepaint(covariant _IsoVoxelPainter old) =>
      old.spec.id != spec.id || old.spec.pattern != spec.pattern;
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.stack,
    this.selected = false,
    this.size = 42,
    this.showName = false,
    this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
  });

  final ItemStack stack;
  final bool selected;
  final double size;

  /// R26d：物品下方显示名称（背包面板开启；快捷栏关闭以免拥挤）。
  final bool showName;

  final VoidCallback? onTap;

  /// Cl29_hotfix：右键（桌面）/ 长按（触屏）拾取一半或放 1 个。
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      onLongPress: onLongPress,
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
                          voxel: stack.item,
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
    final double s = hudResponsiveScale(context);
    return AnimatedBuilder(
      animation: inventory,
      builder: (BuildContext context, Widget? _) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double avail = constraints.maxWidth;
            // 自适应槽位：9 格 + 2 个切换键 + 间隔，全部在可用宽度内排下，
            // 竖屏窄屏不再横向溢出（游戏页布局修复 #2）。
            const double chipW = 38;
            const double gap = 4;
            const double edge = 6;
            final double fixed =
                2 * chipW + 2 * edge + (VoxelInventory.hotbarSize - 1) * gap;
            final double slotSize =
                ((avail - fixed) / VoxelInventory.hotbarSize).clamp(28.0, 52.0);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _chip(
                    scale: s,
                    icon: survival
                        ? Icons.favorite_outline
                        : Icons.flight_rounded,
                    tip: survival ? '生存模式' : '创造模式',
                    onTap: onToggleSurvival,
                  ),
                  SizedBox(width: edge),
                  for (int i = 0; i < VoxelInventory.hotbarSize; i++) ...<Widget>[
                    if (i > 0) SizedBox(width: gap),
                    _Slot(
                      stack: inventory.at(i),
                      selected: inventory.selected == i,
                      // R29：快捷栏（物品栏一部分）也显示方块名，满足「物品栏标明
                      // 各种物体 / 方块名称」；主仓原本就显示，合成页已显示。
                      showName: true,
                      size: slotSize,
                      onTap: () => onSelect(i),
                    ),
                  ],
                  SizedBox(width: edge),
                  _chip(
                    scale: s,
                    icon: Icons.backpack_outlined,
                    tip: '背包 / 合成',
                    onTap: onOpenBag,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _chip({
    required double scale,
    required IconData icon,
    required String tip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 38 * scale,
          height: 38 * scale,
          decoration: BoxDecoration(
            color: const Color(0x660B1220),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x66FFFFFF)),
          ),
          child: Icon(icon, size: 18 * scale, color: const Color(0xFFF2F5FA)),
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
  });

  final VoxelInventory inventory;

  /// 附近是否有工作台（箱子 / 熔炉代用）。
  final bool hasTable;

  final VoidCallback onClose;

  /// 点击配方合成。
  final ValueChanged<CraftRecipe> onCraft;

  @override
  State<VoxelInventoryPanel> createState() => _VoxelInventoryPanelState();
}

class _VoxelInventoryPanelState extends State<VoxelInventoryPanel> {
  bool _crafting = false;

  /// Cl29_hotfix：悬浮光标（手持物品）跟随指针的位置（局部坐标）。
  Offset _cursorPos = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC0A1018),
      child: SafeArea(
        child: AnimatedBuilder(
          animation: widget.inventory,
          builder: (BuildContext context, Widget? _) {
            return Stack(
              children: <Widget>[
                Listener(
                  onPointerDown: (PointerDownEvent e) =>
                      setState(() => _cursorPos = e.localPosition),
                  onPointerMove: (PointerMoveEvent e) =>
                      setState(() => _cursorPos = e.localPosition),
                  child: Column(
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
                  ),
                ),
                // 悬浮光标：手持物品跟随鼠标（触屏显示在最后点击处）。
                if (widget.inventory.carrying)
                  Positioned(
                    left: _cursorPos.dx - 23,
                    top: _cursorPos.dy - 23,
                    child: IgnorePointer(
                      child: _Slot(
                        stack: widget.inventory.cursor,
                        size: 46,
                      ),
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
          // ⑦：退出按钮移到「背包 / 合成」标签左侧，避免与右侧操作冲突。
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded, color: Color(0xFFEFF3FA)),
            tooltip: '关闭',
          ),
          const SizedBox(width: 4),
          _tab('背包', !_crafting, () => setState(() => _crafting = false)),
          const SizedBox(width: 8),
          _tab('合成', _crafting, () => setState(() => _crafting = true)),
          const Spacer(),
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
          '背包（3×9）：点选拾取整堆 · 右键/长按取一半 · 手持时点别的格转移/交换',
          style: TextStyle(color: Color(0x99EFF3FA), fontSize: 11),
        ),
        const SizedBox(height: 8),
        _grid(VoxelInventory.hotbarSize, inv.size),
        const SizedBox(height: 14),
        const Text(
          '物品栏（1×9）：手持物品后按数字键 1-9 移入对应格',
          style: TextStyle(color: Color(0x99EFF3FA), fontSize: 11),
        ),
        const SizedBox(height: 8),
        _grid(0, VoxelInventory.hotbarSize),
      ],
    );
  }

  /// ⑥：背包改为居中的固定 9 列表格（3×9 / 1×9 类似样式），不再随宽度自由换行。
  Widget _grid(int from, int to) {
    final int count = math.max(0, to - from);
    const int columns = 9;
    if (count == 0) return const SizedBox.shrink();
    final List<Widget> rows = <Widget>[];
    for (int r = 0; r < count; r += columns) {
      final int end = math.min(r + columns, count);
      final List<Widget> cells = <Widget>[];
      for (int i = r; i < end; i++) {
        cells.add(_slotTile(from + i));
      }
      rows.add(Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: cells,
      ));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 6),
          rows[i],
        ],
      ],
    );
  }

  /// Cl29_hotfix：单格交互改为 MC 式点选（不再拖拽）。
  /// 左键 = 拾取/落位/交换；右键/长按 = 取半/放 1 个。
  Widget _slotTile(int index) {
    final VoxelInventory inv = widget.inventory;
    final bool isHot = index < VoxelInventory.hotbarSize;
    return _Slot(
      stack: inv.at(index),
      selected: isHot && index == inv.selected,
      // 背包面板内全部显示物品名（用户要求「物品栏标明名称」）。
      showName: true,
      onTap: () => inv.clickSlot(index),
      onSecondaryTap: () => inv.rightSlot(index),
      onLongPress: () => inv.rightSlot(index),
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

/// 手持工具读数（#509 装备 / 工具系统可见化）：名称 + 攻击 + 放置速度。
///
/// 让「装备 / 工具」在 HUD 上可被看见——手持工具越好，攻击越高、放置越快。
class VoxelToolHud extends StatelessWidget {
  const VoxelToolHud({super.key, required this.inventory});

  final VoxelInventory inventory;

  @override
  Widget build(BuildContext context) {
    final ToolKind tool = inventory.tool;
    final int dmg = weaponDamage(tool);
    final int placeMs = placeCooldownMs(tool);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.build_rounded, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            tool.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              shadows: <Shadow>[
                Shadow(blurRadius: 3, color: Color(0xCC000000)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('攻击 $dmg',
              style: const TextStyle(color: Color(0xFFFF9D9D), fontSize: 11)),
          const SizedBox(width: 10),
          Text('放置 ${(placeMs / 1000).toStringAsFixed(2)}s',
              style: const TextStyle(color: Color(0xFF9DD6FF), fontSize: 11)),
        ],
      ),
    );
  }
}
