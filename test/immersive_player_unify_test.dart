import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/core/theme/app_theme_colors.dart';
import 'package:xingli_music/l10n/app_localizations.dart';
import 'package:xingli_music/models/track.dart';
import 'package:xingli_music/pages/now_playing/now_playing_page.dart';
import 'package:xingli_music/providers/audio/audio_providers.dart';
import 'package:xingli_music/providers/audio/visualizer_providers.dart';
import 'package:xingli_music/providers/storage/storage_providers.dart';
import 'package:xingli_music/widgets/lyrics/lyrics_view.dart';
import 'package:xingli_music/widgets/playback/home_player_view.dart';
import 'package:xingli_music/widgets/playback/immersive_player_visuals.dart';
import 'package:xingli_music/widgets/visualizer/reactor_visualizer.dart';

/// 播放器两页统一 · 回归测试（2026-09-14）
///
/// 背景：主页沉浸播放器与整页「正在播放」此前是两套皮（背景 / 封面 / 反应堆 /
/// 横屏阈值都不一致），用户点开整页会有明显「换页换皮」。
///
/// 本测试锁死统一后的四条契约：
/// 1. [ImmersiveSurface] 的**局部深色面覆盖**：即使在浅色主题下，沉浸面内部的
///    语义前景色（`context.appColors.textPrimary`）也必须是**浅色**——这是
///    「曲名 / 歌词 / 控件自动变浅」的唯一机制，一旦失效浅色主题下会出现
///    「深灰字压深色底」不可读。
/// 2. [ImmersiveBackground] 的 `videoThrough` 分支：主页（true）不铺模糊封面
///    底衬（让 B 站视频透出），整页（false）必须铺。
/// 3. [ImmersiveDiscCover] 为两页共用：旋转角严格等于 `spin.value × 2π`。
/// 4. 端到端：主页与整页在**浅 / 深主题 × 竖 / 横屏**四种组合下都渲染出同一批
///    共享组件，且不抛任何 Flutter 异常（含 RenderFlex 溢出）。
///
/// 注意：不 pump 整个 App —— App 启动链会初始化音频服务等平台插件，
/// 在 `flutter test`（无插件宿主）下会永久等待。这里直接挂载两个页面，
/// 并把音频 / 可视化等外部流全部覆写为静态值。
void main() {
  const Track kTrack = Track(
    title: '测试曲目',
    artist: '星璃',
    uri: 'https://example.invalid/a.mp3',
    sourceId: 'test',
    coverUrl: 'https://example.invalid/cover.jpg',
  );

  const List<double> kBands = <double>[
    0.14, 0.22, 0.18, 0.12, 0.16, 0.20, 0.13, 0.10,
    0.10, 0.13, 0.20, 0.16, 0.12, 0.18, 0.22, 0.14,
  ];

  ThemeData themeOf(Brightness brightness) => ThemeData(
        brightness: brightness,
        extensions: <ThemeExtension<dynamic>>[
          brightness == Brightness.dark
              ? AppThemeColors.dark
              : AppThemeColors.light,
        ],
      );

  // ── 1. ImmersiveSurface：局部深色面覆盖 ───────────────────────
  group('ImmersiveSurface 局部深色面', () {
    Future<void> pumpSurface(
      WidgetTester tester,
      Brightness brightness, {
      required ValueChanged<BuildContext> onInner,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeOf(brightness),
            home: Scaffold(
              body: ImmersiveSurface(
                child: Builder(
                  builder: (BuildContext c) {
                    onInner(c);
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('浅色主题下，沉浸面内语义前景色变成浅色（可读）',
        (WidgetTester tester) async {
      late BuildContext inner;
      await pumpSurface(
        tester,
        Brightness.light,
        onInner: (BuildContext c) => inner = c,
      );

      // 语义色是「深色面」变体 → 前景亮、底色暗。
      expect(
        inner.appColors.textPrimary.computeLuminance(),
        greaterThan(0.5),
        reason: '沉浸面内前景文字必须是浅色（否则浅色主题下深灰字压深色底不可读）',
      );
      expect(
        inner.appColors.bgPage.computeLuminance(),
        lessThan(0.2),
        reason: '沉浸面内页面底色必须是深色',
      );
    });

    testWidgets('深色主题下依然保持浅色前景（不因外层主题而回退）',
        (WidgetTester tester) async {
      late BuildContext inner;
      await pumpSurface(
        tester,
        Brightness.dark,
        onInner: (BuildContext c) => inner = c,
      );
      expect(inner.appColors.textPrimary.computeLuminance(), greaterThan(0.5));
    });

    testWidgets('不改变外层 brightness（避免与 colorScheme 断言冲突）',
        (WidgetTester tester) async {
      late Brightness seen;
      await pumpSurface(
        tester,
        Brightness.light,
        onInner: (BuildContext c) {
          // copyWith 只换 extensions，Brightness 必须与外层一致。
          seen = Theme.of(c).brightness;
        },
      );
      expect(seen, Brightness.light);
    });
  });

  // ── 2. ImmersiveBackground：videoThrough 分支 ─────────────────
  group('ImmersiveBackground 背景分支', () {
    Future<void> pumpBg(
      WidgetTester tester,
      Brightness brightness, {
      required bool videoThrough,
      Track? track = kTrack,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeOf(brightness),
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ImmersiveBackground(
                      track: track,
                      videoThrough: videoThrough,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
    }

    testWidgets('主页 videoThrough=true：不铺模糊封面底衬（让视频透出）',
        (WidgetTester tester) async {
      await pumpBg(tester, Brightness.dark, videoThrough: true);
      expect(
        find.byType(ImageFiltered),
        findsNothing,
        reason: '主页背景要让下层 B 站视频透出，不能叠模糊封面',
      );
      // 提色渐变仍在（背景还是沉浸面，不是空壳）。
      expect(find.byType(DecoratedBox), findsWidgets);
    });

    testWidgets('整页 videoThrough=false：铺模糊封面底衬', (WidgetTester tester) async {
      await pumpBg(tester, Brightness.dark, videoThrough: false);
      expect(
        find.byType(ImageFiltered),
        findsOneWidget,
        reason: '整页无视频透出，需要模糊封面兜底避免背景空洞',
      );
      final ImageFiltered f =
          tester.widget<ImageFiltered>(find.byType(ImageFiltered));
      expect(f.imageFilter, isA<ImageFilter>());
    });

    testWidgets('无封面曲目：不尝试渲染封面底衬（不崩）', (WidgetTester tester) async {
      await pumpBg(tester, Brightness.dark, videoThrough: false, track: null);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('浅色主题下背景依然是深色基座（前景白字可读）',
        (WidgetTester tester) async {
      await pumpBg(tester, Brightness.light, videoThrough: true);
      final Finder grad = find.byWidgetPredicate(
        (Widget w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient is LinearGradient,
      );
      expect(grad, findsWidgets);
      final LinearGradient g =
          ((tester.widget<DecoratedBox>(grad.last).decoration)
                  as BoxDecoration)
              .gradient! as LinearGradient;
      for (final Color c in g.colors) {
        expect(c.computeLuminance(), lessThan(0.25),
            reason: '沉浸背景基座必须是深色，浅色主题也不例外');
      }
    });
  });

  // ── 3. ImmersiveDiscCover：两页共用的旋转唱片 ─────────────────
  group('ImmersiveDiscCover 共享唱片', () {
    Future<void> pumpDisc(WidgetTester tester, Track? track, double size) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeOf(Brightness.dark),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: ImmersiveDiscCover(
                    track: track,
                    spin: const AlwaysStoppedAnimation<double>(0.25),
                    size: size,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('旋转角 = spin.value × 2π', (WidgetTester tester) async {
      await pumpDisc(tester, kTrack, 200);
      final Transform t = tester.widget<Transform>(
        find.descendant(
          of: find.byType(ImmersiveDiscCover),
          matching: find.byType(Transform),
        ),
      );
      // 0.25 圈 → π/2。用矩阵 m[0]=cos、m[1]=sin 反解角度。
      final double cos = t.transform.storage[0];
      final double sin = t.transform.storage[1];
      expect(math.atan2(sin, cos), closeTo(math.pi / 2, 1e-6));
    });

    testWidgets('无曲目时降级为音符占位（不崩、不空白）', (WidgetTester tester) async {
      await pumpDisc(tester, null, 200);
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('贴边尺寸不留溢出', (WidgetTester tester) async {
      await pumpDisc(tester, null, 160);
      // 框架会自动把 overflow / build 异常记为测试失败，这里只需确认没吃异常。
      expect(tester.takeException(), isNull);
    });
  });

  // ── 4. ImmersiveTrackTitle：统一空态文案 ──────────────────────
  group('ImmersiveTrackTitle 统一文案', () {
    testWidgets('空态文案两页一致', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeOf(Brightness.light),
            home: const Scaffold(body: ImmersiveTrackTitle(track: null)),
          ),
        ),
      );
      expect(find.text('星璃 · 无限音乐空间'), findsOneWidget);
      expect(find.text('从曲库挑一首开始'), findsOneWidget);
    });

    testWidgets('曲名/歌手用白字 + 投影（浅色主题下依然可读）',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: themeOf(Brightness.light),
            home: const Scaffold(body: ImmersiveTrackTitle(track: kTrack)),
          ),
        ),
      );
      final Text title = tester.widget<Text>(find.text('测试曲目'));
      expect(title.style?.color, Colors.white);
      expect(title.style?.shadows, isNotEmpty);
      final Text artist = tester.widget<Text>(find.text('星璃'));
      expect(artist.style?.shadows, isNotEmpty);
    });
  });

  // ── 5. 端到端：两页同源（直接挂载页面，不经 App 启动链） ──────
  group('两页统一 · 端到端', () {
    Future<void> pumpPage(
      WidgetTester tester,
      Widget page, {
      required Size size,
      required Brightness brightness,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            prefsProvider.overrideWithValue(prefs),
            // 覆写全部外部流：测试环境没有音频引擎 / 平台插件，真实流会挂起。
            nowPlayingProvider.overrideWith((Ref ref) => kTrack),
            isPlayingProvider.overrideWith(
              (Ref ref) => Stream<bool>.value(false),
            ),
            musicPositionProvider.overrideWith(
              (Ref ref) => Stream<Duration?>.value(Duration.zero),
            ),
            musicDurationProvider.overrideWith(
              (Ref ref) => Stream<Duration?>.value(const Duration(minutes: 3)),
            ),
            visualizerBandsProvider.overrideWith(
              (Ref ref) => Stream<List<double>>.value(kBands),
            ),
          ],
          child: MaterialApp(
            theme: themeOf(brightness),
            // 必须补齐本地化代理：控制栏（buildTransportRow）走
            // AppLocalizations.of(context)，缺失时代理会返回 null 并抛 _TypeError。
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: page,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }

    Widget homePage() =>
        const Scaffold(body: HomeImmersivePlayer());

    for (final (String label, Size size, Brightness brightness) in <
        (String, Size, Brightness)>[
      ('竖屏 · 浅色主题', Size(412, 915), Brightness.light),
      ('竖屏 · 深色主题', Size(412, 915), Brightness.dark),
      ('横屏 · 浅色主题', Size(915, 412), Brightness.light),
      ('横屏 · 深色主题', Size(915, 412), Brightness.dark),
    ]) {
      testWidgets('主页沉浸播放器 · $label：渲染共享组件且无异常',
          (WidgetTester tester) async {
        await pumpPage(
          tester,
          homePage(),
          size: size,
          brightness: brightness,
        );

        expect(find.byType(HomeImmersivePlayer), findsOneWidget);
        expect(
          find.byType(ImmersiveBackground),
          findsOneWidget,
          reason: '主页必须使用共享背景组件',
        );
        expect(
          find.byType(ImmersiveDiscCover),
          findsOneWidget,
          reason: '主页必须使用共享旋转唱片',
        );
        expect(find.byType(ReactorVisualizer), findsOneWidget);
        // overflow / build 异常会被框架自动判为失败，无需手工断言。
      });

      testWidgets('整页正在播放 · $label：渲染共享组件且无异常',
          (WidgetTester tester) async {
        await pumpPage(
          tester,
          const NowPlayingPage(),
          size: size,
          brightness: brightness,
        );

        expect(find.byType(NowPlayingPage), findsOneWidget);
        expect(
          find.byType(ImmersiveSurface),
          findsOneWidget,
          reason: '整页必须包在同款沉浸面里（否则前景取色与主页不一致）',
        );
        expect(
          find.byType(ImmersiveDiscCover),
          findsOneWidget,
          reason: '整页封面应与主页同为旋转黑胶（此前是方块呼吸封面）',
        );
        expect(
          find.byType(ReactorVisualizer),
          findsOneWidget,
          reason: '整页此前只有装饰粒子，没有与主页同款音效反应堆',
        );
        expect(find.byType(ImmersiveTrackTitle), findsOneWidget);
      });
    }

    testWidgets('浅色主题：主页沉浸面内前景语义色为浅色（歌词可读）',
        (WidgetTester tester) async {
      await pumpPage(
        tester,
        homePage(),
        size: const Size(412, 915),
        brightness: Brightness.light,
      );

      final Finder lyric = find.byType(LyricsView);
      expect(lyric, findsOneWidget);
      final BuildContext ctx = tester.element(lyric);
      expect(
        ctx.appColors.textPrimary.computeLuminance(),
        greaterThan(0.5),
        reason: '浅色主题下主页歌词仍是深灰字 → 不可读（回归）',
      );
    });

    testWidgets('两页共享同一份视觉常量（文案与文字投影同源）',
        (WidgetTester tester) async {
      await pumpPage(
        tester,
        const NowPlayingPage(),
        size: const Size(412, 915),
        brightness: Brightness.light,
      );
      // 空态/白字投影由共享文件提供：两页取到的是同一份常量。
      expect(kImmersiveTextShadow, isNotEmpty);
      final Text title = tester.widget<Text>(
        find.descendant(
          of: find.byType(ImmersiveTrackTitle),
          matching: find.byType(Text),
        ).first,
      );
      expect(title.style?.shadows, kImmersiveTextShadow);
    });
  });
}
