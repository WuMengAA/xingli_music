import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/desktop_sqflite_init.dart';
import 'core/throttled_binding.dart';
import 'core/theme/light_theme.dart';
import 'providers/color_memory/color_memory_providers.dart';
import 'services/log_service.dart';
import 'widgets/common/crash_screen.dart';

Future<void> main() async {
  // R22：帧率节流 binding —— 必须在任何 ensureInitialized 之前初始化，
  // 全局帧率限制（24/30/60/120）经 throttledFps 生效。
  // ⚠️ 只构造、不显式 initInstances()：Flutter binding 的构造函数已自动
  // 完成 initInstances（含 _instance 注册与各 mixin 初始化），再显式调用
  // 会让 ServicesBinding._defaultBinaryMessenger（late final）重复赋值
  // → LateInitializationError → 启动即崩（04:21 实测双端无法启动的根因）。
  ThrottledWidgetsBinding();

  // v2 M1 · 桌面端 sqflite 原生工厂注册：Windows/Linux/macOS 必须先初始化
  // FFI 才能使用全局 openDatabase API，否则启动即报
  // "databaseFactory not initialized"（Windows 桌面版实测）。
  initDesktopSqflite();

  // 首帧之前就把系统栏切成「透明底 + 深色图标」，避免浅色 UI 上出现
  // 白字状态栏的一帧闪烁（配合 app.dart 的 AnnotatedRegion 双保险）。
  SystemChrome.setSystemUIOverlayStyle(kLightOverlayStyle);
  // v2 M1 · P0-M1-4：整体适配横屏（宽 ≥ 600dp 时响应式重排）。
  // 竖屏布局保持 v1；横屏由各页按 AppSize.landscapeBreakpoint 重排。
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // ── 全局崩溃捕获：所有未处理异常都进 LogService（已脱敏；配置了日志
  // 服务器后会自动上报），用于真机定位闪退。─────────────────
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    LogService.instance.e(
      'crash',
      'Flutter 异常: ${details.exceptionAsString()}',
      details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    LogService.instance.e('crash', '平台异常: $error', stack);
    return true; // 已处理，避免向系统重复上报
  };

  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // ── 初始化阶段预热液态玻璃（R32 用户拍板：测试/预热必须在初始化阶段，
  // 不能等首帧渲染时才现编译 → 卡顿甚至 ANR/崩溃）──────────────
  // liquid_glass_widgets 官方要求：在 main() 里 `await` 后再 runApp。
  // Android GLES 下 glCompileShader+glLinkProgram 是同步编译（100~800ms），
  // 必须在 native splash 背后完成，否则 nativeSurfaceChanged 竞争 → ANR
  // （GitHub #187）。仅 Android 生效，iOS/macOS Metal 预编译零成本，跳过。
  // R33 黑屏防护：预热抛异常/超时不阻塞启动——失败仅降级（液态玻璃由
  // AdaptiveGlass 自身 FakeGlass 兜底，不渲染不等于黑屏）。
  try {
    await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false)
        .timeout(const Duration(seconds: 4));
    debugPrint('[startup] LiquidGlass 预热完成（shader + Impeller 管线）');
  } catch (e) {
    LogService.instance.w('startup', 'LiquidGlass 预热失败（降级继续）: $e');
  }

  // 根应用启动（初始 + 「崩溃界面」重新启动共用）。
  void runRoot() {
    runZonedGuarded(() {
      runApp(
        ProviderScope(
          overrides: [
            // 注入 SharedPreferences：配色记忆、使用行为等本地数据都存这里
            prefsProvider.overrideWithValue(prefs),
          ],
          child: const StelarithMusicApp(),
        ),
      );
    }, (Object error, StackTrace stack) {
      LogService.instance.e('crash', '未捕获异步异常: $error', stack);
    });
  }

  // R27（崩溃界面 = 程序最后底线）：构建期抛错不再显示默认红屏，而是渲染
  // [CrashScreen]——列出最近日志 + 「重新启动 / 日志上报」，程序不退出。
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      CrashScreen(details: details, onRestart: runRoot);

  runRoot();
}
