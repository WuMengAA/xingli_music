/// 网易云内嵌网页登录（Android 原生 WebView 抓取完整 cookie）。
///
/// 网易云登录主凭证 `MUSIC_U` 是 **HttpOnly**，网页 JS 读不到；因此不走
/// webview_flutter（其 CookieManager 只有 set/clear，无法读取），而是自写原生
/// [CookieWebViewActivity]（Java），登录成功后从 `CookieManager` 取出完整
/// cookie 串（含 httpOnly 项），经 MethodChannel 回传本封装。
///
/// 仅 Android 支持（原生通道在其它平台缺失）；非 Android 返回 null，
/// 上层回落到「粘贴 Cookie」路径。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// 与 MainActivity 注册的原生通道保持一致。
const MethodChannel _channel =
    MethodChannel('com.stelarith.xingli_music/webview_login');

/// 当前平台是否支持内嵌网页登录（仅 Android）。
bool get webviewLoginSupported => !kIsWeb && Platform.isAndroid;

/// 发起内嵌登录：打开网易云登录页，登录成功后返回完整 cookie 串；
/// 用户取消 / 平台不支持 / 通道缺失 → null。
Future<String?> startNeteaseWebviewLogin() async {
  if (!webviewLoginSupported) return null;
  try {
    return await _channel.invokeMethod<String>('startNeteaseLogin');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
