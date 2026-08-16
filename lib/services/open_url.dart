/// ════════════════════════════════════════════════════════════════════════
/// 外部链接打开（cl75）：原生桥调系统浏览器，零新依赖。
/// ════════════════════════════════════════════════════════════════════════
///
/// 为什么走原生 MethodChannel 而非 [url_launcher]：保持「零新 pub 依赖」
/// （与 cl74 的 ota_install 思路一致）。Android 经 [MainActivity] 的
/// `open_url` 通道用 `Intent.ACTION_VIEW` 调系统浏览器；非 Android 或调用
/// 失败时回退到「复制链接并提示」，保证任何平台都不崩、都能用。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/notification/app_notify.dart';

/// 与原生约定的通道名。
const String kOpenUrlChannel = 'com.stelarith.xingli_music/open_url';

/// 打开外部链接。
class OpenUrl {
  OpenUrl._();

  static const MethodChannel _channel = MethodChannel(kOpenUrlChannel);

  /// 打开 [url]（完整 http(s) 链接）。
  ///
  /// - Android：经原生 `Intent.ACTION_VIEW` 调系统浏览器；
  /// - 其它平台 / 调用失败：复制到剪贴板并提示（[context] 提供时）。
  static Future<void> launch(BuildContext context, String url) async {
    if (!Platform.isAndroid) {
      await _copyFallback(context, url);
      return;
    }
    try {
      await _channel.invokeMethod<void>('open', url);
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      await _copyFallback(context, url, reason: e.message ?? e.code);
    }
  }

  static Future<void> _copyFallback(
    BuildContext context,
    String url, {
    String? reason,
  }) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      appNotify(
        context,
        reason == null ? '链接已复制：$url' : '无法打开（$reason），已复制链接',
      );
    }
  }
}
