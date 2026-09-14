/// 播放失败可见化 · 回归测试（2026-09-14）
///
/// 背景：播放失败此前只有一次性 toast（或彻底静默），用户看不到任何常驻提示。
/// 本测试锁死新链路的两条契约：
///
/// 1. [playbackErrorProvider] 是**单值最新覆盖**的常驻失败位：
///    `report` 覆盖上一条、`clear` 归零（null）。
/// 2. [PlaybackErrorBanner] 的渲染与自愈：
///    - 无错误时**不占位**（`SizedBox.shrink`，"关闭"后必须真正消失）；
///    - 有错误时展示文案 + 「重试」+「关闭」；
///    - 点「关闭」后清位并消失。
///
/// 注意（避三坑）：
/// - **不 pump 整个 App**——启动链会初始化音频插件，`flutter test` 下永久挂起；
/// - `MaterialApp` 必须补 `locale` + `localizationsDelegates` + `supportedLocales`，
///   否则依赖 `AppLocalizations.of(context)` 的组件会抛 `_TypeError`；
/// - **不覆写 `FlutterError.onError`**——让框架自己抓溢出/构建异常，
///   免得把回归测试变成永远通过的空壳。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/core/theme/app_theme_colors.dart';
import 'package:xingli_music/l10n/app_localizations.dart';
import 'package:xingli_music/models/track.dart';
import 'package:xingli_music/providers/audio/playback_error_provider.dart';
import 'package:xingli_music/widgets/playback/immersive_player_visuals.dart';

void main() {
  const Track kTrack = Track(
    title: '失效曲目',
    artist: '星璃',
    uri: 'https://example.invalid/dead.mp3',
    sourceId: 'test',
  );

  Widget wrap(Widget child, {Brightness brightness = Brightness.dark}) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          extensions: <ThemeExtension<dynamic>>[
            brightness == Brightness.dark
                ? AppThemeColors.dark
                : AppThemeColors.light,
          ],
        ),
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: child),
      ),
    );
  }

  // ── 1. Provider：单值常驻失败位 ───────────────────────────────
  group('playbackErrorProvider', () {
    test('初始为 null（无失败不显示错误条）', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(playbackErrorProvider), isNull);
    });

    test('report 写入，clear 归零', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      final PlaybackErrorNotifier n =
          c.read(playbackErrorProvider.notifier);

      n.report(const PlaybackError(
        message: '无法播放「A」，文件可能缺失或源已失效',
        kind: PlaybackRetryKind.playTrack,
        track: kTrack,
      ));
      final PlaybackError? first = c.read(playbackErrorProvider);
      expect(first, isNotNull);
      expect(first!.message, contains('无法播放'));
      expect(first.kind, PlaybackRetryKind.playTrack);
      expect(first.track, kTrack);

      n.clear();
      expect(c.read(playbackErrorProvider), isNull);
    });

    test('report 覆盖上一条（最新一条生效）', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      final PlaybackErrorNotifier n =
          c.read(playbackErrorProvider.notifier);

      n.report(const PlaybackError(
        message: '第一条',
        kind: PlaybackRetryKind.none,
      ));
      n.report(const PlaybackError(
        message: '第二条',
        kind: PlaybackRetryKind.next,
      ));

      final PlaybackError? err = c.read(playbackErrorProvider);
      expect(err?.message, '第二条');
      expect(err?.kind, PlaybackRetryKind.next);
      expect(err?.track, isNull);
    });
  });

  // ── 2. Banner：渲染 + 关闭自愈 ────────────────────────────────
  group('PlaybackErrorBanner', () {
    testWidgets('无错误时完全不占位', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const PlaybackErrorBanner()));
      await tester.pump();

      expect(find.byType(PlaybackErrorBanner), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(find.text('关闭'), findsNothing);
      expect(
        tester.getSize(find.byType(PlaybackErrorBanner)).height,
        0,
        reason: '无错误时错误条必须彻底消失（不能留一条空白横带压住控制栏）',
      );
    });

    testWidgets('有错误时展示文案 + 重试 + 关闭', (WidgetTester tester) async {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(playbackErrorProvider.notifier).report(const PlaybackError(
        message: '无法播放「失效曲目」，文件可能缺失或源已失效',
        kind: PlaybackRetryKind.playTrack,
        track: kTrack,
      ));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: wrap(const PlaybackErrorBanner()),
        ),
      );
      await tester.pump();

      expect(find.text('无法播放「失效曲目」，文件可能缺失或源已失效'),
          findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('点「关闭」后错误位清空且错误条消失',
        (WidgetTester tester) async {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(playbackErrorProvider.notifier).report(const PlaybackError(
        message: '播到一半断流了',
        kind: PlaybackRetryKind.none,
      ));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: wrap(const PlaybackErrorBanner()),
        ),
      );
      await tester.pump();
      expect(find.text('播到一半断流了'), findsOneWidget);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      expect(c.read(playbackErrorProvider), isNull);
      expect(find.text('播到一半断流了'), findsNothing);
      expect(find.text('关闭'), findsNothing);
    });

    testWidgets('浅色主题下也能渲染出错误条（不残留深色底）',
        (WidgetTester tester) async {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(playbackErrorProvider.notifier).report(const PlaybackError(
        message: '源已失效',
        kind: PlaybackRetryKind.none,
      ));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: wrap(
            const PlaybackErrorBanner(),
            brightness: Brightness.light,
          ),
        ),
      );
      await tester.pump();

      // 错误条文案固定白字（沉浸面内始终压深底），浅色主题下不得被覆盖。
      final Text msg = tester.widget<Text>(find.text('源已失效'));
      expect(msg.style?.color, Colors.white);
    });
  });
}
