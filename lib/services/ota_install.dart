/// OTA 安装入口（cl74）：调用原生安装器安装已下载并校验通过的 APK。
///
/// 为什么走原生 MethodChannel 而非 Dart 直接起 Intent：
/// 1. Android 7+ 禁止 `file://` 暴露给外部应用（FileUriExposedException），
///    必须用 `FileProvider` 生成 `content://` URI；
/// 2. Android 8+ 安装未知来源 APK 需 `REQUEST_INSTALL_PACKAGES` 权限；
/// 3. Dart 侧构造 content URI + 调系统安装器最干净的做法是经原生
///    `FileProvider.getUriForFile` + `Intent.ACTION_VIEW`（见 MainActivity）。
///
/// 通道名与权限 authority 必须和 AndroidManifest / MainActivity 完全一致。
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'ota_service.dart';

/// 与原生约定一致的通道名 / authority。
const String kOtaInstallChannel = 'com.stelarith.xingli_music/ota_install';
const String kOtaFileProviderAuthority = 'com.stelarith.xingli_music.fileprovider';

/// OTA 安装（仅 Android 有效）。
class OtaInstall {
  OtaInstall._();

  static const MethodChannel _channel = MethodChannel(kOtaInstallChannel);

  /// 调系统安装器安装 [apkPath]。非 Android 或文件缺失 / 安装失败抛
  /// [OtaException]（消息可直接展示）。
  static Future<void> install(String apkPath) async {
    if (!Platform.isAndroid) {
      throw OtaException('当前平台不支持应用内安装更新');
    }
    final File f = File(apkPath);
    if (!f.existsSync()) {
      throw OtaException('安装包不存在：$apkPath');
    }
    try {
      await _channel.invokeMethod<void>('install', apkPath);
    } on PlatformException catch (e) {
      throw OtaException('安装失败：${e.message ?? e.code}');
    }
  }
}
