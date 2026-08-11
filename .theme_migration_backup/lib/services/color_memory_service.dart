import 'storage/storage_service.dart';

/// 有记忆的渐变色 · 配色记忆服务
///
/// 配色偏移方向由用户的使用行为决定：
/// 在某个场景逗留越久，整体配色就越向该场景的色相靠拢。
/// 偏移量本身带有波动（会话抖动在 provider 层叠加），
/// 因此用户永远不会看到两次完全相同的配色。
class ColorMemoryService {
  static const String _key = 'color_memory_bias_degrees';

  final StorageService _storage;
  double _biasDegrees = 0;

  ColorMemoryService(this._storage) {
    _biasDegrees = _storage.getDouble(_key) ?? 0;
  }

  /// 当前记忆的色相偏移（度）
  double get biasDegrees => _biasDegrees;

  /// 记录一次逗留：场景越久，配色记忆越向其色相偏移
  ///
  /// [sceneHueDegrees] 场景基础色色相（0~360）
  /// [seconds] 逗留时长（秒）
  Future<void> addDwell({
    required double sceneHueDegrees,
    required double seconds,
  }) async {
    // 单次拉动力有限，避免一次切换就大幅染色
    final double pull =
        (sceneHueDegrees - _biasDegrees).clamp(-30.0, 30.0).toDouble();
    // 每 60 秒逗留推动约 15% 的拉动力（缓慢、平滑地"记住"）
    _biasDegrees = (_biasDegrees + pull * (seconds / 60.0) * 0.15) % 360.0;
    await _storage.setDouble(_key, _biasDegrees);
  }
}
