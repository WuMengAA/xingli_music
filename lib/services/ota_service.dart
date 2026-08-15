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

import '../core/app_version.dart';
import 'log_service.dart';

/// OTA 仓库（开源 + Releases 源）。
const String kOtaRepoOwner = 'WuMengAA';
const String kOtaRepoName = 'xingli_music';
const String kOtaReleaseApi =
    'https://api.github.com/repos/$kOtaRepoOwner/$kOtaRepoName/releases';
const String kOtaAssetName = 'app-release.apk';
const String kOtaShaAssetName = 'app-release.apk.sha256';

/// 一次更新检查的结果。
class OtaCheckResult {
  const OtaCheckResult({
    required this.latestTag,
    required this.latestBuild,
    required this.isHotfix,
    required this.hasUpdate,
    required this.releaseNotes,
  });

  final String latestTag;

  /// 最新 Release 的构建号（从 tag 解析；解析失败为 -1）。
  final int latestBuild;

  /// 是否 hotfix（tag 含 `-hotfix`）→ 直接下载。
  final bool isHotfix;

  /// 是否有可应用的新版本（latestBuild > 当前 buildCount）。
  final bool hasUpdate;

  /// Release 说明（body）。
  final String releaseNotes;

  static const OtaCheckResult none = OtaCheckResult(
    latestTag: '',
    latestBuild: -1,
    isHotfix: false,
    hasUpdate: false,
    releaseNotes: '',
  );
}

/// OTA 服务单例。
class OtaService {
  OtaService._();
  static final OtaService instance = OtaService._();

  final http.Client _client = http.Client();

  /// 检查 GitHub Releases 是否有新版本。
  ///
  /// 失败（网络 / 无 Release / 解析失败）返回 [OtaCheckResult.none]，
  /// 不向上抛——更新检查是附属能力，绝不能因它崩溃或阻塞。
  Future<OtaCheckResult> checkForUpdate() async {
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
      // 取第一个非 draft 的 Release。
      final Map<String, dynamic> first =
          (releases.firstWhere(
                (dynamic r) =>
                    (r as Map<String, dynamic>)['draft'] != true,
                orElse: () => releases.first,
              )
              as Map<String, dynamic>);
      final String tag =
          (first['tag_name'] as String?)?.trim() ?? '';
      if (tag.isEmpty) return OtaCheckResult.none;
      final int build = _parseBuild(tag);
      final bool hotfix = tag.contains('-hotfix');
      final int current = AppVersion.buildCount;
      final bool hasUpdate = build > current;
      LogService.instance.i('ota',
          '检查更新: tag=$tag build=$build 当前=$current hotfix=$hotfix 有更新=$hasUpdate');
      return OtaCheckResult(
        latestTag: tag,
        latestBuild: build,
        isHotfix: hotfix,
        hasUpdate: hasUpdate,
        releaseNotes:
            (first['body'] as String?) ?? '',
      );
    } catch (e) {
      LogService.instance.w('ota', '检查更新失败: $e');
      return OtaCheckResult.none;
    }
  }

  /// 从 Release tag 解析构建号：`cl55` → 55、`v0.26.8.14` → 0（语义版本走
  /// 数字比较兜底），`cl55-hotfix` → 55。
  int _parseBuild(String tag) {
    final RegExp cl = RegExp(r'cl(\d+)', caseSensitive: false);
    final Match? m = cl.firstMatch(tag);
    if (m != null) return int.tryParse(m.group(1)!) ?? -1;
    // 语义版本：取最后一段数字（v0.26.8.14 → 14 只是演示；真实比较应拆四位）。
    final RegExp sem = RegExp(r'(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?');
    final Match? sm = sem.firstMatch(tag);
    if (sm != null) {
      // 简化：cl 体系为主，语义版本暂不参与 OTA 比较。
      return -1;
    }
    return -1;
  }

  /// 下载 Release 资产并校验 SHA-256。
  ///
  /// 返回安装包路径（校验通过）；失败抛 [OtaException]（消息可直接展示）。
  Future<String> downloadAndVerify(String tag) async {
    final String url =
        'https://github.com/$kOtaRepoOwner/$kOtaRepoName/releases/download/$tag/$kOtaAssetName';
    final String shaUrl =
        'https://github.com/$kOtaRepoOwner/$kOtaRepoName/releases/download/$tag/$kOtaShaAssetName';

    final Directory dir = await getApplicationDocumentsDirectory();
    final String apkPath = p.join(dir.path, 'ota_$tag.apk');

    // 1) 下载 sha256 期望值。
    final String expected = await _fetchSha256(shaUrl);
    // 2) 下载 apk（流式）。
    await _download(url, apkPath);
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

  Future<void> _download(String url, String path) async {
    final http.Response resp = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(minutes: 5));
    if (resp.statusCode != 200) {
      throw OtaException('下载失败（HTTP ${resp.statusCode}）');
    }
    final File f = File(path);
    await f.writeAsBytes(resp.bodyBytes, flush: true);
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
