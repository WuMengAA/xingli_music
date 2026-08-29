/// OTA 更新服务（cl55-G7）：检查 GitHub Releases → 下载 → SHA-256 校验。
///
/// 流程：
/// 1. `checkForUpdate()`：调 GitHub Releases API（`/repos/WuMengAA/xingli_music/releases`），
///    取最新 tag（`cl*` / `v*`），解析出构建号；
/// 2. 比对当前 [AppVersion.buildCount]：tag 构建号更高 → 有更新；
///    `-hotfix` 标记 → 直接进入下载（不弹确认）；
/// 3. `download()`：下载 Release 资产 `app-release.apk` 到应用文档目录，
///    同时下载 `.sha256` 资产；
/// 4. 下载完成后校验 SHA-256，通过返回安装包路径，供上层提示安装。
///
/// 仓库地址集中在此，可切换官方源（GitHub Releases 为默认 OTA 源）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/services.dart';

import '../core/app_version.dart';
import 'log_service.dart';

/// OTA 仓库（开源 + Releases 源）。
const String kOtaRepoOwner = 'WuMengAA';
const String kOtaRepoName = 'xingli_music';
const String kOtaReleaseApi =
    'https://api.github.com/repos/$kOtaRepoOwner/$kOtaRepoName/releases';

/// 设备架构（用于 OTA 选对应拆分包）。
enum DeviceAbi {
  arm64,
  arm32,
  unknown,
}

/// 按设备架构映射到 Release 中的拆分包资产名（不再有 universal 整包）。
String otaApkAssetForAbi(DeviceAbi abi) =>
    abi == DeviceAbi.arm32
        ? 'app-armeabi-v7a-release.apk'
        : 'app-arm64-v8a-release.apk';

/// 拆分包对应的 sha256 资产名。
String otaShaAssetForAbi(DeviceAbi abi) =>
    '${otaApkAssetForAbi(abi)}.sha256';

/// 一次更新检查的结果。
class OtaCheckResult {
  const OtaCheckResult({
    required this.latestTag,
    required this.latestBuild,
    required this.isHotfix,
    required this.hasUpdate,
    required this.releaseNotes,
    this.latestDateKey = -1,
    this.latestChannel = UpdateChannel.beta,
  });

  final String latestTag;

  /// 最新 Release 的构建号（从 tag 解析；解析失败为 -1）。
  final int latestBuild;

  /// 最新 Release 的日期键（YYMMDD 数字，新格式 tag；旧格式为 -1）。
  final int latestDateKey;

  /// 最新 Release 的渠道（新格式 tag 解析）。
  final UpdateChannel latestChannel;

  /// 是否 hotfix（tag 含 `-hotfix` / `_hotfix`）→ 直接下载。
  final bool isHotfix;

  /// 是否有可应用的新版本（渠道内按「日期优先、同日比 cl」判定）。
  final bool hasUpdate;

  /// Release 说明（body，即该版本更新日志）。
  final String releaseNotes;

  static const OtaCheckResult none = OtaCheckResult(
    latestTag: '',
    latestBuild: -1,
    isHotfix: false,
    hasUpdate: false,
    releaseNotes: '',
  );
}

/// 新格式 tag 解析结果：`0.26.8.17_beta_cl01` / `0.26.8.17_beta_cl01_hotfix1`。
class OtaTagInfo {
  OtaTagInfo({
    required this.tag,
    required this.dateKey,
    required this.channel,
    required this.build,
    this.hotfix,
    this.notes = '',
  });

  final String tag;
  /// 日期键：`year*10000 + month*100 + day`（如 2026-08-17 → 20260817）。
  final int dateKey;
  final UpdateChannel channel;
  final int build;
  final int? hotfix;
  String notes;

  /// 该 Release 内含的安卓拆分包架构（从资产名推断）。
  Set<DeviceAbi> androidAbis = <DeviceAbi>{};
  /// 是否含 Windows 构建（portable.zip / setup.exe）。
  bool hasWindows = false;
  /// Windows 架构标记（从文件名推断，如 x64；当前单架构）。
  Set<String> windowsArches = <String>{};

  /// 是否比当前版本新（2026-08-17 渠道化定版）：**先比日期、同日再比 cl**，
  /// cl 不再单独决定新旧（跨天 cl 清零不会误判）；hotfix 与当前同版本也算
  /// 有更新（修复缺陷的补丁包）。
  bool newerThanCurrent(int currentDateKey, int currentBuild) {
    if (dateKey > currentDateKey) return true;
    if (dateKey == currentDateKey) {
      if (build > currentBuild) return true;
      if (build >= currentBuild && hotfix != null) return true;
    }
    return false;
  }
}

