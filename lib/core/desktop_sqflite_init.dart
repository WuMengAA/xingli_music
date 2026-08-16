import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 桌面端（Windows / Linux / macOS）sqflite FFI 初始化。
///
/// sqflite 在 Android/iOS 会自动注册 [databaseFactory]，但在桌面端需要显式：
/// 1. [sqfliteFfiInit] 加载原生 sqlite3 动态库；
/// 2. [databaseFactory = databaseFactoryFfi] 替换全局工厂。
///
/// 必须在首次调用 [openDatabase] 之前执行（通常放在 main() 首帧前）。
/// Web 端直接无操作。
void initDesktopSqflite() {
  if (kIsWeb) return;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
