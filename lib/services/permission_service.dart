/// ════════════════════════════════════════════════════════════════════════
/// 运行时权限服务（R13）
/// ════════════════════════════════════════════════════════════════════════
///
/// 目标：通知 / 存储 / 媒体读取权限全部在应用内主动申请（Android 13+ 分级），
/// 拒绝后给引导、可跳系统设置重新授权 —— **不再依赖 adb 授权**。
///
/// 权限清单：
///  - 通知（POST_NOTIFICATIONS，Android 13+）：通知栏静默媒体通知（R14）
///  - 存储 / 媒体音频（READ_MEDIA_AUDIO 或 READ_EXTERNAL_STORAGE）：本地曲库
///  - 麦克风（可选）：传感器实验（摇晃切场景等不需要，仅降级提示）
library;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'log_service.dart';

/// 权限服务（静态方法集）。
abstract final class PermissionService {
  /// 启动时申请「必要权限」：通知 + 存储。
  ///
  /// 静默执行（不弹解释框，直接请求系统弹窗），失败不阻塞启动。
  static Future<void> requestEssentialOnStartup() async {
    if (kIsWeb) return;
    try {
      await _requestIfNotGranted(Permission.notification);
      await _requestIfNotGranted(Permission.storage);
    } catch (e) {
      LogService.instance.w('perm', '启动权限申请异常: $e');
    }
  }

  /// 手动申请全部权限（设置页「权限与授权」入口调用）。
  ///
  /// 返回最终是否全部通过。
  static Future<bool> requestAll() async {
    if (kIsWeb) return true;

    final Map<Permission, PermissionStatus> results =
        await <Permission>[
      Permission.notification,
      Permission.storage,
    ].request();

    bool ok = true;
    results.forEach((Permission p, PermissionStatus s) {
      LogService.instance.i('perm', '${p.toString()} -> ${s.name}');
      if (!s.isGranted) ok = false;
    });

    // 麦克风：实验功能，非必要；仅当被永久拒绝时提示跳转
    if (await Permission.microphone.isPermanentlyDenied) {
      LogService.instance.w('perm', '麦克风被永久拒绝（实验功能降级）');
    }

    // 有被永久拒绝的 → 引导去系统设置
    if (await Permission.notification.isPermanentlyDenied ||
        await Permission.storage.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    return ok;
  }

  /// 查询权限总览（设置页展示用）。
  static Future<Map<String, bool>> overview() async {
    if (kIsWeb) return <String, bool>{'通知': true, '存储': true};
    return <String, bool>{
      '通知': await Permission.notification.isGranted,
      '存储/媒体': await Permission.storage.isGranted,
      '麦克风(实验)': await Permission.microphone.isGranted,
    };
  }

  static Future<void> _requestIfNotGranted(Permission p) async {
    try {
      if (await p.isGranted) return;
      await p.request();
    } catch (_) {
      // 单个权限失败不影响其它
    }
  }
}
