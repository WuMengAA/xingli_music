import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../log_service.dart';

/// 传感器服务（v2 实验 F 扩展）。
///
/// - **光线 lux**：自写原生 MethodChannel（`com.stelarith.xingli_music/sensors`
///   的 `TYPE_LIGHT`），**不依赖 light 插件**（其 minSdk 21 挡 Android 4.4）。
///   仅 Android 可用，其余平台 lux = null → 页面显示「当前设备不支持」。
/// - **加速度**：`sensors_plus`（Android/iOS），用于摇晃切场景。
/// - **陀螺仪**：`sensors_plus`（Android/iOS），实验页实时展示角速度。
/// - **心率**：原生 MethodChannel（`TYPE_HEART_RATE`，需 BODY_SENSORS 权限，
///   多数手机无此传感器 → 读取失败返回 null，页面显示「无心率传感器」）。
///
/// 权限说明为静态文案（并入同意 gate 与实验页，本地处理不上传）。
/// 所有订阅必须在 [dispose] 取消，防泄漏 / 耗电（架构 §7.10）。
class SensorService {
  static const MethodChannel _channel =
      MethodChannel('com.stelarith.xingli_music/sensors');

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  SensorService();

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 是否支持环境光（Android-only）。
  bool get lightSupported => _isAndroid;

  /// 环境光流（lux）。
  ///
  /// 非 Android / 读取失败 → 单发 `null`（页面展示「当前设备不支持」）。
  Stream<double?> lightLux() {
    if (!_isAndroid) {
      return Stream<double?>.value(null);
    }
    try {
      return _channel
          .invokeMethod<double>('lightLux')
          .asStream()
          .map<double?>((double? v) => v)
          .handleError((Object e, StackTrace st) {
        LogService.instance.w('sensor', '光线读取失败: $e');
      });
    } catch (e) {
      LogService.instance.w('sensor', '光线传感器初始化失败: $e');
      return Stream<double?>.value(null);
    }
  }

  /// 陀螺仪流（rad/s，Android/iOS）。
  Stream<GyroscopeEvent> gyroscope() {
    try {
      return gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval);
    } catch (e) {
      LogService.instance.w('sensor', '陀螺仪不可用: $e');
      return const Stream<GyroscopeEvent>.empty();
    }
  }

  /// 心率流（bpm；多数设备无此传感器 → 读取失败发 `null`）。
  Stream<double?> heartRate() {
    if (!_isAndroid) {
      return Stream<double?>.value(null);
    }
    try {
      return _channel
          .invokeMethod<double>('heartRate')
          .asStream()
          .map<double?>((double? v) => v)
          .handleError((Object e, StackTrace st) {
        LogService.instance.w('sensor', '心率读取失败: $e');
      });
    } catch (e) {
      LogService.instance.w('sensor', '心率传感器不可用: $e');
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
