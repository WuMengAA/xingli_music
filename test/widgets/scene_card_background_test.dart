import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/core/theme/app_theme_colors.dart';
import 'package:xingli_music/models/scene.dart';
import 'package:xingli_music/providers/audio/audio_providers.dart';
import 'package:xingli_music/providers/scene/scene_providers.dart';
import 'package:xingli_music/providers/storage/storage_providers.dart';
import 'package:xingli_music/widgets/card_stack.dart';
import 'package:xingli_music/widgets/liquid_glass.dart';

/// 场景卡片背景渐变回归测试
///
/// 修复背景：场景页默认场景卡片没有背景（露出纯白 Card 底），
/// 期望显示该场景对应的深色渐变背景。
///
/// 覆盖点：
/// 1. bgTop / bgBottom 覆盖色优先生效；
/// 2. 无覆盖色时回落到 visual.gradientColors（stops 长度匹配时一并生效）；
/// 3. 两者都缺失时兜底为中性深色渐变（不会露出纯白底）；
/// 4. Card 本身透明、无 elevation，渐变由外层 Container 提供；
/// 5. 深色背景下文字为浅色，保障对比度；
/// 6. 切换场景时背景随之变化。
void main() {
  // ── 测试夹具 ────────────────────────────────────────────────

  const SceneVisual baseVisual = SceneVisual(
    gradientColors: <Color>[Color(0xFF2B1B4D), Color(0xFF120B22)],
    stops: <double>[0.0, 1.0],
    accent: Color(0xFF9B7BFF),
    glyph: '✦',
  );

  /// 构造测试用 Scene；默认带内置深色渐变，可按用例覆盖。
  Scene makeScene({
    String id = 'test_scene',
    String name = '星夜',
    SceneVisual visual = baseVisual,
    Color? bgTop,
    Color? bgBottom,
  }) {
    return Scene(
      id: id,
      name: name,
      mood: '静谧',
      desc: '一片安静的星空',
      track: '夜的第七章',
      artist: '星璃',
      soundscape: 'night',
      icon: 'star',
      visual: visual,
      visualWeight: 0.8,
      valence: 0.5,
      energy: 0.3,
      bgTop: bgTop,
      bgBottom: bgBottom,
    );
  }

  /// 挂载 SceneCardStack。
  ///
  /// _TrackProgress 是 ConsumerWidget，会订阅位置/时长流，
  /// 这里覆写为静态流，避免测试里触碰真实音频引擎（插件不可用）。
  Future<void> pumpStack(
    WidgetTester tester, {
    required List<Scene> scenes,
    int currentIndex = 0,
    void Function(int)? onSceneChanged,
    Brightness brightness = Brightness.dark,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          prefsProvider.overrideWithValue(prefs),
          musicPositionProvider.overrideWith(
            (ref) => Stream<Duration?>.value(Duration.zero),
          ),
          musicDurationProvider.overrideWith(
            (ref) => Stream<Duration?>.value(const Duration(minutes: 3)),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            extensions: <ThemeExtension<dynamic>>[
              brightness == Brightness.dark
                  ? AppThemeColors.dark
                  : AppThemeColors.light,
            ],
          ),
          home: Scaffold(
            body: SceneCardStack(
              scenes: scenes,
              currentIndex: currentIndex,
              onSceneChanged: onSceneChanged ?? (_) {},
            ),
          ),
        ),
      ),
    );
    // 不用 pumpAndSettle：AnimatedScale / AnimatedSwitcher 有持续动画，
    // 固定推进两帧即可拿到稳定的首帧布局。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  /// 找出承载场景渐变背景的 DecoratedBox（cl52-B 液态玻璃：渐变由
  /// 最底层的 DecoratedBox(decoration: BoxDecoration(gradient:)) 提供，
  /// 外层再叠加实色浓度 + LiquidGlass 磨砂 + 透明 Card）。
  Finder gradientContainerFinder() {
    return find.byWidgetPredicate(
      (Widget w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient is LinearGradient,
      description: '带 LinearGradient 的 DecoratedBox 背景',
    );
  }

  /// 取出背景渐变；找不到时直接失败（说明卡片仍是无背景状态）。
  ///
  /// 多场景时 `deck` 里会有当前卡之后的预览卡（同样带渐变），这里优先取
  /// AnimatedSwitcher（最上层当前卡）内的渐变，避免取到预览卡。
  LinearGradient readGradient(WidgetTester tester) {
    final Finder inFront = find.descendant(
      of: find.byType(AnimatedSwitcher),
      matching: gradientContainerFinder(),
    );
    final Finder finder =
        inFront.evaluate().isNotEmpty ? inFront : gradientContainerFinder();
    expect(finder, findsWidgets,
        reason: '卡片子树中应存在带 LinearGradient 的背景 DecoratedBox');
    final DecoratedBox c = tester.widget<DecoratedBox>(finder.first);
    return (c.decoration as BoxDecoration).gradient as LinearGradient;
  }

  // ── 用例 ────────────────────────────────────────────────────

  group('场景卡片背景渐变', () {
    testWidgets('a) bgTop/bgBottom 覆盖色优先作为背景渐变', (WidgetTester tester) async {
      const Color top = Color(0xFF3A2A6E);
      const Color bottom = Color(0xFF0B0716);
      final Scene scene = makeScene(bgTop: top, bgBottom: bottom);

      await pumpStack(tester, scenes: <Scene>[scene]);

      final LinearGradient g = readGradient(tester);
      expect(g.colors, <Color>[top, bottom]);
      expect(g.begin, Alignment.topCenter);
      expect(g.end, Alignment.bottomCenter);
      // 覆盖色分支不带 stops
      expect(g.stops, isNull);
    });

    testWidgets('b) 无覆盖色时使用 visual.gradientColors 与匹配的 stops',
        (WidgetTester tester) async {
      const List<Color> colors = <Color>[Color(0xFF14304A), Color(0xFF07131F)];
      const List<double> stops = <double>[0.0, 0.9];
      final Scene scene = makeScene(
        visual: const SceneVisual(
          gradientColors: colors,
          stops: stops,
          accent: Color(0xFF6FC3FF),
          glyph: '~',
        ),
      );

      await pumpStack(tester, scenes: <Scene>[scene]);

      final LinearGradient g = readGradient(tester);
      expect(g.colors, colors);
      expect(g.stops, stops, reason: 'stops 长度与 colors 一致时应一并生效');
    });

    testWidgets('b2) stops 长度与 colors 不一致时忽略 stops',
        (WidgetTester tester) async {
      const List<Color> colors = <Color>[
        Color(0xFF14304A),
        Color(0xFF0A1E30),
        Color(0xFF07131F),
      ];
      final Scene scene = makeScene(
        visual: const SceneVisual(
          gradientColors: colors,
          stops: <double>[0.0, 1.0], // 长度 2 ≠ colors 长度 3
          accent: Color(0xFF6FC3FF),
          glyph: '~',
        ),
      );

      await pumpStack(tester, scenes: <Scene>[scene]);

      final LinearGradient g = readGradient(tester);
      expect(g.colors, colors);
      expect(g.stops, isNull, reason: '长度不匹配的 stops 会让渐变抛错，应被忽略');
    });

    testWidgets('c) 缺数据场景兜底为中性深色渐变（不露白底）',
        (WidgetTester tester) async {
      final Scene scene = makeScene(
        visual: const SceneVisual(
          gradientColors: <Color>[],
          stops: <double>[],
          accent: Color(0xFF9B7BFF),
          glyph: '✦',
        ),
      );

      await pumpStack(tester, scenes: <Scene>[scene]);

      final LinearGradient g = readGradient(tester);
      // cl52-B 兜底：语义色（跟随主题的 bgSurface/bgPage），不再是写死的
      // 暗紫色；主题浅色时亮度偏高，故只验证「非空且 stops 被忽略」。
      expect(g.colors, isNotEmpty, reason: '兜底渐变必须有颜色');
      // 兜底色必须是深色：亮度足够低才不会重现"白底"问题
      for (final Color c in g.colors) {
        expect(c.computeLuminance(), lessThan(0.25),
            reason: '兜底渐变必须是深色');
      }
    });

    testWidgets('d) Card 透明且无 elevation，渐变由外层 DecoratedBox 提供（液态玻璃）',
        (WidgetTester tester) async {
      await pumpStack(tester, scenes: <Scene>[makeScene()]);

      final Card card = tester.widget<Card>(find.byType(Card));
      expect(card.color, Colors.transparent,
          reason: 'Card 不能有自己的（白色）底色，否则会盖住渐变');
      expect(card.elevation, 0);

      // 渐变容器存在（DecoratedBox，cl52-B：不再用 Container + 圆角投影）。
      expect(gradientContainerFinder(), findsWidgets);
      // 液态玻璃容器存在（替代原投影 Container）
      expect(find.byType(LiquidGlass), findsWidgets);
    });

    testWidgets('e) 文字颜色跟随主题（cl52-B：浅色主题用深色文字保证可读）',
        (WidgetTester tester) async {
      final Scene scene = makeScene(name: '星夜');
      await pumpStack(tester, scenes: <Scene>[scene]);

      // 测试默认浅色主题：文字应为主题主色（textPrimary），与浅色玻璃对比可读。
      final Text sceneName = tester.widget<Text>(find.text('星夜'));
      expect(sceneName.style?.color, isNotNull,
          reason: '场景名应有颜色（跟随主题）');

      final Text trackTitle = tester.widget<Text>(find.text('夜的第七章'));
      expect(trackTitle.style?.color, isNotNull);
    });

    testWidgets('f) 切换场景时背景渐变随之变化', (WidgetTester tester) async {
      final Scene a = makeScene(
        id: 'scene_a',
        name: 'A',
        bgTop: const Color(0xFF3A2A6E),
        bgBottom: const Color(0xFF0B0716),
      );
      final Scene b = makeScene(
        id: 'scene_b',
        name: 'B',
        bgTop: const Color(0xFF102A2A),
        bgBottom: const Color(0xFF03100F),
      );

      await pumpStack(tester, scenes: <Scene>[a, b], currentIndex: 0);
      expect(readGradient(tester).colors, <Color>[a.bgTop!, a.bgBottom!]);

      await pumpStack(tester, scenes: <Scene>[a, b], currentIndex: 1);
      // AnimatedSwitcher 交叉淡出期间可能同时存在两张卡片，等切换动画结束
      await tester.pump(const Duration(milliseconds: 800));

      expect(readGradient(tester).colors, <Color>[b.bgTop!, b.bgBottom!],
          reason: 'AnimatedSwitcher 以 ValueKey(scene.id) 区分，背景应跟随切换');
    });
  });

  // ── 原始缺陷场景复现：用真实内置场景数据 ──────────────────────
  group('内置场景（缺陷复现）', () {
    testWidgets('默认场景（index 0 星夜）卡片有深色渐变背景，不是白底',
        (WidgetTester tester) async {
      await pumpStack(tester, scenes: builtInScenes, currentIndex: 0);

      final LinearGradient g = readGradient(tester);
      expect(g.colors, builtInScenes.first.visual.gradientColors,
          reason: '默认场景应使用自身内置渐变');
      expect(g.stops, builtInScenes.first.visual.stops);
      for (final Color c in g.colors) {
        expect(c.computeLuminance(), lessThan(0.15),
            reason: '默认场景背景必须是深色，缺陷正是这里露出了白底');
      }
    });

    testWidgets('全部 7 个内置场景均渲染深色渐变背景', (WidgetTester tester) async {
      expect(builtInScenes, isNotEmpty);

      for (int i = 0; i < builtInScenes.length; i++) {
        await pumpStack(tester, scenes: builtInScenes, currentIndex: i);
        await tester.pump(const Duration(milliseconds: 800));

        final Scene s = builtInScenes[i];
        final LinearGradient g = readGradient(tester);
        expect(g.colors, s.visual.gradientColors,
            reason: '场景 ${s.id} 应使用自身渐变色');
        for (final Color c in g.colors) {
          expect(c.computeLuminance(), lessThan(0.2),
              reason: '场景 ${s.id} 背景应为深色');
        }
      }
    });
  });
}
