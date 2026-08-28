import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;

/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 后端内容 API（cl08）
/// ════════════════════════════════════════════════════════════════════════
///
/// 与 relay_server 的 REST 内容接口联动，App 与 ClassIsland 桌面组件
/// 共用同一内容源：场景包 / 推荐歌单 / 公告。内容不局限于当前构建，
/// 由后端动态下发；离线模式下跳过（本地能力不受影响）。
/// ════════════════════════════════════════════════════════════════════════

/// 拉取随机内容（场景或歌单，供轮换展示）。失败返回 null。
///
/// [client] 可选：自托管场景传入宽松客户端（接受自签名证书）。
Future<RemoteContent?> fetchRemoteContent(
  String baseUrl, {
  http.Client? client,
}) async {
  final http.Client c = client ?? http.Client();
  try {
    final Uri uri = Uri.parse('${baseUrl.trimRight()}/api/content/random');
    final http.Response resp = await c.get(uri).timeout(
      const Duration(seconds: 5),
    );
    if (resp.statusCode != 200) return null;
    final Object? v = jsonDecode(utf8.decode(resp.bodyBytes));
    return v is Map<String, dynamic> ? RemoteContent.fromJson(v) : null;
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// 拉取公告列表。失败/空返回空列表。
///
/// [client] 可选：自托管场景传入宽松客户端（接受自签名证书）。
Future<List<RemoteNotice>> fetchRemoteNotices(
  String baseUrl, {
  http.Client? client,
}) async {
  final http.Client c = client ?? http.Client();
  try {
    final Uri uri = Uri.parse('${baseUrl.trimRight()}/api/content/notices');
    final http.Response resp = await c.get(uri).timeout(
      const Duration(seconds: 5),
    );
    if (resp.statusCode != 200) return const <RemoteNotice>[];
    final Object? v = jsonDecode(utf8.decode(resp.bodyBytes));
    if (v is! Map<String, dynamic>) return const <RemoteNotice>[];
    final List<dynamic> list = v['notices'] as List<dynamic>? ?? const <dynamic>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(RemoteNotice.fromJson)
        .toList();
  } catch (_) {
    return const <RemoteNotice>[];
  } finally {
    if (client == null) c.close();
  }
}

/// 后端下发的随机内容条目（场景 / 歌单）。
@immutable
class RemoteContent {
  const RemoteContent({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  /// `scene`（场景）或 `playlist`（推荐歌单）。
  final String type;
  final String title;
  final String subtitle;

  /// 主题色（十六进制 `#RRGGBB`）。
  final String accent;

  factory RemoteContent.fromJson(Map<String, dynamic> m) => RemoteContent(
        type: m['type'] as String? ?? 'scene',
        title: m['title'] as String? ?? '',
        subtitle: m['subtitle'] as String? ?? '',
        accent: m['accent'] as String? ?? '#9B7BFF',
      );
}

/// 后端下发的公告。
@immutable
class RemoteNotice {
  const RemoteNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.ts,
  });

  final String id;
  final String title;
  final String body;
  final String ts;

  factory RemoteNotice.fromJson(Map<String, dynamic> m) => RemoteNotice(
        id: m['id'] as String? ?? '',
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        ts: m['ts'] as String? ?? '',
      );
}
