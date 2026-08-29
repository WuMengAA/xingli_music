/// 星璃 · 网易云音源 Riverpod 接线（I 域 · P1-3）
///
/// 只暴露「登录态 + 搜索」两件事，**刻意不接入 `activeSourcesProvider`**
/// 与主播放链路 —— 曲库聚合与 StreamResolver 属于 P0 地基改造范围
/// （docs/方案_音源扩充.md §3.1~§3.3），未完成前接进去会引发回归。
///
/// cookie 一律经既有的 [SecureBox] 加密落盘，绝不进明文 SharedPreferences。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../services/audio/sources/netease/netease_api.dart';
import '../../services/audio/sources/netease/netease_source.dart';
import '../../services/security/secure_store.dart';

/// 加密保险箱（复用 P-3 既有实现，不新建存储）。
final Provider<SecureBox> neteaseSecureBoxProvider =
    Provider<SecureBox>((Ref ref) => SecureBox());

/// weapi 客户端。cookie 由 [NeteaseAuthNotifier] 注入 / 清除。
final Provider<NeteaseApi> neteaseApiProvider = Provider<NeteaseApi>((Ref ref) {
  final NeteaseApi api = NeteaseApi();
  ref.onDispose(api.close);
  return api;
});

/// 网易云音源实例。`enabled` 随登录态变化（未登录时不参与任何聚合）。
final Provider<NeteaseSource> neteaseSourceProvider = Provider<NeteaseSource>((Ref ref) {
  final NeteaseApi api = ref.watch(neteaseApiProvider);
  ref.watch(neteaseAuthProvider); // 登录态变化时重建，刷新 enabled
  return NeteaseSource(api);
});

/// 登录态。
class NeteaseAuthState {
  const NeteaseAuthState({
    this.restoring = true,
    this.busy = false,
    this.account,
    this.qrKey,
    this.qrUrl,
    this.error,
    this.qrMessage,
  });

  /// 冷启动读取密文 cookie 中。
  final bool restoring;

  /// 正在登录 / 登出 / 轮询。
  final bool busy;

  final NeteaseAccount? account;

  /// 二维码登录会话（仅在扫码流程中非空）。
  final String? qrKey;
  final String? qrUrl;

  /// 可直接展示的失败原因。
  final String? error;

  /// 扫码流程的进行中提示（如「已在手机确认登录，正在完成…」）。
  final String? qrMessage;

  bool get isLoggedIn => account != null;

  NeteaseAuthState copyWith({
    bool? restoring,
    bool? busy,
    NeteaseAccount? account,
    String? qrKey,
    String? qrUrl,
    String? error,
    String? qrMessage,
    bool clearAccount = false,
    bool clearQr = false,
    bool clearError = false,
  }) =>
      NeteaseAuthState(
        restoring: restoring ?? this.restoring,
        busy: busy ?? this.busy,
        account: clearAccount ? null : (account ?? this.account),
        qrKey: clearQr ? null : (qrKey ?? this.qrKey),
        qrUrl: clearQr ? null : (qrUrl ?? this.qrUrl),
        error: clearError ? null : (error ?? this.error),
        qrMessage: qrMessage,
      );
}

/// 登录编排：恢复 / cookie 登录 / 扫码登录 / 登出。
final StateNotifierProvider<NeteaseAuthNotifier, NeteaseAuthState> neteaseAuthProvider =
    StateNotifierProvider<NeteaseAuthNotifier, NeteaseAuthState>(
  (Ref ref) => NeteaseAuthNotifier(
    ref.watch(neteaseApiProvider),
    ref.watch(neteaseSecureBoxProvider),
  ),
);

class NeteaseAuthNotifier extends StateNotifier<NeteaseAuthState> {
  NeteaseAuthNotifier(this._api, this._box) : super(const NeteaseAuthState()) {
    restore();
  }

  final NeteaseApi _api;
  final SecureBox _box;

