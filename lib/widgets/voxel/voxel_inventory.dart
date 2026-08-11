/// ════════════════════════════════════════════════════════════════════════
/// 背包系统（R23w · GDD §3.2 / Phase 4）
/// ════════════════════════════════════════════════════════════════════════
///
/// 36 格主背包（其中前 9 格是快捷栏）+ 独立的合成网格。
/// 纯 Dart + [ChangeNotifier]，UI 只监听不持有状态；可 JSON 持久化。
library;

import 'package:flutter/foundation.dart';

import 'voxel_items.dart';
import 'voxel_world_types.dart';

/// 背包：36 格（0~8 快捷栏，9~35 主仓）。
class VoxelInventory extends ChangeNotifier {
  VoxelInventory({int size = 36})
      : _slots = List<ItemStack>.filled(size, ItemStack.empty);

  /// 快捷栏格数。
  static const int hotbarSize = 9;

  final List<ItemStack> _slots;

  int _selected = 0;

  /// 只读槽位视图。
  List<ItemStack> get slots => List<ItemStack>.unmodifiable(_slots);

  int get size => _slots.length;

  /// 当前选中的快捷栏下标（0~8）。
  int get selected => _selected;

  set selected(int i) {
    final int v = i % hotbarSize;
    if (v == _selected) return;
    _selected = v;
    notifyListeners();
  }

  /// 当前手持物品。
  ItemStack get held => _slots[_selected];

  /// 当前手持推导出的工具。
  ToolKind get tool => toolFromHeld(held.isEmpty ? Voxel.air : held.item);

  ItemStack at(int i) => (i < 0 || i >= _slots.length) ? ItemStack.empty : _slots[i];

  /// 直接写入某格（拖拽落位用）。
  void set(int i, ItemStack s) {
    if (i < 0 || i >= _slots.length) return;
    _slots[i] = s.isEmpty ? ItemStack.empty : s;
    notifyListeners();
  }

  /// 交换两格（拖拽换位；若同类可合并则先合并）。
  void swap(int a, int b) {
    if (a == b || a < 0 || b < 0 || a >= _slots.length || b >= _slots.length) {
      return;
    }
    final ItemStack sa = _slots[a];
    final ItemStack sb = _slots[b];
    if (!sa.isEmpty && !sb.isEmpty && sa.item == sb.item) {
      final int room = sb.maxStack - sb.count;
      if (room > 0) {
        final int move = sa.count < room ? sa.count : room;
        _slots[b] = sb.plus(move);
        _slots[a] = sa.plus(-move);
        notifyListeners();
        return;
      }
    }
    _slots[a] = sb;
    _slots[b] = sa;
    notifyListeners();
  }

  /// 拾取：优先并入同类未满格，其次填空格。返回未装下的数量。
  int add(ItemStack stack) {
    if (stack.isEmpty) return 0;
    int left = stack.count;
    // 1) 并入同类。
    for (int i = 0; i < _slots.length && left > 0; i++) {
      final ItemStack s = _slots[i];
      if (s.isEmpty || s.item != stack.item) continue;
      final int room = s.maxStack - s.count;
      if (room <= 0) continue;
      final int move = left < room ? left : room;
      _slots[i] = s.plus(move);
      left -= move;
    }
    // 2) 填空格。
    for (int i = 0; i < _slots.length && left > 0; i++) {
      if (!_slots[i].isEmpty) continue;
      final ItemStack fresh = ItemStack(stack.item, 1);
      final int move = left < fresh.maxStack ? left : fresh.maxStack;
      _slots[i] = ItemStack(stack.item, move);
      left -= move;
    }
    if (left != stack.count) notifyListeners();
    return left;
  }

  /// 消耗手上 1 个（放置 / 吃东西）。返回是否成功。
  bool consumeHeld([int n = 1]) {
    final ItemStack s = _slots[_selected];
    if (s.isEmpty || s.count < n) return false;
    _slots[_selected] = s.plus(-n);
    notifyListeners();
    return true;
  }

  /// 统计某种物品的总数（合成判定用）。
  int countOf(Voxel v) {
    int n = 0;
    for (final ItemStack s in _slots) {
      if (!s.isEmpty && s.item == v) n += s.count;
    }
    return n;
  }

  /// 从背包扣除指定数量（不足则不扣、返回 false）。
  bool take(Voxel v, int n) {
    if (countOf(v) < n) return false;
    int left = n;
    for (int i = 0; i < _slots.length && left > 0; i++) {
      final ItemStack s = _slots[i];
      if (s.isEmpty || s.item != v) continue;
      final int move = s.count < left ? s.count : left;
      _slots[i] = s.plus(-move);
      left -= move;
    }
    notifyListeners();
    return true;
  }

  void clear() {
    for (int i = 0; i < _slots.length; i++) {
      _slots[i] = ItemStack.empty;
    }
    notifyListeners();
  }

  /// 创造模式初始物资（切到创造时一键给满）。
  void fillCreative(List<Voxel> blocks) {
    for (int i = 0; i < _slots.length; i++) {
      _slots[i] = i < blocks.length
          ? ItemStack(blocks[i], 64)
          : ItemStack.empty;
    }
    notifyListeners();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'selected': _selected,
        'slots': <Map<String, dynamic>>[
          for (final ItemStack s in _slots) s.toJson(),
        ],
      };

  void loadJson(Map<String, dynamic> j) {
    final List<dynamic> raw = (j['slots'] as List<dynamic>?) ?? <dynamic>[];
    for (int i = 0; i < _slots.length; i++) {
      _slots[i] = i < raw.length
          ? ItemStack.fromJson(Map<String, dynamic>.from(raw[i] as Map))
          : ItemStack.empty;
    }
    _selected = ((j['selected'] as num?)?.toInt() ?? 0) % hotbarSize;
    notifyListeners();
  }
}
