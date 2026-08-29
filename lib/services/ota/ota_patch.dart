/// ════════════════════════════════════════════════════════════════════════
/// OTA 补丁基线管理（cl76_hotfix5：增量差分热修复）
/// ════════════════════════════════════════════════════════════════════════
///
/// 增量补丁需要一个「旧 APK 基线」才能合成新包。Android 上**无法直接读
/// /data/app 下已安装包的字节**，所以首次启动/安装后把当前 APK 复制一份到
/// 私有 files 目录（`ota_base.apk`）；下次更新下载补丁 → 基线+补丁合成新包 →
/// 校验通过后把新包提升为新基线，如此迭代。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/paths.dart';

/// 取当前安装包路径的原生通道（MainActivity 注册）。
const String kAppInfoChannel = 'com.stelarith.xingli_music/app_info';

/// OTA 补丁基线。
class OtaPatchBase {
  OtaPatchBase._();

  static const MethodChannel _channel = MethodChannel(kAppInfoChannel);

  /// 当前安装包绝对路径（原生 `sourceDir`；非 Android / 失败返回空串）。
  static Future<String> sourceDir() async {
    if (!Platform.isAndroid) return '';
    try {
      final String? s = await _channel.invokeMethod<String>('sourceDir');
      return s ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> _basePath() async {
    final Directory dir = await appDataDir();
    return p.join(dir.path, 'ota_base.apk');
  }

  /// 确保补丁合成基线存在（首次则复制当前安装包；已存在直接返回）。
  /// 返回基线路径；无法取得（非 Android / 复制失败）返回 null。
  static Future<String?> ensureBase() async {
    final String base = await _basePath();
    if (File(base).existsSync()) return base;
    final String src = await sourceDir();
    if (src.isEmpty) return null;
    try {
      await File(src).copy(base);
      return base;
    } catch (_) {
      return null;
    }
  }

  /// 补丁合成并通过 SHA-256 校验后，把新 APK 提升为新基线（供下次补丁）。
  static Future<void> promoteBase(String newApk) async {
    final String base = await _basePath();
    try {
      final File src = File(newApk);
      if (src.existsSync()) await src.copy(base);
    } catch (_) {}
  }

  /// 删除旧基线（可选：应用更新替换自身后基线可能已过期）。
  static Future<void> clearBase() async {
    try {
      final File f = File(await _basePath());
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}
