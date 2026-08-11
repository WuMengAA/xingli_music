import 'package:flutter/foundation.dart';

import '../../models/voxel.dart';

/// 2.5D 等距画布控制器（v2 M2-D / M5-1 共享渲染基础）。
///
/// 网格坐标 `(col, row)`，`col ∈ [0, cols)`，`row ∈ [0, rows)`；
/// 序列化 key = `"$col,$row"`（架构 §3.2.3 / §7.7）。
///
/// 维护：方块表、当前选中类型、撤销 / 重做栈、清空。
/// 小游戏与音效编辑器共用本控制器（Q3 已裁决）。
class VoxelCanvasController extends ChangeNotifier {
  VoxelCanvasController({
    this.cols = 8,
    this.rows = 8,
    VoxelBlockType? selected,
  }) : _selected = selected ?? kVoxelBlockTypes.first;

  final int cols;
  final int rows;

  /// 方块表：网格 key `"$col,$row"` → 类型 id。
  final Map<String, String> blocks = <String, String>{};

  VoxelBlockType _selected;
  VoxelBlockType get selected => _selected;
  set selected(VoxelBlockType value) {
    if (_selected.id == value.id) return;
    _selected = value;
    notifyListeners();
  }

  final List<Map<String, String>> _undoStack = <Map<String, String>>[];
  final List<Map<String, String>> _redoStack = <Map<String, String>>[];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  static String keyOf(int col, int row) => '$col,$row';

  /// 解析 key 为 (col, row)；格式非法返回 null。
  static (int, int)? parseKey(String key) {
    final List<String> parts = key.split(',');
    if (parts.length != 2) return null;
    final int? c = int.tryParse(parts[0]);
    final int? r = int.tryParse(parts[1]);
    if (c == null || r == null) return null;
    return (c, r);
  }

  bool inBounds(int col, int row) =>
      col >= 0 && col < cols && row >= 0 && row < rows;

  /// 放置当前选中类型的方块（覆盖已有）。
  void setBlock(int col, int row) {
    if (!inBounds(col, row)) return;
    final String key = keyOf(col, row);
    if (blocks[key] == _selected.id) return; // 无变化
    _pushUndo();
    blocks[key] = _selected.id;
    _redoStack.clear();
    notifyListeners();
  }

  /// 删除方块。
  void removeBlock(int col, int row) {
    final String key = keyOf(col, row);
    if (!blocks.containsKey(key)) return;
    _pushUndo();
    blocks.remove(key);
    _redoStack.clear();
    notifyListeners();
  }

  /// 切换：已有则删除，否则放置。
  void toggleBlock(int col, int row) {
    final String key = keyOf(col, row);
    if (blocks.containsKey(key)) {
      removeBlock(col, row);
    } else {
      setBlock(col, row);
    }
  }

  void _pushUndo() {
    _undoStack.add(Map<String, String>.of(blocks));
    if (_undoStack.length > 64) _undoStack.removeAt(0);
  }

  /// 撤销上一步。
  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(Map<String, String>.of(blocks));
    blocks
      ..clear()
      ..addAll(_undoStack.removeLast());
    notifyListeners();
  }

  /// 重做。
  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(Map<String, String>.of(blocks));
    blocks
      ..clear()
      ..addAll(_redoStack.removeLast());
    notifyListeners();
  }

  /// 清空画布。
  void clear() {
    if (blocks.isEmpty) return;
    _pushUndo();
    blocks.clear();
    _redoStack.clear();
    notifyListeners();
  }

  /// 从保存场景加载。
  void load(VoxelSoundScene scene) {
    blocks
      ..clear()
      ..addAll(Map<String, String>.of(scene.blocks));
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  /// 导出为保存模型。
  VoxelSoundScene toScene(String id, String name) => VoxelSoundScene(
        id: id,
        name: name,
        cols: cols,
        rows: rows,
        blocks: Map<String, String>.of(blocks),
      );

  /// 统计每类数量（混音用）。
  Map<String, int> countByType() {
    final Map<String, int> counts = <String, int>{};
    for (final String typeId in blocks.values) {
      counts[typeId] = (counts[typeId] ?? 0) + 1;
    }
    return counts;
  }

  /// 从 key 解析的 (col,row) 列表（小游戏用）。
  List<(int, int)> allCells() {
    final List<(int, int)> cells = <(int, int)>[];
    for (final String key in blocks.keys) {
      final (int, int)? p = parseKey(key);
      if (p != null) cells.add(p);
    }
    return cells;
  }
}
