import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;

import '../../models/capability.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 能力清单拉取（cl11）
/// ════════════════════════════════════════════════════════════════════════
///
/// 借鉴 Piped 的「多实例」思路：官方服务与备用地址一起传入，**逐个尝试、
/// 首个成功即返回**。任一实例挂掉不影响整体，这是 Listen1 那种「单个后端
/// 挂了全站瘫痪」的反面。
///
/// 全部失败返回 `null`，由上层回退本地缓存——**绝不向上抛异常**，能力层
/// 的任何故障都不能影响播放主流程。
/// ════════════════════════════════════════════════════════════════════════

/// 默认单地址超时。
const Duration kCapabilitiesTimeout = Duration(seconds: 5);

/// 按主备顺序拉取能力清单，首个成功即返回；全部失败返回 null。
///
/// [baseUrls] 主地址在前、备用在后。
/// [client] 可选：自托管场景传入宽松客户端（接受自签名证书）。
Future<CapabilityManifest?> fetchCapabilities(
  List<String> baseUrls, {
  http.Client? client,
  Duration timeout = kCapabilitiesTimeout,
}) async {
  final http.Client c = client ?? http.Client();
  try {
    for (final String base in baseUrls) {
      final String b = base.trim().replaceAll(RegExp(r'/+$'), '');
      if (b.isEmpty) continue;
      try {
        final http.Response resp = await c
            .get(Uri.parse('$b/api/capabilities'))
            .timeout(timeout);
        if (resp.statusCode != 200) continue;
        final Object? v = jsonDecode(utf8.decode(resp.bodyBytes));
        if (v is! Map<String, dynamic>) continue;
        return CapabilityManifest.fromJson(v);
      } catch (_) {
        continue; // 换下一个备用地址
      }
    }
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// 清单落盘前的序列化（本地缓存用）。
String encodeCapabilities(CapabilityManifest m) => jsonEncode(m.toJson());

/// 读取本地缓存的清单；无缓存或格式损坏返回 null。
///
/// [fromCache] 置 true，便于 UI 提示「当前为离线缓存」。
CapabilityManifest? decodeCapabilities(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    final Object? v = jsonDecode(s);
    if (v is! Map<String, dynamic>) return null;
    return CapabilityManifest.fromJson(v, fromCache: true);
  } catch (_) {
    return null;
  }
}

/// 本地固有能力（不经服务端，文件在用户设备上）。
///
/// `enabled` 由实际配置决定（如是否配过目录 / 服务器），故此处统一置
/// `enabled: false`，由 `capability_providers.dart` 按配置覆盖。
@immutable
class LocalCapabilitySpec {
  const LocalCapabilitySpec({
    required this.id,
    required this.kind,
    required this.title,
  });

  final String id;
  final CapabilityKind kind;
  final String title;

  Capability toCapability({required bool enabled}) => Capability(
        id: id,
        source: 'local',
        kind: kind,
        title: title,
        requiresCredential: false,
        credentialOwner: CredentialOwner.none,
        enabled: enabled,
        status: enabled ? 'ready' : 'planned',
        builtin: true,
      );
}

/// 客户端本地固有能力清单。
const List<LocalCapabilitySpec> kLocalCapabilitySpecs = <LocalCapabilitySpec>[
  LocalCapabilitySpec(
    id: 'local.library',
    kind: CapabilityKind.local,
    title: '本地曲库',
  ),
  LocalCapabilitySpec(
    id: 'local.dir',
    kind: CapabilityKind.local,
    title: '本地目录',
  ),
  LocalCapabilitySpec(
    id: 'local.subsonic',
    kind: CapabilityKind.radio,
    title: '自建 Subsonic',
  ),
  LocalCapabilitySpec(
    id: 'local.radio',
    kind: CapabilityKind.radio,
    title: '公开电台',
  ),
];
