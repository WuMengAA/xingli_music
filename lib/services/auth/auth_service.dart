import 'dart:convert';

import 'package:http/http.dart' as http;

/// ════════════════════════════════════════════════════════════════════════
/// 用户系统 · 后端认证服务（cl10）
/// ════════════════════════════════════════════════════════════════════════
///
/// 与 relay_server 的 `/api/auth/*` 联动：注册 / 登录 / 拉取档案。
/// 后端签发 HMAC token（见 relay_server），App 端用 [SecureBox] 持久化。
/// [client] 可选：自托管场景传入宽松客户端（接受自签名证书）。

/// 登录用户档案（剔除盐/校验值，仅前端可用字段）。
class AuthUser {
  const AuthUser({
    required this.username,
    this.prefs = const <String, dynamic>{},
    this.favorites = const <dynamic>[],
    this.createdAt,
  });

  final String username;
  final Map<String, dynamic> prefs;
  final List<dynamic> favorites;
  final String? createdAt;

  factory AuthUser.fromJson(Map<String, dynamic> m) => AuthUser(
        username: (m['username'] as String?) ?? '',
        prefs: (m['prefs'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
        favorites: (m['favorites'] as List<dynamic>?) ?? const <dynamic>[],
        createdAt: m['createdAt'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'username': username,
        'prefs': prefs,
        'favorites': favorites,
        'createdAt': createdAt,
      };
}

/// 认证结果。
class AuthResult {
  const AuthResult({this.ok = false, this.token, this.user, this.error});

  final bool ok;
  final String? token;
  final AuthUser? user;
  final String? error;
}

/// 注册。成功返回 token + 档案。
Future<AuthResult> registerUser(
  String baseUrl,
  String username,
  String password, {
  http.Client? client,
}) =>
    _postAuth(client, '${baseUrl.trimRight()}/api/auth/register',
        <String, dynamic>{'username': username, 'password': password});

/// 登录。成功返回 token + 档案。
Future<AuthResult> loginUser(
  String baseUrl,
  String username,
  String password, {
  http.Client? client,
}) =>
    _postAuth(client, '${baseUrl.trimRight()}/api/auth/login',
        <String, dynamic>{'username': username, 'password': password});

/// 凭 token 拉取最新档案（用于启动恢复/刷新）。
Future<AuthResult> fetchMe(
  String baseUrl,
  String token, {
  http.Client? client,
}) async {
  final http.Client c = client ?? http.Client();
  try {
    final http.Response resp = await c
        .get(
          Uri.parse('${baseUrl.trimRight()}/api/auth/me'),
          headers: <String, String>{'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) return const AuthResult(error: '登录已失效');
    final Object? v = jsonDecode(utf8.decode(resp.bodyBytes));
    if (v is! Map<String, dynamic> || v['ok'] != true) {
      return const AuthResult(error: '登录已失效');
    }
    return AuthResult(
      ok: true,
      token: token,
      user: AuthUser.fromJson(v['user'] as Map<String, dynamic>),
    );
  } catch (_) {
    return const AuthResult(error: '网络错误');
  } finally {
    if (client == null) c.close();
  }
}

// ═══ cl14：档案更新（偏好 / 收藏跨设备同步）════════════════════════

/// 整体更新偏好：`PUT /api/auth/prefs`，body `{prefs: {...}}`。
///
/// 返回新档案；失败返回 `ok:false`（含 error）。token 无效返回「登录已失效」。
Future<AuthResult> updateUserPrefs(
  String baseUrl,
  String token,
  Map<String, dynamic> prefs, {
  http.Client? client,
}) =>
    _putAuth(baseUrl, token, '/api/auth/prefs',
        <String, dynamic>{'prefs': prefs}, client: client);

/// 整体更新收藏：`PUT /api/auth/favorites`，body `{favorites: [...]}`。
Future<AuthResult> updateUserFavorites(
  String baseUrl,
  String token,
  List<dynamic> favorites, {
  http.Client? client,
}) =>
    _putAuth(baseUrl, token, '/api/auth/favorites',
        <String, dynamic>{'favorites': favorites}, client: client);

/// 部分更新档案：`PATCH /api/auth/profile`，body 可含 `prefs` 和/或 `favorites`。
Future<AuthResult> updateUserProfile(
  String baseUrl,
  String token, {
  Map<String, dynamic>? prefs,
  List<dynamic>? favorites,
  http.Client? client,
}) {
  final Map<String, dynamic> body = <String, dynamic>{};
  if (prefs != null) body['prefs'] = prefs;
  if (favorites != null) body['favorites'] = favorites;
  return _putAuth(baseUrl, token, '/api/auth/profile', body, client: client);
}

/// 内部：PUT 档案并解析统一响应。
Future<AuthResult> _putAuth(
  String baseUrl,
  String token,
  String path,
  Map<String, dynamic> body, {
  http.Client? client,
}) async {
  final http.Client c = client ?? http.Client();
  try {
    final http.Response resp = await c
        .put(
          Uri.parse('${baseUrl.trimRight()}$path'),
          headers: <String, String>{
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 5));
    final Object? v = jsonDecode(utf8.decode(resp.bodyBytes));
    if (v is! Map<String, dynamic>) return const AuthResult(error: '响应异常');
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      return const AuthResult(error: '登录已失效');
    }
    if (v['ok'] == true) {
      return AuthResult(
        ok: true,
        user: v['user'] is Map<String, dynamic>
            ? AuthUser.fromJson(v['user'] as Map<String, dynamic>)
            : null,
      );
    }
    return AuthResult(error: (v['error'] as String?) ?? '请求失败');
  } catch (_) {
    return const AuthResult(error: '网络错误');
  } finally {
    if (client == null) c.close();
  }
}

/// 内部：POST 注册/登录并解析统一响应。
Future<AuthResult> _postAuth(
  http.Client? client,
  String url,
  Map<String, dynamic> body,
) async {
  final http.Client c = client ?? http.Client();
  try {
    final http.Response resp = await c
        .post(
          Uri.parse(url),
          headers: <String, String>{'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 5));
    final Object? v = jsonDecode(utf8.decode(resp.bodyBytes));
    if (v is! Map<String, dynamic>) return const AuthResult(error: '响应异常');
    if (v['ok'] == true) {
      return AuthResult(
        ok: true,
        token: v['token'] as String?,
        user: AuthUser.fromJson(v['user'] as Map<String, dynamic>),
      );
    }
    return AuthResult(error: (v['error'] as String?) ?? '请求失败');
  } catch (_) {
    return const AuthResult(error: '网络错误');
  } finally {
    if (client == null) c.close();
  }
}
