/// 星璃 · 哔哩哔哩（B站）音源 Riverpod 接线
///
/// 暴露：登录态（二维码 / cookie / 登出 / 恢复）+ 搜索 + 自动匹配。
/// 与网易云源同构（`netease_provider.dart`），cookie 一律经 `SecureBox`
/// 加密落盘，绝不进明文 SharedPreferences。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../services/audio/sources/bilibili/bilibili_api.dart';
import '../../services/audio/sources/bilibili/bilibili_source.dart';
import '../../services/security/secure_store.dart';

/// 加密保险箱（复用既有实现）。
final Provider<SecureBox> bilibiliSecureBoxProvider =
    Provider<SecureBox>((Ref ref) => SecureBox());

/// B站 HTTP 客户端。
final Provider<BilibiliApi> bilibiliApiProvider = Provider<BilibiliApi>((Ref ref) {
  final BilibiliApi api = BilibiliApi();
  ref.onDispose(api.close);
  return api;
});

/// B站音源实例。`enabled` 随登录态变化（未登录不参与聚合/解析）。
final Provider<BilibiliSource> bilibiliSourceProvider =
    Provider<BilibiliSource>((Ref ref) {
  final BilibiliApi api = ref.watch(bilibiliApiProvider);
  ref.watch(bilibiliAuthProvider); // 登录态变化时重建，刷新 enabled
  return BilibiliSource(api);
});

/// 登录态。
class BilibiliAuthState {
  const BilibiliAuthState({
    this.restoring = true,
    this.busy = false,
    this.nickname,
    this.vip = false,
    this.qrKey,
    this.qrUrl,
    this.error,
    this.qrMessage,
  });

  /// 冷启动读取密文 cookie 中。
  final bool restoring;

  /// 正在登录 / 登出 / 轮询。
  final bool busy;

  /// 登录后昵称（未登录为 null）。
  final String? nickname;

  /// 大会员状态（R26skel-b6：自动识别，>0 解锁更高清晰度）。
  final bool vip;

  /// 二维码登录会话（仅在扫码流程中非空）。
  final String? qrKey;
  final String? qrUrl;

  /// 可直接展示的失败原因。
  final String? error;

  /// 扫码流程的进行中提示。
  final String? qrMessage;

  bool get isLoggedIn => nickname != null;

  BilibiliAuthState copyWith({
    bool? restoring,
    bool? busy,
    String? nickname,
    bool? vip,
    String? qrKey,
    String? qrUrl,
    String? error,
    String? qrMessage,
    bool clearQr = false,
    bool clearError = false,
  }) =>
      BilibiliAuthState(
        restoring: restoring ?? this.restoring,
        busy: busy ?? this.busy,
        nickname: nickname ?? this.nickname,
        vip: vip ?? this.vip,
        qrKey: clearQr ? null : (qrKey ?? this.qrKey),
        qrUrl: clearQr ? null : (qrUrl ?? this.qrUrl),
        error: clearError ? null : (error ?? this.error),
        qrMessage: qrMessage,
      );
}

/// 登录编排：恢复 / cookie 登录 / 扫码登录 / 登出。
final StateNotifierProvider<BilibiliAuthNotifier, BilibiliAuthState>
    bilibiliAuthProvider =
    StateNotifierProvider<BilibiliAuthNotifier, BilibiliAuthState>(
  (Ref ref) => BilibiliAuthNotifier(
    ref.watch(bilibiliApiProvider),
    ref.watch(bilibiliSecureBoxProvider),
  ),
);

class BilibiliAuthNotifier extends StateNotifier<BilibiliAuthState> {
  BilibiliAuthNotifier(this._api, this._box)
      : super(const BilibiliAuthState()) {
    restore();
  }

  final BilibiliApi _api;
  final SecureBox _box;

  /// 冷启动恢复：读密文 cookie 并校验。
  Future<void> restore() async {
    final String? raw = await _box.readSecret(SecureBox.kBilibiliCookie);
    if (raw == null || raw.isEmpty) {
      state = state.copyWith(restoring: false);
      return;
    }
    try {
      await _api.loginWithCookie(raw);
      final info = await _api.account();
      state = state.copyWith(
          restoring: false, nickname: info?.uname, vip: info?.vip ?? false, clearError: true);
    } catch (_) {
      await _box.deleteSecret(SecureBox.kBilibiliCookie);
      _api.clearCookie();
      state = state.copyWith(
        restoring: false,
        error: 'B站登录已失效，请重新登录',
      );
    }
  }

