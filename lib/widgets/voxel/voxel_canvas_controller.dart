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

  /// ── Module "MusicViz-2.5D"：音乐可视化状态 ──
  /// 每格静态高度比（0~1，来自 3D 世界提取）；缺省回落 [heightOf] 的 0.5。
  final Map<String, double> _cellHeights = <String, double>{};

  /// 当前帧：各频段能量（长度 = MusicEnvelope.bandCount，0~1）。
  List<double>? _vizBands;

  /// 当前帧：节拍强度（0~1，驱动顶面脉冲缩放）。
  double _vizBeat = 0;

  /// 当前帧：整体能量（0~1，驱动亮度呼吸）。
  double _vizLevel = 0;

  /// 单调递增版本号：每次应用一帧 envelope 自增，驱动 painter 重绘。
  int _vizVersion = 0;

  /// 可视化可调参数（随场景持久化；默认中性观感，与 Phase 1 原始一致）。
  VoxelVizSettings _vizSettings = VoxelVizSettings.defaults;

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
    if (blocks.isEmpty && _cellHeights.isEmpty) return;
    _pushUndo();
    blocks.clear();
    _cellHeights.clear();
    _resetViz();
    _redoStack.clear();
    notifyListeners();
  }

  /// 从保存场景加载。
  void load(VoxelSoundScene scene) {
    blocks
      ..clear()
      ..addAll(Map<String, String>.of(scene.blocks));
    _cellHeights
      ..clear()
      ..addAll(Map<String, double>.of(scene.heights));
    _vizSettings = scene.viz ?? VoxelVizSettings.defaults;
    _undoStack.clear();
    _redoStack.clear();
    _resetViz();
    notifyListeners();
  }

  /// 导出为保存模型。
  VoxelSoundScene toScene(String id, String name) => VoxelSoundScene(
        id: id,
        name: name,
        cols: cols,
        rows: rows,
        blocks: Map<String, String>.of(blocks),
        heights: Map<String, double>.of(_cellHeights),
        viz: _vizSettings,
      );

  // ── Module "MusicViz-2.5D"：可视化状态读写 ──

  /// 每格静态高度比（0~1）；无记录回落 0.5（中性高度）。
  double heightOf(String key) => _cellHeights[key] ?? 0.5;

  /// 批量写入高度比（3D 提取后调用，覆盖既有）。
  void setHeights(Map<String, double> heights) {
    _cellHeights
      ..clear()
      ..addAll(heights);
    notifyListeners();
  }

  /// 当前帧节拍强度（0~1）。
  double get vizBeat => _vizBeat;

  /// 当前帧整体能量（0~1）。
  double get vizLevel => _vizLevel;

  /// 当前帧各频段能量（长度 = bandCount，null = 尚未有真实/合成数据）。
  List<double>? get vizBands => _vizBands;

  /// 可视化版本号（每次应用一帧自增），painter 据此判断是否重绘。
  int get vizVersion => _vizVersion;

  /// 当前可视化参数（振幅 / 涟漪位置权重 / 节拍脉冲）。
  VoxelVizSettings get vizSettings => _vizSettings;

  /// 更新可视化参数并触发重绘（暂停未播放时也即时反映滑块调整）。
  void setVizSettings(VoxelVizSettings settings) {
    _vizSettings = settings;
    _vizVersion++;
    notifyListeners();
  }

  /// 某格绑定的频段索引（Phase 2 refined：位置涟漪 + 音色音高混合）。
  ///
  /// - **位置涟漪**：到画布中心的径向距离 → 频段由内向外扩散（同心环）。
  /// - **音色音高**：方块类型在预设表中的位置 → 低频音色(雨)落在低 band、
  ///   高频音色(虫鸣)落在高 band，让不同音景占据不同频段区，听感更"对位"。
  /// 两者加权混合（位置 0.55 + 音高 0.45），避免纯径向时所有同心环同频。
  int bandIndexFor(String key, int bandCount) {
    if (bandCount <= 1) return 0;
    final (int, int)? p = VoxelCanvasController.parseKey(key);
    if (p == null) return 0;

    // 位置涟漪：曼哈顿径向距离归一化到 [0,1]。
    final int cc = cols ~/ 2;
    final int cr = rows ~/ 2;
    final int dist = (p.$1 - cc).abs() + (p.$2 - cr).abs();
    final int maxDist = (cc + cr).clamp(1, 1 << 30);
    final double radialFrac = (dist / maxDist).clamp(0.0, 1.0);

    // 音色音高：类型在预设表索引 → [0,1]（rain 低 → cricket 高）。
    final String? typeId = blocks[key];
    final double pitchFrac;
    if (typeId == null) {
      pitchFrac = 0.5;
    } else {
      final int idx = kVoxelBlockTypes.indexOf(voxelBlockTypeById(typeId));
      pitchFrac = kVoxelBlockTypes.length <= 1
          ? 0.5
          : idx / (kVoxelBlockTypes.length - 1);
    }

    final double w = _vizSettings.ripplePosWeight.clamp(0.0, 1.0);
    final double combined = radialFrac * w + pitchFrac * (1 - w);
    final int idx = (combined * (bandCount - 1)).round();
    return idx.clamp(0, bandCount - 1);
  }

  /// 应用一帧 envelope 数据（[bands] 长度 = bandCount，[beat] 0~1）。
  /// 由 [envelopeSamplerProvider] / 合成 [VisualizerService] 每帧驱动。
  void applyEnvelope(List<double> bands, double beat) {
    _vizBands = bands;
    _vizBeat = beat.clamp(0.0, 1.0);
    double s = 0.0;
    for (final double b in bands) {
      s += b;
    }
    _vizLevel = bands.isEmpty ? 0.0 : (s / bands.length).clamp(0.0, 1.0);
    _vizVersion++;
    notifyListeners();
  }

  /// 复位可视化帧（无音乐/未播放时回落静态）。
  void _resetViz() {
    _vizBands = null;
    _vizBeat = 0;
    _vizLevel = 0;
    _vizVersion++;
  }

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
