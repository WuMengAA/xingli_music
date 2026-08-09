import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:light/light.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../log_service.dart';

/// 传感器服务（v2 实验 F · Q5 已裁决：仅光线 + 加速度）。
///
/// - **光线**：`light` 包（仅 Android，其余平台 lux = null → 页面显示
///   「当前设备不支持」）；用于场景亮度遮罩联动。
/// - **加速度**：`sensors_plus`（Android/iOS），用于摇晃切场景。
///
/// 权限说明为静态文案（并入同意 gate 与实验页，本地处理不上传）。
/// 所有订阅必须在 [dispose] 取消，防泄漏 / 耗电（架构 §7.10）。
class SensorService {
  final Light? _light;
  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  SensorService() : _light = _isAndroid ? Light() : null;

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 是否支持环境光（Android-only）。
  bool get lightSupported => _light != null;

  /// 环境光流（lux）。
  ///
  /// 非 Android / 读取失败 → 单发 `null`（页面展示「当前设备不支持」）。
  Stream<double?> lightLux() {
    final Light? light = _light;
    if (light == null) {
      return Stream<double?>.value(null);
    }
    try {
      return light.lightSensorStream
          .map<double?>((int v) => v.toDouble())
          .handleError((Object e, StackTrace st) {
        LogService.instance.w('sensor', '光线读取失败: $e');
      });
    } catch (e) {
      LogService.instance.w('sensor', '光线传感器初始化失败: $e');
      return Stream<double?>.value(null);
    }
  }

  /// 摇晃检测流（加速度模长超阈值触发 `true`，带 800ms 冷却防连发）。
  ///
  /// 桌面 / 不支持平台返回空流（页面置灰）。
  Stream<bool> shakeDetected() {
    final StreamController<bool> ctrl = StreamController<bool>.broadcast();
    DateTime lastShake = DateTime.now();
    try {
      final StreamSubscription<AccelerometerEvent> sub =
          accelerometerEventStream().listen(
        (AccelerometerEvent event) {
          final double mag = sqrt(event.x * event.x +
              event.y * event.y +
              event.z * event.z);
          if (mag > 2.2 &&
              DateTime.now().difference(lastShake) >
                  const Duration(milliseconds: 800)) {
            lastShake = DateTime.now();
            if (!ctrl.isClosed) ctrl.add(true);
          }
        },
        onError: (Object e) {
          LogService.instance.w('sensor', '加速度读取失败: $e');
        },
      );
      _subs.add(sub);
    } catch (e) {
      LogService.instance.w('sensor', '加速度传感器不可用: $e');
    }
    return ctrl.stream;
  }

  /// 取消全部订阅（Provider dispose 时调用）。
  void dispose() {
    for (final StreamSubscription<dynamic> s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}
