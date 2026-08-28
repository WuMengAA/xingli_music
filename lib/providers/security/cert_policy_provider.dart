import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage_providers.dart';

/// 连接安全策略（cl10：加密连接）。
///
/// - [strict]：默认。校验服务端证书链（系统根 CA），遭遇自签名/伪造证书即拒绝。
/// - [lenient]：自托管局域网场景用——接受任意证书（含自签名），仅加密不认证。
///   不默认开启，避免对官方中转（Cloudflare 合法证书）反而弱化校验。
enum CertPolicy { strict, lenient }

/// 证书策略的 SharedPreferences 键。
const String kCertPolicyKey = 'cert_policy';

/// 证书策略：设置可切换，prefs 键 `cert_policy`。
class CertPolicyNotifier extends StateNotifier<CertPolicy> {
  CertPolicyNotifier(this._prefs, CertPolicy initial) : super(initial);

  final SharedPreferences _prefs;

  void set(CertPolicy p) {
    state = p;
    unawaited(
      _prefs.setString(kCertPolicyKey, p == CertPolicy.lenient ? 'lenient' : 'strict'),
    );
  }
}

final StateNotifierProvider<CertPolicyNotifier, CertPolicy> certPolicyProvider =
    StateNotifierProvider<CertPolicyNotifier, CertPolicy>(
  (Ref ref) => CertPolicyNotifier(
    ref.read(prefsProvider),
    ref.read(prefsProvider).getString(kCertPolicyKey) == 'lenient'
        ? CertPolicy.lenient
        : CertPolicy.strict,
  ),
);

/// 当前是否为宽松（自签名可接受）模式。
bool isLenient(WidgetRef ref) => ref.watch(certPolicyProvider) == CertPolicy.lenient;
