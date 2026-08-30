/// ════════════════════════════════════════════════════════════════════════
/// OTA GitHub Pages 分发 · manifest 模型与解析（clOTA）
/// ════════════════════════════════════════════════════════════════════════
///
/// 仓库 `gh-pages` 分支静态托管 `ota/manifest.json` + `ota/<tag>/` 资产：
///
/// ```json
/// {
///   "schema": 1,
///   "source": "github-pages",
///   "updatedAt": "2026-08-31T06:20:00+08:00",
///   "channels": {
///     "beta": {
///       "latest": {
///         "tag": "0.26.8.31_beta_cl01",
///         "dateKey": 20260831,
///         "build": 1,
///         "hotfix": null,
///         "notes": "clOTA：GitHub Pages 分发链路"
///       }
///     }
///   },
///   "assets": {
///     "0.26.8.31_beta_cl01": {
///       "android": {
///         "arm64-v8a":   { "name": "app-arm64-v8a-release.apk",   "size": 44890000, "sha256": "…" },
///         "armeabi-v7a": { "name": "app-armeabi-v7a-release.apk", "size": 42200000, "sha256": "…" }
///       },
///       "windows": {
///         "x64": { "name": "xingli_music_windows_x64.zip", "size": 81200000, "sha256": "…" }
///       }
///     }
///   },
///   "versions": ["0.26.8.31_beta_cl01"]
/// }
/// ```
///
/// - 资产 URL = Pages 根 + `/ota/<tag>/<name>`（GitHub Pages 静态域名，无 API 限额）。
/// - [parsePagesManifest] 为**纯函数**（不做网络），单测直接喂 JSON。
/// - 本文件刻意零外部依赖（渠道/ABI 用字符串），避免与 ota_service 循环导入。
library;

import 'dart:convert';

/// 单个平台（安卓 / Windows）的资产条目。
class PagesAssetItem {
  const PagesAssetItem({
    required this.name,
    required this.size,
    required this.sha256,
  });

  /// 资产文件名（与 ota_service 的固定命名一致，如 `app-arm64-v8a-release.apk`）。
  final String name;
  final int size;

  /// 资产 SHA-256（小写 hex）；空串表示缺失（上层回退 Releases 源）。
  final String sha256;
}

/// 一个版本 tag 下的平台资产。
class PagesTagAssets {
  PagesTagAssets({Map<String, PagesAssetItem>? android, this.windows})
      : android = android ?? <String, PagesAssetItem>{};

  /// 安卓 ABI 键（'arm64-v8a' / 'armeabi-v7a'）→ 资产。
  final Map<String, PagesAssetItem> android;

  /// Windows 架构键（'x64'）→ 资产；无 Windows 包为 null。
  /// （解析期填充，故非 final。）
  Map<String, PagesAssetItem>? windows;

  /// 是否有任一资产（区别于「空对象」）。
  bool get isEmpty => android.isEmpty && (windows?.isEmpty ?? true);
}

/// 渠道最新版本（manifest 的 `channels.<ch>.latest`）。
class PagesChannelLatest {
  const PagesChannelLatest({
    required this.tag,
    required this.channelTag,
    required this.dateKey,
    required this.build,
    this.hotfix,
    this.notes = '',
  });

  /// 完整版本 tag（如 `0.26.8.31_beta_cl01`）。
  final String tag;

  /// 渠道段（'beta' / 'alpha'）。
  final String channelTag;

  /// 日期键 YYYYMMDD（数字）。
  final int dateKey;

  /// 当日构建次数（cl）。
  final int build;

  /// hotfix 序号；非热修补丁为 null。
  final int? hotfix;

  /// 更新日志（该版本 Release notes / 发布说明）。
  final String notes;
}

/// Pages OTA manifest（整个文件）。
class PagesOtaManifest {
  const PagesOtaManifest({
    required this.schema,
    required this.updatedAt,
    required this.channels,
    required this.assetsByTag,
    required this.versions,
  });

