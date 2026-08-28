import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/content/content_service.dart';
import '../../services/security/http_client_factory.dart';
import '../security/cert_policy_provider.dart';
import '../storage/storage_providers.dart';

/// 官方内容服务地址（relay_server 的 http 根；与中继 wss 同域）。
const String kDefaultContentBaseUrl = 'https://relay.245959623.xyz';

/// 内容服务地址（cl08：设置可改，prefs 键 `content_base_url`）。
class ContentBaseUrlPrefs extends StateNotifier<String> {
  ContentBaseUrlPrefs(this._prefs)
      : super(_prefs.getString('content_base_url') ?? kDefaultContentBaseUrl);

  final SharedPreferences _prefs;

  void set(String v) {
    final String next = v.trim().replaceAll(RegExp(r'/+$'), '');
    if (next.isEmpty) return;
    state = next;
    unawaited(_prefs.setString('content_base_url', next));
  }
}

final StateNotifierProvider<ContentBaseUrlPrefs, String> contentBaseUrlProvider =
    StateNotifierProvider<ContentBaseUrlPrefs, String>(
  (Ref ref) => ContentBaseUrlPrefs(ref.read(prefsProvider)),
);

/// 随机内容（场景/歌单，后端下发，轮换展示）。
final AutoDisposeFutureProvider<RemoteContent?> remoteContentProvider =
    FutureProvider.autoDispose<RemoteContent?>(
  (Ref ref) => fetchRemoteContent(
    ref.watch(contentBaseUrlProvider),
    client: makeHttpClient(
      lenient: ref.watch(certPolicyProvider) == CertPolicy.lenient,
    ),
  ),
);

/// 公告列表（后端下发）。
final AutoDisposeFutureProvider<List<RemoteNotice>> remoteNoticesProvider =
    FutureProvider.autoDispose<List<RemoteNotice>>(
  (Ref ref) => fetchRemoteNotices(
    ref.watch(contentBaseUrlProvider),
    client: makeHttpClient(
      lenient: ref.watch(certPolicyProvider) == CertPolicy.lenient,
    ),
  ),
);
