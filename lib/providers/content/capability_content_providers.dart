import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/capability.dart';
import '../../models/track.dart';
import '../sources/netease_provider.dart';
import 'capability_providers.dart';

// ═══ 能力 → 内容 的解析层 ═══════════════════════════════════════════
//
// 单独成文件，是为了让 `capability_providers.dart` 保持「只声明、不接线」：
// 它不认识任何音源，音源层也不认识它。两边在这一层汇合，避免循环依赖。

/// 按能力 id 取该能力产出的曲目。
///
/// 三条约定，UI 依赖它们：
///
/// 1. **能力关闭 / 尚未实现 → 直接返回空列表，不打接口**。门控集中在这里做，
///    每个入口不必各自判断，也不会出现「用户在设置里关掉了、后台还在偷偷请求」。
/// 2. **未接入的能力返回空，不抛异常**。服务端以后登记了新能力 id，老客户端
///    走到 default 分支返回空即可，不会因为不认识而崩。
/// 3. **按需执行**（autoDispose + family）：只有被 watch 的能力才真正跑，
///    关掉的能力零网络开销、零内存占用。
final AutoDisposeFutureProviderFamily<List<Track>, String>
    capabilityTracksProvider =
    FutureProvider.autoDispose.family<List<Track>, String>(
        (Ref ref, String capabilityId) async {
  final Capability? cap =
      _findCapability(ref.watch(capabilitiesProvider), capabilityId);

  // 清单里没有 / 被用户关掉 / 服务端只登记未实现 —— 三者都不该发起请求。
  if (cap == null || !cap.enabled || cap.isPlanned) return const <Track>[];

  // 客户端执行的能力：端上已有完整实现（weapi 加解密 + 登录态都在本地），
  // 凭据不出设备，与 credentialOwner = client 的约定一致。
  switch (capabilityId) {
    case 'netease.recommend':
      return ref.watch(neteaseDailyRecommendProvider.future);
    default:
      return const <Track>[];
  }
});

/// 该能力是否因「未登录」而拿不到内容。
///
/// 每日推荐这类接口未登录就是空的，UI 若只看空列表会显示一片空白，用户无从
/// 判断是「没内容」还是「要登录」。这里把原因单独暴露出去，UI 据此引导登录。
///
/// 服务端下发的能力不参与判定——它们不需要本地登录态，一律 false。
final ProviderFamily<bool, String> capabilityBlockedByAuthProvider =
    Provider.family<bool, String>((Ref ref, String capabilityId) {
  return switch (capabilityId) {
    'netease.recommend' => !ref.watch(neteaseAuthProvider).isLoggedIn,
    _ => false,
  };
});

/// 在能力列表中查找。
///
/// 不用 `firstWhere` / `firstOrNull`：前者找不到会抛 StateError，后者依赖
/// package:collection。服务端可能下发客户端不认识的 id，找不到是常态而非异常。
Capability? _findCapability(List<Capability> caps, String id) {
  for (final Capability c in caps) {
    if (c.id == id) return c;
  }
  return null;
}