  final int schema;
  final String updatedAt;

  /// 渠道键（'beta'/'alpha'）→ 最新版本信息。
  final Map<String, PagesChannelLatest> channels;

  /// 版本 tag → 平台资产。
  final Map<String, PagesTagAssets> assetsByTag;

  /// 历史版本 tag（新→旧）。
  final List<String> versions;

  /// 某 tag 的指定平台资产。
  ///
  /// [abiKey] 为 'arm64-v8a' / 'armeabi-v7a'（安卓）或 'x64'（Windows）。
  PagesAssetItem? assetFor(String tag, String abiKey, {required bool windows}) {
    final PagesTagAssets? t = assetsByTag[tag];
    if (t == null) return null;
    if (windows) return t.windows?[abiKey];
    return t.android[abiKey];
  }
}

/// 解析 manifest 正文（纯函数，不做网络）。
/// 结构非法 / schema 不符返回 null（上层回退 Releases 源）。
PagesOtaManifest? parsePagesManifest(String body) {
  try {
    final dynamic j = jsonDecode(body);
    if (j is! Map<String, dynamic>) return null;
    final int schema = (j['schema'] as num?)?.toInt() ?? 0;
    if (schema != 1) return null;

    final Map<String, dynamic> chMap =
        (j['channels'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final Map<String, PagesChannelLatest> channels =
        <String, PagesChannelLatest>{};
    chMap.forEach((String ch, dynamic v) {
      if (v is! Map<String, dynamic>) return;
      final Map<String, dynamic> latest =
          (v['latest'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final String? tag = latest['tag'] as String?;
      if (tag == null || tag.isEmpty) return;
      channels[ch] = PagesChannelLatest(
        tag: tag,
        channelTag: ch,
        dateKey: (latest['dateKey'] as num?)?.toInt() ?? 0,
        build: (latest['build'] as num?)?.toInt() ?? -1,
        hotfix: (latest['hotfix'] as num?)?.toInt(),
        notes: (latest['notes'] as String?) ?? '',
      );
    });

    final Map<String, dynamic> assetsMap =
        (j['assets'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final Map<String, PagesTagAssets> assetsByTag =
        <String, PagesTagAssets>{};
    assetsMap.forEach((String tag, dynamic v) {
      if (v is! Map<String, dynamic>) return;
      final PagesTagAssets t = PagesTagAssets();
      final Map<String, dynamic>? android =
          v['android'] as Map<String, dynamic>?;
      android?.forEach((String abi, dynamic a) {
        final PagesAssetItem? item = _assetItem(a);
        if (item != null) t.android[abi] = item;
      });
      final Map<String, dynamic>? windows =
          v['windows'] as Map<String, dynamic>?;
      if (windows != null && windows.isNotEmpty) {
        final Map<String, PagesAssetItem> w = <String, PagesAssetItem>{};
        windows.forEach((String arch, dynamic a) {
          final PagesAssetItem? item = _assetItem(a);
          if (item != null) w[arch] = item;
        });
        if (w.isNotEmpty) t.windows = w;
      }
      assetsByTag[tag] = t;
    });

    final List<String> versions = (j['versions'] as List<dynamic>? ?? <dynamic>[])
        .whereType<String>()
        .toList();

    return PagesOtaManifest(
      schema: schema,
      updatedAt: (j['updatedAt'] as String?) ?? '',
      channels: channels,
      assetsByTag: assetsByTag,
      versions: versions,
    );
  } catch (_) {
    return null;
  }
}

PagesAssetItem? _assetItem(dynamic a) {
  if (a is! Map<String, dynamic>) return null;
  final String? name = a['name'] as String?;
  if (name == null || name.isEmpty) return null;
  return PagesAssetItem(
    name: name,
    size: (a['size'] as num?)?.toInt() ?? 0,
    sha256: (a['sha256'] as String?) ?? '',
  );
}