/// 解析新格式 tag：`0.26.8.17_beta_cl01` / `0.26.8.17_beta_cl01_hotfix1`。
/// 非新格式（历史 `cl*`/`v*`、缺渠道段）返回 null。
OtaTagInfo? parseOtaTag(String tag) {
  final RegExp re = RegExp(
    r'^0\.(\d+)\.(\d+)\.(\d+)_(beta|alpha)_cl(\d+)(?:_hotfix(\d+))?$',
    caseSensitive: false,
  );
  final Match? m = re.firstMatch(tag.trim());
  if (m == null) return null;
  final int year = int.tryParse(m.group(1)!) ?? 0;
  final int month = int.tryParse(m.group(2)!) ?? 0;
  final int day = int.tryParse(m.group(3)!) ?? 0;
  final int build = int.tryParse(m.group(5)!) ?? -1;
  if (build < 0) return null;
  return OtaTagInfo(
    tag: tag,
    dateKey: year * 10000 + month * 100 + day,
    channel: UpdateChannel.fromTag(m.group(4)!),
    build: build,
      hotfix: int.tryParse(m.group(6) ?? ''),
    );
  }

  /// 从 Release 资产列表推断该版本的平台/架构标记（安卓拆分包 + Windows）。
  void _applyReleaseAssets(OtaTagInfo info, Map<String, dynamic> r) {
    final List<dynamic> assets = (r['assets'] as List<dynamic>?) ?? <dynamic>[];
    for (final dynamic a in assets) {
      final Map<String, dynamic> asset = a as Map<String, dynamic>;
      final String name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        if (name.contains('arm64-v8a')) {
          info.androidAbis.add(DeviceAbi.arm64);
        } else if (name.contains('armeabi-v7a')) {
          info.androidAbis.add(DeviceAbi.arm32);
        }
      } else if (name.endsWith('.exe') ||
          (name.endsWith('.zip') && name.contains('win'))) {
        info.hasWindows = true;
        info.windowsArches.add(name.contains('arm64') ? 'arm64' : 'x64');
      }
    }
  }

  /// 下载进度（cl61）：已下载 / 总量 / 实时网速（字节每秒）。
class OtaProgress {
  const OtaProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.speedBytesPerSec,
  });

  final int receivedBytes;
  final int totalBytes;
  final double speedBytesPerSec;

  /// 0~1 进度（总量未知时按 -1 处理为 0）。
  double get fraction =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0;
}

/// OTA 服务单例。
class OtaService {
  OtaService._();
  static final OtaService instance = OtaService._();

  /// 设备架构检测通道（对应 MainActivity 的 com.stelarith.xingli_music/device）。
  static const MethodChannel _deviceChannel =
      MethodChannel('com.stelarith.xingli_music/device');

  final http.Client _client = http.Client();

  /// 检测设备主架构（arm64 / arm32），用于 OTA 选对应拆分包。
  /// 失败/未知统一回落 arm64（现代设备绝大多数）。
  static Future<DeviceAbi> detectDeviceAbi() async {
    try {
      final String? s =
          await _deviceChannel.invokeMethod<String>('getPrimaryAbi');
      final String a = (s ?? '').toLowerCase();
      if (a.contains('arm64')) return DeviceAbi.arm64;
      if (a.contains('v7a') || a.contains('armeabi')) return DeviceAbi.arm32;
      return DeviceAbi.arm64;
    } catch (_) {
      return DeviceAbi.arm64;
    }
  }

