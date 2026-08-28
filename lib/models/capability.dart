import 'package:flutter/foundation.dart' show immutable;

/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 能力清单模型（cl11）
/// ════════════════════════════════════════════════════════════════════════
///
/// 架构约定：**服务端是能力中心，客户端只按清单选配**。
/// 客户端不内置任何音源逻辑，也不认识「网易云 / B站」这些具体平台——它只
/// 知道服务端声明了哪些 [Capability]，并按此渲染入口。新增一个音源 =
/// 服务端登记 + 实现路由，**客户端零发版**。
///
/// 与 `tools/relay_server/relay_server.dart` 的 `_cap()` 字段一一对应；
/// 未知取值一律落到 `unknown` 而非抛错，保证服务端升级字段时老客户端不崩。
/// ════════════════════════════════════════════════════════════════════════

/// 能力种类（与服务端 `_cap()` 的 kind 取值对齐）。
enum CapabilityKind {
  /// 搜索（按关键词找歌）。
  search,

  /// 用户歌单。
  playlist,

  /// 每日推荐。
  recommend,

  /// 服务端策展内容（场景包 / 精选歌单 / 公告等）。
  curated,

  /// 电台 / 自建流媒体（Subsonic、公开电台）。
  radio,

  /// 本地文件曲库（不经服务端）。
  local,

  /// 未知类型（服务端新增了客户端尚未适配的 kind）。
  unknown;

  static CapabilityKind parse(String? v) => switch (v) {
        'search' => CapabilityKind.search,
        'playlist' => CapabilityKind.playlist,
        'recommend' => CapabilityKind.recommend,
        'curated' => CapabilityKind.curated,
        'radio' => CapabilityKind.radio,
        'local' => CapabilityKind.local,
        _ => CapabilityKind.unknown,
      };

  String get jsonValue => switch (this) {
        CapabilityKind.search => 'search',
        CapabilityKind.playlist => 'playlist',
        CapabilityKind.recommend => 'recommend',
        CapabilityKind.curated => 'curated',
        CapabilityKind.radio => 'radio',
        CapabilityKind.local => 'local',
        CapabilityKind.unknown => 'unknown',
      };
}

/// 凭据归属——本项目的安全边界所在。
enum CredentialOwner {
  /// 凭据留在客户端加密存储，随请求带上；服务端只做**无状态**协议适配，
  /// 用完即弃、不落盘、不记日志。
  ///
  /// 这是默认项：服务端因此不持有任何用户账号资产，被投诉时无物可交。
  client,

  /// 服务端代持凭据（仅自托管场景可选，风险由部署者自负）。
  server,

  /// 公开能力，无需凭据。
  none,

  /// 未知。
  unknown;

  static CredentialOwner parse(String? v) => switch (v) {
        'client' => CredentialOwner.client,
        'server' => CredentialOwner.server,
        'none' => CredentialOwner.none,
        _ => CredentialOwner.unknown,
      };

  String get jsonValue => switch (this) {
        CredentialOwner.client => 'client',
        CredentialOwner.server => 'server',
        CredentialOwner.none => 'none',
        CredentialOwner.unknown => 'unknown',
      };
}

/// 单条能力声明。
@immutable
class Capability {
  const Capability({
    required this.id,
    required this.source,
    required this.kind,
    required this.title,
    required this.requiresCredential,
    required this.credentialOwner,
    this.endpoint,
    this.enabled = false,
    this.status = 'ready',
    this.builtin = false,
  });

  /// 全局唯一 id，如 `content.scenes` / `netease.recommend` / `local.library`。
  final String id;

  /// 归属的源，如 `content` / `netease` / `bilibili` / `local`。
  final String source;

  final CapabilityKind kind;

  /// 展示名。
  final String title;

  /// 服务端侧的相对路径（本地能力为 null）。
  final String? endpoint;

  /// 是否需要用户凭据。
  final bool requiresCredential;

  final CredentialOwner credentialOwner;

  /// 服务端是否已实现并对该客户端开放。
  final bool enabled;

  /// `ready`（可用）/ `planned`（服务端已认知但未实现）。
  final String status;

  /// 是否客户端本地固有能力（不经服务端，如本地曲库 / 局域网 Subsonic）。
  final bool builtin;

  /// 服务端已认知但尚未实现——UI 应展示为「未启用」而不是直接隐藏，
  /// 让用户知道这条路存在。
  bool get isPlanned => status == 'planned';

  factory Capability.fromJson(Map<String, dynamic> m) => Capability(
        id: m['id'] as String? ?? '',
        source: m['source'] as String? ?? '',
        kind: CapabilityKind.parse(m['kind'] as String?),
        title: m['title'] as String? ?? '',
        endpoint: m['endpoint'] as String?,
        requiresCredential: m['requiresCredential'] as bool? ?? false,
        credentialOwner: CredentialOwner.parse(m['credentialOwner'] as String?),
        enabled: m['enabled'] as bool? ?? false,
        status: m['status'] as String? ?? 'ready',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'source': source,
        'kind': kind.jsonValue,
        'title': title,
        if (endpoint != null) 'endpoint': endpoint,
        'requiresCredential': requiresCredential,
        'credentialOwner': credentialOwner.jsonValue,
        'enabled': enabled,
        'status': status,
        if (builtin) 'builtin': true,
      };

  Capability copyWith({bool? enabled}) => Capability(
        id: id,
        source: source,
        kind: kind,
        title: title,
        endpoint: endpoint,
        requiresCredential: requiresCredential,
        credentialOwner: credentialOwner,
        enabled: enabled ?? this.enabled,
        status: status,
        builtin: builtin,
      );
}

/// 服务端下发的能力清单。
@immutable
class CapabilityManifest {
  const CapabilityManifest({
    required this.capabilities,
    this.service,
    this.version,
    this.mode,
    this.ts,
    this.fromCache = false,
  });

  final List<Capability> capabilities;

  /// 服务端标识（如 `xingli-relay`）。
  final String? service;

  /// 服务端版本（如 `cl11`）。
  final String? version;

  /// 部署形态（official / selfhosted）。
  final String? mode;

  /// 服务端时间戳。
  final String? ts;

  /// 是否来自本地缓存（服务端不可达时的降级结果）。
  final bool fromCache;

  factory CapabilityManifest.fromJson(
    Map<String, dynamic> m, {
    bool fromCache = false,
  }) {
    final Map<String, dynamic> server =
        m['server'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final List<dynamic> raw =
        m['capabilities'] as List<dynamic>? ?? const <dynamic>[];
    return CapabilityManifest(
      capabilities: raw
          .whereType<Map<String, dynamic>>()
          .map(Capability.fromJson)
          .where((Capability c) => c.id.isNotEmpty)
          .toList(growable: false),
      service: server['service'] as String?,
      version: server['version'] as String?,
      mode: server['mode'] as String?,
      ts: server['ts'] as String?,
      fromCache: fromCache,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'server': <String, dynamic>{
          if (service != null) 'service': service,
          if (version != null) 'version': version,
          if (mode != null) 'mode': mode,
          if (ts != null) 'ts': ts,
        },
        'capabilities': capabilities
            .map((Capability c) => c.toJson())
            .toList(growable: false),
      };

  /// 按 id 取能力，未找到返回 null。
  Capability? byId(String id) {
    for (final Capability c in capabilities) {
      if (c.id == id) return c;
    }
    return null;
  }
}
