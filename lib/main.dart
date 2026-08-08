import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/light_theme.dart';
import 'providers/color_memory/color_memory_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 首帧之前就把系统栏切成「透明底 + 深色图标」，避免浅色 UI 上出现
  // 白字状态栏的一帧闪烁（配合 app.dart 的 AnnotatedRegion 双保险）。
  SystemChrome.setSystemUIOverlayStyle(kLightOverlayStyle);
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final SharedPreferences prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        // 注入 SharedPreferences：配色记忆、使用行为等本地数据都存这里
        prefsProvider.overrideWithValue(prefs),
      ],
      child: const StelarithMusicApp(),
    ),
  );
}
