import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/capability.dart';
import '../../models/local_dir_config.dart';
import '../../models/server_config.dart';
import '../../services/content/capability_service.dart';
import '../../services/security/http_client_factory.dart';
import '../audio/local_dir_providers.dart';
import '../audio/server_config_provider.dart';
import '../security/cert_policy_provider.dart';
import '../storage/storage_providers.dart';
import 'content_providers.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 能力清单 Provider（cl11）
/// ════════════════════════════════════════════════════════════════════════
///
/// 数据流：
///   服务端 /api/capabilities ─┬─→ 成功 → 写缓存 ─┐
///                             └─→ 失败 → 读缓存 ─┴→ 合并本地固有能力
///                                                      ↓
///                                              应用用户选配开关
///                                                      ↓
///                                            [capabilitiesProvider]
///
/// 任何一环失败都不抛异常：能力层故障绝不影响播放主流程。
/// ════════════════════════════════════════════════════════════════════════

/// 能力清单的本地缓存键。
const String kCapabilitiesCacheKey = 'capabilities_cache';

/// 被用户关闭的能力 id 集合。
const String kCapabilityDisabledKey = 'capability_disabled';

/// 备用内容服务地址（prefs 键 `content_backup_urls`）。
///
/// 主+备是 Piped 那套「多实例兜底」思路的最小实现：官方实例挂掉时，
/// 自托管备用地址仍能顶上，避免出现 Listen1 式「后端一挂全站瘫痪」。
class ContentBackupUrlsPrefs extends StateNotifier<List<String>> {
  ContentBackupUrlsPrefs(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static List<String> _load(SharedPreferences p) =>
      p.getStringList('content_backup_urls') ?? const <String>[];

  void set(List<String> v) {
    final List<String> next = v
        .map((String s) => s.trim().replaceAll(RegExp(r'/+$'), ''))
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    state = next;
    unawaited(_prefs.setStringList('content_backup_urls', next));
  }
}

final StateNotifierProvider<ContentBackupUrlsPrefs, List<String>>
    contentBackupUrlsProvider =
    StateNotifierProvider<ContentBackupUrlsPrefs, List<String>>(
  (Ref ref) => ContentBackupUrlsPrefs(ref.read(prefsProvider)),
);

/// 主地址在前、备用在后的完整地址列表（去重）。
final Provider<List<String>> contentBaseUrlsProvider = Provider<List<String>>(
  (Ref ref) {
    final String main = ref.watch(contentBaseUrlProvider);
    final List<String> backups = ref.watch(contentBackupUrlsProvider);
    return <String>[main, ...backups.where((String b) => b != main)];
  },
);

/// 本地缓存的清单（服务端不可达时降级用）。
final Provider<CapabilityManifest?> cachedCapabilitiesProvider =
    Provider<CapabilityManifest?>(
  (Ref ref) => decodeCapabilities(
    ref.watch(prefsProvider).getString(kCapabilitiesCacheKey),
  ),
);

/// 能力清单：主备逐个尝试 → 成功写缓存 → 全失败回退缓存 → 再没有则空清单。
final AutoDisposeFutureProvider<CapabilityManifest> capabilityManifestProvider =
    FutureProvider.autoDispose<CapabilityManifest>((Ref ref) async {
  final CapabilityManifest? fresh = await fetchCapabilities(
    ref.watch(contentBaseUrlsProvider),
    client: makeHttpClient(
      lenient: ref.watch(certPolicyProvider) == CertPolicy.lenient,
    ),
  );
  if (fresh != null) {
    unawaited(ref.read(prefsProvider).setString(
          kCapabilitiesCacheKey,
          encodeCapabilities(fresh),
        ));
    return fresh;
  }
  return ref.read(cachedCapabilitiesProvider) ??
      const CapabilityManifest(capabilities: <Capability>[]);
});

/// 能力选配：只记录「被用户关掉」的 id，未记录的即启用。
///
/// 这样服务端后续新增能力会自动出现在客户端（默认启用），用户再自行裁剪
/// ——符合「服务端全量支持、客户端自行选配」的定位。
class CapabilitySelectionPrefs extends StateNotifier<Set<String>> {
  CapabilitySelectionPrefs(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static Set<String> _load(SharedPreferences p) =>
      (p.getStringList(kCapabilityDisabledKey) ?? const <String>[]).toSet();

  bool isOn(String id) => !state.contains(id);

  void setOn(String id, bool on) {
    final Set<String> next = Set<String>.from(state);
    if (on) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = next;
    unawaited(_prefs.setStringList(
      kCapabilityDisabledKey,
      next.toList(growable: false),
    ));
  }
}

final StateNotifierProvider<CapabilitySelectionPrefs, Set<String>>
    capabilitySelectionProvider =
    StateNotifierProvider<CapabilitySelectionPrefs, Set<String>>(
  (Ref ref) => CapabilitySelectionPrefs(ref.read(prefsProvider)),
);

/// 本地固有能力：`enabled` 按实际配置判定（配过目录 / 服务器才算可用）。
///
/// 这些能力不经服务端——文件在用户设备上，服务端读不到，也不该读到。
final Provider<List<Capability>> localCapabilitiesProvider =
    Provider<List<Capability>>((Ref ref) {
  final List<ServerConfig> servers = ref.watch(serverConfigsProvider);
  final List<LocalDirConfig> dirs = ref.watch(localDirConfigsProvider);

  bool anyServer(SourceType t) =>
      servers.any((ServerConfig c) => c.enabled && c.type == t);
  final bool hasDir = dirs.any((LocalDirConfig d) => d.enabled);

  return kLocalCapabilitySpecs.map((LocalCapabilitySpec s) {
    final bool enabled = switch (s.id) {
      'local.library' => true,
      'local.dir' => hasDir,
      'local.subsonic' => anyServer(SourceType.subsonic),
      'local.radio' => anyServer(SourceType.radio),
      _ => false,
    };
    return s.toCapability(enabled: enabled);
  }).toList(growable: false);
});

/// 最终能力列表 = 本地固有 + 服务端下发，并应用用户的选配开关。
///
/// UI 据此渲染入口，不再按音源类型写 if-else。
final Provider<List<Capability>> capabilitiesProvider =
    Provider<List<Capability>>((Ref ref) {
  final Set<String> off = ref.watch(capabilitySelectionProvider);
  final List<Capability> local = ref.watch(localCapabilitiesProvider);
  final AsyncValue<CapabilityManifest> remote =
      ref.watch(capabilityManifestProvider);
  final List<Capability> remoteCaps =
      remote.valueOrNull?.capabilities ?? const <Capability>[];

  return <Capability>[...local, ...remoteCaps]
      .map((Capability c) =>
          c.copyWith(enabled: c.enabled && !off.contains(c.id)))
      .toList(growable: false);
});

/// 清单是否来自本地缓存（UI 可提示「离线缓存」）。
final Provider<bool> capabilitiesFromCacheProvider = Provider<bool>((Ref ref) =>
    ref.watch(capabilityManifestProvider).valueOrNull?.fromCache ?? false);
