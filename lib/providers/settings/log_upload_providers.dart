/// 日志上报配置 + 上传器接线（配套官方 relay `/api/logs`，落盘 + 崩溃自动建 issue）。
///
/// - [logUploadEnabledProvider]：开关。**Alpha 渠道默认开**（内部压测自动收集崩溃），
///   Beta/RC/Release 默认关（隐私）；用户随时可手动关闭。
/// - [logUploadEndpointProvider]：服务端地址，默认官方 relay
///   `kDefaultContentBaseUrl`（不带 `/api/logs` 后缀，上传器自动拼）。
/// - [remoteLogUploaderProvider]：上传器单例，随配置实时生效并挂到
///   [LogService]（由 App 根组件 watch 保持存活）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../providers/content/content_providers.dart';
import '../../services/log_service.dart';
import '../../services/remote_log_uploader.dart';
import 'offline_providers.dart';

/// 上报开关（Alpha 渠道默认开，其余渠道默认关——隐私优先）。
final logUploadEnabledProvider = StateProvider<bool>(
  (ref) => AppVersion.channel == UpdateChannel.alpha,
);

/// 服务端地址（默认官方 relay 根；不带 /api/logs 后缀）。
final logUploadEndpointProvider = StateProvider<String>((ref) => kDefaultContentBaseUrl);

/// 详细日志（DEBUG 级）开关（默认开；关闭后 [LogService.d] 不再记录）。
final logDebugEnabledProvider = StateProvider<bool>((ref) => true);

/// 上传器单例：创建即生效，配置变化实时同步。
final remoteLogUploaderProvider = Provider<RemoteLogUploader>((ref) {
  final RemoteLogUploader uploader = RemoteLogUploader(
    endpoint: ref.read(logUploadEndpointProvider),
    // cl08：离线模式（不依靠官方服务器）→ 强制停用远程日志上传。
    enabled: ref.read(logUploadEnabledProvider) &&
        !ref.read(offlineModeProvider),
    // 健康快照：每次上报批次自动附错误/告警摘要（自动识别异常）。
    healthSummary: () => LogService.instance.healthSummary,
  );
  ref.onDispose(uploader.dispose);
  ref.listen<String>(
    logUploadEndpointProvider,
    (_, String v) => uploader.setEndpoint(v),
  );
  ref.listen<bool>(
    logUploadEnabledProvider,
    (_, bool v) => uploader.setEnabled(v),
  );
  // 挂到全局日志：此后 LogService 每条脱敏日志都会进上传器缓冲。
  LogService.instance.remote = uploader;
  return uploader;
});