  /// 冷启动恢复：读密文 cookie 并校验有效性。
  ///
  /// 任何失败都当作「未登录」，并擦除已损坏的密文 —— 绝不拿空 cookie
  /// 继续发请求（会被风控记账，见 §4.4(5)）。
  Future<void> restore() async {
    final String? raw = await _box.readSecret(SecureBox.kNeteaseCookie);
    if (raw == null || raw.isEmpty) {
      state = state.copyWith(restoring: false);
      return;
    }
    try {
      final NeteaseAccount acc = await _api.loginWithCookie(raw);
      state = state.copyWith(restoring: false, account: acc, clearError: true);
    } catch (_) {
      await _box.deleteSecret(SecureBox.kNeteaseCookie);
      _api.clearCookie();
      state = state.copyWith(
        restoring: false,
        clearAccount: true,
        error: '网易云登录已失效，请重新登录',
      );
    }
  }

  /// 用现成 cookie 登录（WebView 抓取或用户手工粘贴 MUSIC_U）。
  Future<bool> loginWithCookie(String rawCookie) async {
    if (rawCookie.trim().isEmpty) {
      state = state.copyWith(error: 'cookie 不能为空');
      return false;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      final NeteaseAccount acc = await _api.loginWithCookie(rawCookie.trim());
      await _box.writeSecret(SecureBox.kNeteaseCookie, _api.cookie);
      state = state.copyWith(busy: false, account: acc, clearQr: true, clearError: true);
      return true;
    } on NeteaseApiException catch (e) {
      state = state.copyWith(busy: false, error: _readable(e));
      return false;
    } catch (_) {
      state = state.copyWith(busy: false, error: '网易云登录失败，请检查网络后重试');
      return false;
    }
  }

  /// 申请二维码，成功后 `state.qrUrl` 即为待渲染的二维码内容。
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

  /// 轮询一次扫码状态；返回是否已登录成功。UI 侧按 2 秒间隔调用即可。
  Future<NeteaseQrStatus?> pollQrLogin() async {
    final String? key = state.qrKey;
    if (key == null) return null;
    try {
      final NeteaseQrStatus st = await _api.checkQrLogin(key);
      if (st.authorized) {
        // C1 修复：803 时先把 cookie 落盘 + 清 QR 状态——即便后续 account()
        // 失败（风控/网络抖动）也绝不吞掉「扫码成功」信号，UI 立即进入已登录。
        // account() 改为异步降级：成功则补全昵称头像，失败保留已登录态。
        await _box.writeSecret(SecureBox.kNeteaseCookie, _api.cookie);
        state = state.copyWith(clearQr: true, clearError: true);
        unawaited(_refreshAccountAfterQr());
      } else if (st.expired) {
        state = state.copyWith(clearQr: true, error: '二维码已过期，请重新获取');
      } else if (st.waitingConfirm) {
        // 802：手机已扫码待确认——给用户明确提示，避免「扫码后没反应」。
        state = state.copyWith(
            qrMessage: '已在手机确认登录，正在完成…',
            clearError: true);
      }
      return st;
    } catch (_) {
      state = state.copyWith(error: '扫码状态查询失败');
      return null;
    }
  }

  /// 扫码成功后的账号补全（异步降级：失败不影响已登录态）。
  Future<void> _refreshAccountAfterQr() async {
    try {
      final NeteaseAccount acc = await _api.account();
      state = state.copyWith(account: acc);
    } catch (_) {
      // 账号接口暂不可用：保留登录态（cookie 已落盘），下次搜索会自动校验。
    }
  }

  /// 登出：擦除密文 + 清内存会话。
  Future<void> logout() async {
    state = state.copyWith(busy: true);
    await _box.deleteSecret(SecureBox.kNeteaseCookie);
    _api.clearCookie();
    state = const NeteaseAuthState(restoring: false);
  }

  static String _readable(NeteaseApiException e) =>
      e.isAuthFailure ? '网易云登录态无效，请重新登录' : '网易云接口调用失败（${e.code}）';
}

