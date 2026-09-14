import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/core/theme/app_theme_colors.dart';
import 'package:xingli_music/l10n/app_localizations.dart';
import 'package:xingli_music/models/capability.dart';
import 'package:xingli_music/models/track.dart';
import 'package:xingli_music/pages/sources/aggregate_search_page.dart';
import 'package:xingli_music/providers/audio/audio_providers.dart';
import 'package:xingli_music/providers/content/capability_providers.dart';
import 'package:xingli_music/providers/storage/storage_providers.dart';
import 'package:xingli_music/providers/sources/bilibili_provider.dart';
import 'package:xingli_music/providers/sources/netease_provider.dart';
import 'package:xingli_music/providers/stats/track_stats_providers.dart';
import 'package:xingli_music/services/audio/sources/bilibili/bilibili_api.dart';
import 'package:xingli_music/services/audio/sources/netease/netease_api.dart';
import 'package:xingli_music/services/security/secure_store.dart';
import 'package:xingli_music/widgets/common/state_views.dart';

/// 缺陷1 回归：聚合搜索「全部」筛选下，单源首次批次失败（如网易云 401 / B站 403）
/// 不应被静默吞掉成「没有匹配的结果」，而应在结果列表顶部渲染非阻断错误条，
/// 同时其余源的结果照常渲染。
///
/// 不 pump 整个 App：App 启动链会初始化音频插件并永久挂起（实测卡 18 分钟）。
/// 这里直接挂 [AggregateSearchPage]，并把搜索 / 登录态 / 能力清单等外部依赖
/// 全部覆写为静态值；本地化代理按 [immersive_player_unify_test.dart] 的写法补齐，
/// 否则 `AppLocalizations.of(context)` 返回 null 抛 `_TypeError`。
void main() {
  const Track kNeTrack = Track(
    title: '网易云曲',
    artist: '歌手A',
    uri: 'https://example.invalid/ne1.mp3',
    sourceId: 'netease',
    coverUrl: 'https://example.invalid/ne1.jpg',
  );
  const Track kBiTrack = Track(
    title: 'B站视频',
    artist: 'UP主B',
    uri: 'https://example.invalid/bi1.mp4',
    sourceId: 'bilibili',
    coverUrl: 'https://example.invalid/bi1.jpg',
  );

  ThemeData themeOf(Brightness b) => ThemeData(
        brightness: b,
        extensions: <ThemeExtension<dynamic>>[
          b == Brightness.dark ? AppThemeColors.dark : AppThemeColors.light,
        ],
      );

  /// 登录态桩：网易云已登录（neActive=true），B站未登录（免登录也能搜，biOn 仅
  /// 受能力开关约束）。两个桩都不跑 `restore()`，避免安全存储 / 网络调用。
  Future<void> pumpAggregate(
    WidgetTester tester, {
    required bool neError,
    required bool biError,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // prefs 必须在测试里显式覆写（生产环境在 main() 中覆写）；否则
          // capabilitySelectionProvider / searchHistoryProvider 等读 prefs 的
          // provider 在 build 期抛 `prefsProvider 需在 main() 中 override`。
          prefsProvider.overrideWithValue(prefs),
          neteaseAuthProvider.overrideWith((Ref ref) => _StubNeteaseAuth()),
          bilibiliAuthProvider.overrideWith((Ref ref) => _StubBilibiliAuth()),
          // 能力清单空 → 所有源不被禁用（neOn / biOn 均为 true）。
          capabilitiesProvider.overrideWith((Ref ref) => <Capability>[]),
          // 用户显式关掉的来源集合为空 —— 否则 capabilitySelectionProvider 会
          // 在构造时读 prefs（虽已 override，但 StateNotifier 构造路径更脆），
          // 直接在测试里钉死为「没有源被关掉」。
          capabilitySelectionProvider.overrideWith(
            (Ref ref) => CapabilitySelectionPrefs(prefs),
          ),
          // 本地曲库空（不扫盘 / 不走网络）。
          musicLibraryProvider.overrideWith(
            (Ref ref) => Future<List<Track>>.value(<Track>[]),
          ),
          // 收藏态桩（避免 sqflite）。
          isFavoriteProvider.overrideWith(
            (Ref ref, String key) => Future<bool>.value(false),
          ),
          // 两个搜索 provider：一成功一失败（按参数互换，覆盖两种组合）。
          neteaseSearchProvider('测试').overrideWith(
            (Ref ref) => neError
                ? Future<List<Track>>.error(Exception('401'))
                : Future<List<Track>>.value(<Track>[kNeTrack]),
          ),
          bilibiliSearchProvider('测试').overrideWith(
            (Ref ref) => biError
                ? Future<List<Track>>.error(Exception('403'))
                : Future<List<Track>>.value(<Track>[kBiTrack]),
          ),
        ],
        child: MaterialApp(
          theme: themeOf(Brightness.light),
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const AggregateSearchPage(),
        ),
      ),
    );
    await tester.pump();
    // 触发一次搜索（onSubmitted 走 _submit，设置 _keyword 并使 provider 重取）。
    await tester.enterText(find.byType(TextField), '测试');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('缺陷1：B站失败 + 网易云成功 → 错误条出现且网易云结果仍渲染',
      (WidgetTester tester) async {
    await pumpAggregate(tester, neError: false, biError: true);

    // 非阻断错误条出现（B站）。
    expect(find.byType(SourceErrorBar), findsOneWidget);
    // 成功源（网易云）结果照常渲染。
    expect(find.text('网易云曲'), findsOneWidget);
    // 不应退回「没有匹配的结果」。
    expect(find.text('没有匹配的结果'), findsNothing);
  });

  testWidgets('缺陷1：网易云失败 + B站成功 → 错误条出现且B站结果仍渲染',
      (WidgetTester tester) async {
    await pumpAggregate(tester, neError: true, biError: false);

    expect(find.byType(SourceErrorBar), findsOneWidget);
    expect(find.text('B站视频'), findsOneWidget);
    expect(find.text('没有匹配的结果'), findsNothing);
  });

  testWidgets('缺陷1：两源都成功 → 不出现错误条，两源结果都渲染',
      (WidgetTester tester) async {
    await pumpAggregate(tester, neError: false, biError: false);

    expect(find.byType(SourceErrorBar), findsNothing);
    expect(find.text('网易云曲'), findsOneWidget);
    expect(find.text('B站视频'), findsOneWidget);
  });

  testWidgets('缺陷1：两源都失败 → 至少一条错误条，不显示「没有匹配的结果」',
      (WidgetTester tester) async {
    await pumpAggregate(tester, neError: true, biError: true);

    // all 为空但激活源有失败 → 仍渲染错误条（非空态时退回「没有匹配的结果」）。
    expect(find.byType(SourceErrorBar), findsWidgets);
    expect(find.text('没有匹配的结果'), findsNothing);
  });
}

/// 已登录的网易云登录态桩。直接继承真实 notifier 以满足
/// `neteaseAuthProvider.overrideWith` 的返回类型约束，并覆盖 `restore()`
/// 为 no-op（否则会读密文 cookie / 打网络），构造函数同步置为已登录态。
class _StubNeteaseAuth extends NeteaseAuthNotifier {
  _StubNeteaseAuth() : super(NeteaseApi(), SecureBox()) {
    state = const NeteaseAuthState(
      restoring: false,
      account: NeteaseAccount(uid: 1, nickname: '测试'),
    );
  }

  @override
  Future<void> restore() async {}
}

/// 已登录的 B站登录态桩（B站搜索免登录，这里仅演示可置为已登录态）。
class _StubBilibiliAuth extends BilibiliAuthNotifier {
  _StubBilibiliAuth() : super(BilibiliApi(), SecureBox()) {
    state = const BilibiliAuthState(restoring: false, nickname: '测试UP');
  }

  @override
  Future<void> restore() async {}
}
