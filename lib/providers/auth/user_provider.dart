import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/auth_service.dart';
import '../../services/security/secure_store.dart';

/// 登录态。
enum AuthStatus { guest, authed }

/// 全局登录状态。
class AuthState {
  const AuthState({this.status = AuthStatus.guest, this.user, this.token});

  final AuthStatus status;
  final AuthUser? user;
  final String? token;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? token,
    bool clear = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        token: clear ? null : (token ?? this.token),
      );

  bool get isAuthed => status == AuthStatus.authed && token != null;
}

/// 登录态 Notifier：持有当前用户，token/档案经 [SecureBox] 持久化（静态混淆级）。
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _restore();
  }

  final SecureBox _box = SecureBox();

  static const String _kToken = 'auth.token';
  static const String _kUser = 'auth.user';

  /// 启动恢复：若本地存有有效 token + 档案则直接进入已登录态。
  Future<void> _restore() async {
    try {
      final String? token = await _box.readSecret(_kToken);
      final String? userJson = await _box.readSecret(_kUser);
      if (token != null && userJson != null) {
        final AuthUser u = AuthUser.fromJson(
          jsonDecode(userJson) as Map<String, dynamic>,
        );
        state = state.copyWith(status: AuthStatus.authed, token: token, user: u);
      }
    } catch (_) {
      // 恢复失败静默回落游客
    }
  }

  /// 写入会话（登录/注册成功后）。
  Future<void> setSession(String token, AuthUser user) async {
    state = state.copyWith(status: AuthStatus.authed, token: token, user: user);
    try {
      await _box.writeSecret(_kToken, token);
      await _box.writeSecret(_kUser, jsonEncode(user.toJson()));
    } catch (_) {}
  }

  /// 刷新档案（如服务端偏好变更后）。
  void setUser(AuthUser user) {
    state = state.copyWith(user: user);
    try {
      unawaited(_box.writeSecret(_kUser, jsonEncode(user.toJson())));
    } catch (_) {}
  }

  /// 登出：清内存 + 清本地持久化。
  Future<void> logout() async {
    state = const AuthState();
    try {
      await _box.deleteSecret(_kToken);
      await _box.deleteSecret(_kUser);
    } catch (_) {}
  }
}

final StateNotifierProvider<AuthNotifier, AuthState> authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>(
  (Ref ref) => AuthNotifier(),
);