/// 搜索结果。未登录时直接给空列表，不打接口。
final AutoDisposeFutureProviderFamily<List<Track>, String> neteaseSearchProvider =
    FutureProvider.autoDispose.family<List<Track>, String>((Ref ref, String keyword) async {
  final NeteaseAuthState auth = ref.watch(neteaseAuthProvider);
  if (!auth.isLoggedIn || keyword.trim().isEmpty) return const <Track>[];
  return ref.watch(neteaseSourceProvider).search(keyword.trim());
});

/// #279 搜索加固：把搜索/接口异常转成用户可读文案。
///
/// 优先级：登录失效 → 引导重新登录；风控(-462)/限流(-405) → 友好提示；
/// 网络类 → 网络异常；其余 → 带业务码的通用提示。
String neteaseErrorText(Object e) {
  if (e is NeteaseApiException) {
    if (e.isAuthFailure) return '网易云登录态已失效，请重新登录';
    if (e.code == -462) return '操作过于频繁，请稍候重试';
    if (e.code == -405) return '请求被限制，请稍后重试';
    return '网易云接口异常（${e.code}）';
  }
  if (e is TimeoutException) return '网络超时，请检查连接后重试';
  final String msg = e.toString();
  if (msg.contains('SocketException') || msg.toLowerCase().contains('network')) {
    return '网络异常，请检查网络连接';
  }
  return '搜索失败，请稍后重试';
}

/// 是否登录失效类错误（可引导去登录而非单纯重试）。
bool neteaseIsAuthFailure(Object e) =>
    e is NeteaseApiException && e.isAuthFailure;

/// 每日推荐。未登录时直接给空列表，不打接口（与搜索同策略）。
///
/// 用户手动刷新时 UI 侧 [ref.invalidate] 本 provider 即可。
final AutoDisposeFutureProvider<List<Track>> neteaseDailyRecommendProvider =
    FutureProvider.autoDispose<List<Track>>((Ref ref) async {
  final NeteaseAuthState auth = ref.watch(neteaseAuthProvider);
  if (!auth.isLoggedIn) return const <Track>[];
  return ref.watch(neteaseSourceProvider).recommend();
});

/// 私人漫游。未登录时直接给空列表，不打接口。
///
/// 漫游是无限流：UI 侧用 [neteaseRoamMoreProvider] 追加批次（保留已加载列表）。
final AutoDisposeFutureProvider<List<Track>> neteaseRoamProvider =
    FutureProvider.autoDispose<List<Track>>((Ref ref) async {
  final NeteaseAuthState auth = ref.watch(neteaseAuthProvider);
  if (!auth.isLoggedIn) return const <Track>[];
  return ref.watch(neteaseSourceProvider).roam();
});

/// 当前登录用户的歌单列表。未登录时直接给空列表。
final AutoDisposeFutureProvider<List<NeteasePlaylist>> neteasePlaylistsProvider =
    FutureProvider.autoDispose<List<NeteasePlaylist>>((Ref ref) async {
  final NeteaseAuthState auth = ref.watch(neteaseAuthProvider);
  if (!auth.isLoggedIn) return const <NeteasePlaylist>[];
  return ref.watch(neteaseSourceProvider).playlists();
});

/// 单个网易云歌单内的曲目（按歌单 id 取）。未登录时给空列表。
///
/// 返回类型与 [NeteaseTrackListPage.firstProvider] 兼容（family 实例也是
/// `AutoDisposeFutureProvider<List<Track>>`），可直接复用曲目列表薄壳。
final AutoDisposeFutureProviderFamily<List<Track>, int>
    neteasePlaylistTracksProvider = FutureProvider.autoDispose
        .family<List<Track>, int>((Ref ref, int playlistId) async {
  final NeteaseAuthState auth = ref.watch(neteaseAuthProvider);
  if (!auth.isLoggedIn) return const <Track>[];
  return ref.watch(neteaseSourceProvider).playlistTracks(playlistId);
});
