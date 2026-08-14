/// 哔哩哔哩内嵌网页登录（复用网易云同款原生 WebView 通道）。
///
/// B站关键登录凭证 `SESSDATA` 是 **HttpOnly**，网页 JS 读不到；因此复用自写
/// 原生 [CookieWebViewActivity]（已扩展支持 bilibili 类型），加载桌面模式的 B站
/// 官方登录页（`https://passport.bilibili.com/login`，桌面 UA），用户在网页里
/// 扫码（页面自带的标准 Web 二维码，B站 App 可正常识别）或输账号登录，原生层
/// 从 `CookieManager` 取出完整 cookie 串（含 httpOnly 项），经 MethodChannel
/// 回传本封装。
///
/// 仅 Android 支持（原生通道在其它平台缺失）；非 Android 返回 null，
/// 上层回落到「粘贴 Cookie」路径。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// 与 MainActivity 注册的原生通道保持一致（与网易云同一通道）。
const MethodChannel _channel =
    MethodChannel('com.stelarith.xingli_music/webview_login');

/// 当前平台是否支持内嵌网页登录（仅 Android）。
bool get webviewLoginSupported => !kIsWeb && Platform.isAndroid;

/// 发起内嵌登录：打开 B站桌面登录页，登录成功后返回完整 cookie 串；
/// 用户取消 / 平台不支持 / 通道缺失 → null。
Future<String?> startBilibiliWebviewLogin() async {
  if (!webviewLoginSupported) return null;
  try {
    return await _channel.invokeMethod<String>('startBilibiliLogin');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