  /// 用现成 cookie 登录（用户粘贴 SESSDATA 等）。
  Future<bool> loginWithCookie(String rawCookie) async {
    if (rawCookie.trim().isEmpty) {
      state = state.copyWith(error: 'cookie 不能为空');
      return false;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _api.loginWithCookie(rawCookie.trim());
      final info = await _api.account();
      await _box.writeSecret(SecureBox.kBilibiliCookie, _api.cookie);
      state = state.copyWith(
          busy: false, nickname: info?.uname, vip: info?.vip ?? false, clearQr: true, clearError: true);
      return true;
    } on BilibiliApiException catch (e) {
      state = state.copyWith(busy: false, error: _readable(e));
      return false;
    } catch (_) {
      state = state.copyWith(busy: false, error: 'B站登录失败，请检查网络后重试');
      return false;
    }
  }

  /// 申请二维码。
  Future<bool> startQrLogin() async {
    state = state.copyWith(busy: true, clearQr: true, clearError: true);
    try {
      final String key = await _api.createQrKey();
      state = state.copyWith(busy: false, qrKey: key, qrUrl: _api.qrLoginUrl(key));
      return true;
    } catch (_) {
      state = state.copyWith(busy: false, error: '二维码获取失败，请稍后重试');
      return false;
    }
  }

  /// 轮询一次扫码状态；返回是否已登录成功。UI 侧按 2 秒间隔调用。
  Future<BiliQrStatus?> pollQrLogin() async {
    final String? key = state.qrKey;
    if (key == null) return null;
    try {
      final BiliQrStatus st = await _api.checkQrLogin(key);
      if (st == BiliQrStatus.authorized) {
        await _box.writeSecret(SecureBox.kBilibiliCookie, _api.cookie);
        state = state.copyWith(clearQr: true, clearError: true);
        unawaited(_refreshAccountAfterQr());
      } else if (st == BiliQrStatus.expired) {
        state = state.copyWith(clearQr: true, error: '二维码已过期，请重新获取');
      } else if (st == BiliQrStatus.waitingConfirm) {
        state = state.copyWith(
            qrMessage: '已在手机确认登录，正在完成…', clearError: true);
      }
      return st;
    } catch (_) {
      state = state.copyWith(error: '扫码状态查询失败');
      return null;
    }
  }

  Future<void> _refreshAccountAfterQr() async {
    try {
      final info = await _api.account();
      state = state.copyWith(nickname: info?.uname, vip: info?.vip ?? false);
    } catch (_) {
      // 账号接口暂不可用：保留登录态。
    }
  }

  /// 登出。
  Future<void> logout() async {
    state = state.copyWith(busy: true);
    await _box.deleteSecret(SecureBox.kBilibiliCookie);
    _api.clearCookie();
    state = const BilibiliAuthState(restoring: false);
  }

  static String _readable(BilibiliApiException e) =>
      e.isAuthFailure ? 'B站登录态无效，请重新登录' : 'B站接口调用失败（${e.code}）';
}

/// B站搜索结果（未登录返回空）。
final AutoDisposeFutureProviderFamily<List<Track>, String>
    bilibiliSearchProvider = FutureProvider.autoDispose
        .family<List<Track>, String>((Ref ref, String keyword) async {
  final BilibiliAuthState auth = ref.watch(bilibiliAuthProvider);
  if (keyword.trim().isEmpty) return const <Track>[];
  return ref.watch(bilibiliSourceProvider).search(keyword.trim());
});

/// 把搜索/接口异常转成用户可读文案。
String bilibiliErrorText(Object e) {
  if (e is BilibiliApiException) {
    if (e.isAuthFailure) return 'B站登录态已失效，请重新登录';
    return 'B站接口异常（${e.code}）';
  }
  if (e is TimeoutException) return '网络超时，请检查连接后重试';
  final String msg = e.toString();
  if (msg.contains('SocketException') || msg.toLowerCase().contains('network')) {
    return '网络异常，请检查网络连接';
  }
  return 'B站请求失败，请稍后重试';
}

/// cl46 视听结合：当前歌曲自动搜B站视频作场景卡片背景画面（默认开）。
final biliVisualEnabledProvider = StateProvider<bool>((Ref ref) => true);

/// 视听结合：背景视频模糊（默认关）。
final biliVisualBlurProvider = StateProvider<bool>((Ref ref) => false);

/// 视听结合：视频跟随音乐进度同步（默认开）。
final biliVisualSyncProvider = StateProvider<bool>((Ref ref) => true);

/// 视听结合：变速适配——时长相差过大时实时同步进度（默认关）。
final biliVisualTempoAdaptProvider = StateProvider<bool>((Ref ref) => false);
