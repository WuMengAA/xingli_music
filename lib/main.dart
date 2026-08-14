import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
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
