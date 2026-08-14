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

  /// 光标 / 手持物品（点选拾取后临时拿在手上、跟随鼠标 / 显示在面板顶部的物品）。
  ///
  /// Cl29_hotfix：引入 MC 式「鼠标拾取」交互模型，替代旧拖拽换位。
  ItemStack _cursor = ItemStack.empty;

  /// 光标上的物品（空 = 未手持）。
  ItemStack get cursor => _cursor;

  /// 是否正手持物品（点选后）。
  bool get carrying => !_cursor.isEmpty;

  /// 左键点击某格：
  /// - 未手持 → 整堆拾取到光标（原格清空）。
  /// - 手持 → 落位（空格整堆放、同类填满、不同类交换）。
  void clickSlot(int index) {
    if (index < 0 || index >= _slots.length) return;
    if (_cursor.isEmpty) {
      final ItemStack s = _slots[index];
      if (s.isEmpty) return;
      _cursor = s;
      _slots[index] = ItemStack.empty;
    } else {
      _dropInto(index);
    }
    notifyListeners();
  }

  /// 右键 / 长按：
  /// - 未手持 → 拾取一半（仅 1 个则整堆拾取）。
  /// - 手持 → 向该格放 1 个（空或同类未满）；不同类或已满不操作。
  void rightSlot(int index) {
    if (index < 0 || index >= _slots.length) return;
    if (_cursor.isEmpty) {
      final ItemStack s = _slots[index];
      if (s.isEmpty) return;
      final int half = s.count ~/ 2;
      if (half <= 0) {
        _cursor = s;
        _slots[index] = ItemStack.empty;
      } else {
        _cursor = ItemStack(s.item, half);
        _slots[index] = s.plus(-half);
      }
    } else {
      final ItemStack t = _slots[index];
      if (!t.isEmpty && t.item != _cursor.item) return; // 不同类不操作
      // 以「光标物品」的堆叠上限判满——空目标(t.count=0、maxStack=air 的 0)
      // 不能用 t.maxStack（会 0>=0 误判为已满而拒绝放置）。
      if (t.count >= _cursor.maxStack) return; // 已满不操作
      // 空格目标须用光标物品起堆：t.plus(1) 会沿用空格的 air 物品 → 错。
      _slots[index] = t.isEmpty ? ItemStack(_cursor.item, 1) : t.plus(1);
      _cursor = _cursor.plus(-1);
    }
    notifyListeners();
  }

  /// 落位逻辑（左键 / 数字键手持时调用）。
  void _dropInto(int index) {
    final ItemStack t = _slots[index];
    if (t.isEmpty) {
      _slots[index] = _cursor;
      _cursor = ItemStack.empty;
      return;
    }
    if (t.item == _cursor.item) {
      final int room = t.maxStack - t.count;
      if (room > 0) {
        final int move = _cursor.count < room ? _cursor.count : room;
        _slots[index] = t.plus(move);
        _cursor = _cursor.plus(-move);
      }
      return; // 满则不动
    }
    // 不同类 → 交换
    _slots[index] = _cursor;
    _cursor = t;
  }

  /// 数字键 1-9：把光标物品迁移到对应快捷栏槽位（落位逻辑同左键）。
  void cursorToHotbar(int n) {
    if (!carrying || n < 1 || n > hotbarSize) return;
    _dropInto(n - 1);
    notifyListeners();
  }

  /// 关闭面板时把光标物品归还背包（避免悬空导致世界手持错乱）。
  void returnCursor() {
    if (_cursor.isEmpty) return;
    final int left = add(_cursor);
    if (left == 0) {
      _cursor = ItemStack.empty;
    } else {
      // 背包真满（全异类且无空格）兜底：原地放回首个空格；仍无则保留光标。
      for (int i = 0; i < _slots.length; i++) {
        if (_slots[i].isEmpty) {
          _slots[i] = _cursor;
          _cursor = ItemStack.empty;
          break;
        }
      }
    }
    notifyListeners();
  }

  /// 强制清空光标（切世界 / 重置时）。
  void clearCursor() {
    if (_cursor.isEmpty) return;
    _cursor = ItemStack.empty;
    notifyListeners();
  }

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
    _cursor = ItemStack.empty;
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
        'cursor': _cursor.toJson(),
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
    final Map<String, dynamic>? cur =
        j['cursor'] as Map<String, dynamic>?;
    _cursor = cur == null ? ItemStack.empty : ItemStack.fromJson(cur);
    _selected = ((j['selected'] as num?)?.toInt() ?? 0) % hotbarSize;
    notifyListeners();
  }
}
