/// OTA 下载控制器（cl61）：全局单例，支持**挂后台下载**。
///
/// 下载任务由 [OtaDownloadNotifier.start] 持有并推进，不依赖任何页面
/// context——用户关闭「版本更新」面板后下载继续；完成/失败经状态广播，
/// 由 AppShell 等常驻层监听并弹全局通知。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/ota_service.dart';

/// 下载阶段。
enum OtaPhase { idle, downloading, done, error }

/// OTA 下载状态（进度 / 网速 / 结果）。
class OtaDownloadState {
  const OtaDownloadState({
    this.phase = OtaPhase.idle,
    this.tag = '',
    this.fraction = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.apkPath = '',
    this.error,
  });

  final OtaPhase phase;

  /// 目标版本 tag（如 `cl61`）。
  final String tag;

  /// 0~1 下载进度。
  final double fraction;

  final int receivedBytes;
  final int totalBytes;

  /// 实时网速（字节/秒，EMA 平滑）。
  final double speedBytesPerSec;

  /// 校验通过后的安装包路径（phase == done 时有效）。
  final String apkPath;

  /// 错误消息（phase == error 时有效）。
  final String? error;

  bool get isDownloading => phase == OtaPhase.downloading;
  bool get isDone => phase == OtaPhase.done;
  bool get isError => phase == OtaPhase.error;

  OtaDownloadState copyWith({
    OtaPhase? phase,
    String? tag,
    double? fraction,
    int? receivedBytes,
    int? totalBytes,
    double? speedBytesPerSec,
    String? apkPath,
    String? error,
  }) {
    return OtaDownloadState(
      phase: phase ?? this.phase,
      tag: tag ?? this.tag,
      fraction: fraction ?? this.fraction,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      apkPath: apkPath ?? this.apkPath,
      error: error ?? this.error,
    );
  }
}

/// 全局 OTA 下载控制器（单例，跨页面存活 = 后台下载）。
final otaDownloadProvider =
    StateNotifierProvider<OtaDownloadNotifier, OtaDownloadState>(
  (ref) => OtaDownloadNotifier(),
);

class OtaDownloadNotifier extends StateNotifier<OtaDownloadState> {
  OtaDownloadNotifier() : super(const OtaDownloadState());

  /// 启动下载（幂等：已在下载中则忽略）。返回后调用方可安全离开页面。
  /// [abi] 不选则下载时按设备架构自动选拆分包。
  Future<void> start(String tag, {DeviceAbi? abi}) async {
    if (state.isDownloading) return;
    state = OtaDownloadState(phase: OtaPhase.downloading, tag: tag);
    try {
      final String apkPath = await OtaService.instance.downloadAndVerify(
        tag,
        abi: abi,
        onProgress: (OtaProgress p) {
          if (mounted) {
            state = state.copyWith(
              fraction: p.fraction,
              receivedBytes: p.receivedBytes,
              totalBytes: p.totalBytes,
              speedBytesPerSec: p.speedBytesPerSec,
            );
          }
        },
      );
      if (mounted) {
        state = state.copyWith(phase: OtaPhase.done, apkPath: apkPath);
      }
    } on OtaException catch (e) {
      if (mounted) {
        state = state.copyWith(phase: OtaPhase.error, error: e.message);
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(phase: OtaPhase.error, error: '更新失败，请检查网络后重试');
      }
    }
  }

  /// 重置（回到 idle，便于再次检查）。
  void reset() => state = const OtaDownloadState();
}