  /// 检查 GitHub Releases 是否有新版本（仅当前渠道）。
  ///
  /// 新旧判断（2026-08-17 渠道化定版）：tag 需为新格式
  /// `0.26.8.<day>_<channel>_cl<NN>`；**只比较 [channel] 渠道**的 Release；
  /// **先比日期、同日再比 cl**——cl 不再单独决定新旧，跨天 cl 清零不会误判
  /// （历史坑：cl78 > cl01 误判"有更新"）。历史 `cl*`/`v*` tag（无日期）忽略。
  /// 失败（网络 / 无 Release / 解析失败）返回 [OtaCheckResult.none]，不抛。
  Future<OtaCheckResult> checkForUpdate({
    UpdateChannel channel = UpdateChannel.beta,
  }) async {
    try {
      final http.Response resp = await _client
          .get(Uri.parse(kOtaReleaseApi))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        LogService.instance.w('ota', '检查更新 HTTP ${resp.statusCode}');
        return OtaCheckResult.none;
      }
      final List<dynamic> releases =
          jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      if (releases.isEmpty) return OtaCheckResult.none;
      // 遍历所有非 draft 的 Release：只取「当前渠道 + 新格式 tag」中
      // (日期, cl) 最大者（日期大者新；同日 cl 大者新；不依赖返回顺序）。
      OtaTagInfo? best;
      for (final dynamic item in releases) {
        final Map<String, dynamic> r = item as Map<String, dynamic>;
        if (r['draft'] == true) continue;
        final String tag = (r['tag_name'] as String?)?.trim() ?? '';
        if (tag.isEmpty) continue;
        final OtaTagInfo? info = parseOtaTag(tag);
        if (info == null || info.channel != channel) continue;
        _applyReleaseAssets(info, r);
        if (best == null ||
            info.dateKey > best.dateKey ||
            (info.dateKey == best.dateKey && info.build > best.build)) {
          best = info..notes = (r['body'] as String?) ?? '';
        }
      }
      if (best == null) return OtaCheckResult.none;
      final int currentDateKey = _currentDateKey;
      final int currentBuild = AppVersion.buildCount;
      final bool hasUpdate = best.newerThanCurrent(currentDateKey, currentBuild);
      LogService.instance.i(
          'ota',
          '检查更新: 最新=${best.tag} date=${best.dateKey} cl=${best.build} '
          '渠道=${best.channel.tag} | 当前 date=$currentDateKey '
          'cl=$currentBuild 渠道=${channel.tag} 有更新=$hasUpdate');
      return OtaCheckResult(
        latestTag: best.tag,
        latestBuild: best.build,
        latestDateKey: best.dateKey,
        latestChannel: best.channel,
        isHotfix: best.hotfix != null,
        hasUpdate: hasUpdate,
        releaseNotes: best.notes,
      );
    } catch (e) {
      LogService.instance.w('ota', '检查更新失败: $e');
      return OtaCheckResult.none;
    }
  }

  /// 当前版本日期键（YYMMDD 数字）。
  static int get _currentDateKey =>
      AppVersion.year * 10000 + AppVersion.month * 100 + AppVersion.day;

  // ── 更新日志本地缓存（2026-08-17 渠道化：网络拉取、按渠道分离）──
  static const String _kCachedNotesKey = 'ota_cached_notes';
  static const String _kCachedNotesTagKey = 'ota_cached_notes_tag';

  /// 启动时拉取当前渠道最新 Release 的说明（更新日志）并缓存本地。
  /// 供设置页「更新日志」查看；网络失败沿用旧缓存。返回是否拉到新内容。
  Future<bool> refreshCachedNotes({
    UpdateChannel channel = UpdateChannel.beta,
  }) async {
    try {
      final http.Response resp = await _client
          .get(Uri.parse(kOtaReleaseApi))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return false;
      final List<dynamic> releases =
          jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      OtaTagInfo? best;
      for (final dynamic item in releases) {
        final Map<String, dynamic> r = item as Map<String, dynamic>;
        if (r['draft'] == true) continue;
        final String tag = (r['tag_name'] as String?)?.trim() ?? '';
        final OtaTagInfo? info = parseOtaTag(tag);
        if (info == null || info.channel != channel) continue;
        _applyReleaseAssets(info, r);
        if (best == null ||
            info.dateKey > best.dateKey ||
            (info.dateKey == best.dateKey && info.build > best.build)) {
          best = info..notes = (r['body'] as String?) ?? '';
        }
      }
      if (best == null || best.notes.trim().isEmpty) return false;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCachedNotesKey, best.notes);
      await prefs.setString(_kCachedNotesTagKey, best.tag);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 读取本地缓存的更新日志（无缓存返回 null）。
  static Future<String?> cachedNotes() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCachedNotesKey);
  }

  /// 读取本地缓存的更新日志对应版本 tag（无缓存返回 null）。
  static Future<String?> cachedNotesTag() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCachedNotesTagKey);
  }

  /// 列出当前渠道所有（非 draft）Release 版本，按 (日期, cl) 倒序，
  /// 供更新面板「多版本选择」。每项含 notes（Release body）。
  /// 网络失败返回空列表（不抛）。
  Future<List<OtaTagInfo>> listChannelReleases(
      UpdateChannel channel) async {
    try {
      final http.Response resp = await _client
          .get(Uri.parse(kOtaReleaseApi))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return const <OtaTagInfo>[];
      final List<dynamic> releases =
          jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      final List<OtaTagInfo> out = <OtaTagInfo>[];
      for (final dynamic item in releases) {
        final Map<String, dynamic> r = item as Map<String, dynamic>;
        if (r['draft'] == true) continue;
        final String tag = (r['tag_name'] as String?)?.trim() ?? '';
        if (tag.isEmpty) continue;
        final OtaTagInfo? info = parseOtaTag(tag);
        if (info == null || info.channel != channel) continue;
        _applyReleaseAssets(info, r);
        out.add(info..notes = (r['body'] as String?) ?? '');
      }
      out.sort((OtaTagInfo a, OtaTagInfo b) {
        if (a.dateKey != b.dateKey) {
          return b.dateKey.compareTo(a.dateKey);
        }
        return b.build.compareTo(a.build);
      });
      return out;
    } catch (_) {
      return const <OtaTagInfo>[];
    }
  }

  /// 下载 Release 中「适配本机架构」的拆分包并校验 SHA-256。
  ///
  /// [abi] 不传则自动检测设备架构；据此选 `app-arm64-v8a-release.apk`
  /// 或 `app-armeabi-v7a-release.apk`（不再有 universal 整包）。
  /// [onProgress] 在下载期间持续回调进度（字节 / 网速），供 UI 展示；
  /// 下载不依赖调用方生命周期（调用方销毁后 Future 继续跑，即「挂后台」）。
  /// 返回安装包路径（校验通过）；失败抛 [OtaException]（消息可直接展示）。
  Future<String> downloadAndVerify(
    String tag, {
    DeviceAbi? abi,
    void Function(OtaProgress progress)? onProgress,
  }) async {
    abi ??= await detectDeviceAbi();
    final String asset = otaApkAssetForAbi(abi);
    final String shaAsset = otaShaAssetForAbi(abi);
    final String url =
        'https://github.com/$kOtaRepoOwner/$kOtaRepoName/releases/download/$tag/$asset';
    final String shaUrl =
        'https://github.com/$kOtaRepoOwner/$kOtaRepoName/releases/download/$tag/$shaAsset';

    final Directory dir = await appDataDir();
    final String apkPath = p.join(dir.path, 'ota_${tag}_$asset');

    // 1) 下载 sha256 期望值（对应架构拆分包）。
    final String expected = await _fetchSha256(shaUrl);

    // 2) 拆分包下载（流式，回调进度）。
    await _download(url, apkPath, onProgress: onProgress);

    // 3) 校验。
    final String actual = await _sha256OfFile(apkPath);
    if (expected.isNotEmpty && actual != expected) {
      throw OtaException(
        '哈希校验失败\n期望 $expected\n实际 $actual\n请勿安装，可能被篡改。',
      );
    }
    return apkPath;
  }

  Future<String> _fetchSha256(String url) async {
    try {
      final http.Response resp = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return '';
      final String body = utf8.decode(resp.bodyBytes).trim();
      // 格式："<hash>  <filename>" 或 "<hash>"，取首个 64 位 hex。
      final Match? m = RegExp(r'[0-9a-fA-F]{64}').firstMatch(body);
      return m?.group(0)?.toLowerCase() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 流式下载到文件，边下边回调进度（已下载 / 总量 / 实时网速）。
  Future<void> _download(
    String url,
    String path, {
    void Function(OtaProgress progress)? onProgress,
  }) async {
    final http.Request req = http.Request('GET', Uri.parse(url));
    final http.StreamedResponse resp =
        await _client.send(req).timeout(const Duration(minutes: 2));
    if (resp.statusCode != 200) {
      throw OtaException('下载失败（HTTP ${resp.statusCode}）');
    }
    final int total = resp.contentLength ?? -1;
    final File f = File(path);
    final IOSink sink = f.openWrite();
    int received = 0;
    final Stopwatch sw = Stopwatch()..start();
    int lastBytes = 0;
    double speed = 0;
    try {
      await for (final List<int> chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        final int now = sw.elapsedMilliseconds;
        if (now >= 400) {
          // 实时网速：本窗口字节 / 窗口时长（EMA 平滑）。
          final double inst = (received - lastBytes) * 1000 / now;
          speed = speed <= 0 ? inst : speed * 0.6 + inst * 0.4;
          lastBytes = received;
          sw..reset()..start();
        }
        onProgress?.call(OtaProgress(
          receivedBytes: received,
          totalBytes: total > 0 ? total : received,
          speedBytesPerSec: speed,
        ));
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (received == 0) throw OtaException('下载内容为空');
  }

  Future<String> _sha256OfFile(String path) async {
    final File f = File(path);
    final List<int> bytes = await f.readAsBytes();
    return sha256.convert(bytes).toString();
  }
}

/// OTA 异常（消息可直接展示给用户）。
class OtaException implements Exception {
  const OtaException(this.message);
  final String message;

  @override
  String toString() => message;
}
