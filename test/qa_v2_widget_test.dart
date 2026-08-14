import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/providers/settings/performance_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/app.dart';
import 'package:xingli_music/models/track.dart';
import 'package:xingli_music/providers/storage/storage_providers.dart';
import 'package:xingli_music/widgets/common/info_row.dart';
import 'package:xingli_music/widgets/common/state_chip.dart';
import 'package:xingli_music/widgets/library/folder_view.dart';

void main() {
  group('M1 · 通用组件', () {
    testWidgets('InfoRow 渲染 封面48 + 歌名 + 歌手 + 右对齐时长', (tester) async {
      const Track t = Track(
        title: '星夜',
        artist: '星璃',
        uri: 'file:///tmp/star.mp3',
        source: TrackSource.local,
        duration: Duration(minutes: 3, seconds: 5),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InfoRow(track: t),
          ),
        ),
      );
      expect(find.text('星夜'), findsOneWidget);
      expect(find.text('星璃'), findsOneWidget);
      expect(find.text('3:05'), findsOneWidget);
    });

    testWidgets('StateChip 渲染各 tone 文案', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                StateChip(tone: ChipTone.experimenting, label: '实验中'),
                StateChip(tone: ChipTone.retired, label: '已下线'),
                StateChip(tone: ChipTone.failed, label: '失败'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('实验中'), findsOneWidget);
      expect(find.text('已下线'), findsOneWidget);
      expect(find.text('失败'), findsOneWidget);
    });
  });

  group('M2 · 探索同意 Gate（整 App 集成）', () {
    testWidgets('首次进入探索页出现 Gate，同意后进入实验列表', (tester) async {
      useRoomySurface(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.oobeDone': true,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[prefsProvider.overrideWithValue(prefs), oobeDoneProvider.overrideWith((ref) => true)],
          child: const StelarithMusicApp(),
        ),
      );
      await settle(tester);

      // 切到探索 Tab
      await tester.tap(find.text('探索'));
      await settle(tester);

      // Gate 卡片（未同意）：说明 + 主按钮 + 次按钮
      expect(find.text('这里是实验场所'), findsWidgets);
      expect(find.text('同意并进入'), findsOneWidget);
      expect(find.text('暂不参与'), findsOneWidget);

      // 同意 → 实验列表（数据驱动）
      await tester.tap(find.text('同意并进入'));
      await settle(tester);

      // 注：'智能推荐' 同时出现在常驻「功能模块」入口与实验卡片，故用 findsWidgets（≥1）。
      expect(find.text('智能推荐'), findsWidgets);
      expect(find.text('音效均衡器'), findsWidgets);
      expect(find.text('心情分析'), findsWidgets);
      expect(find.text('传感器'), findsWidgets);
      expect(find.text('AI 陪伴（实验）'), findsWidgets);
    });
  });

  group('M6 · 通知中心（整 App 集成 · P0-M6-1/2）', () {
    testWidgets('设置 → 通知分类渲染三区块 + 事件日志', (tester) async {
      useRoomySurface(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.oobeDone': true,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[prefsProvider.overrideWithValue(prefs), oobeDoneProvider.overrideWith((ref) => true)],
          child: const StelarithMusicApp(),
        ),
      );
      await settle(tester);

      // 切到设置 Tab
      await tester.tap(find.text('设置'));
      await settle(tester);

      // 「通知」文本同时出现在分组小标与分类 tile 上，
      // 用「被 InkWell 包着」锁定真正可点击的 tile（分组小标没有 InkWell）。
      final Finder notificationTile = find.ancestor(
        of: find.text('通知'),
        matching: find.byType(InkWell),
      );
      expect(notificationTile, findsOneWidget, reason: '竖栏应有唯一可点击的「通知」分类');
      await tester.tap(notificationTile);
      await settle(tester);

      // 三区块 + 日志（P0-M6-1）
      expect(find.text('运行状态'), findsOneWidget);
      expect(find.text(termsNowPlaying), findsOneWidget);
      expect(find.text('场景状态'), findsOneWidget);
      expect(find.text('最近事件'), findsOneWidget);

      // ① 三个开关（后台播放 / 锁屏控件 / 通知栏）
      expect(find.text('后台播放'), findsOneWidget);
      expect(find.text('锁屏控件'), findsOneWidget);
      expect(find.text('通知栏'), findsOneWidget);
    });
  });

  group('M3 · 曲库三形态（整 App 集成）', () {
    testWidgets('曲库页含三态 SegmentedButton 与搜索栏', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.oobeDone': true,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[prefsProvider.overrideWithValue(prefs), oobeDoneProvider.overrideWith((ref) => true)],
          child: const StelarithMusicApp(),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('曲库'));
      await settle(tester);

      // R26fx：曲库分页后——「专辑」= Tab + 三形态 segment 各一；验证 Tab 与切换器。
      expect(find.text('卡片'), findsOneWidget);
      expect(find.text('文件夹'), findsOneWidget);
      expect(find.text('歌曲'), findsOneWidget); // 分页 Tab
      expect(find.text('专辑'), findsNWidgets(2)); // Tab + segment
      // 搜索栏 hint
      expect(find.text('搜索歌曲、歌手、专辑'), findsOneWidget);
    });

    testWidgets('P1-1 复验：FolderView 直接渲染非空曲库（竖屏树 + 横屏 master-detail）', (tester) async {
      // 与线上 DemoSource 一致的 3 首在线曲目（sourceId=demo）
      const List<Track> tracks = <Track>[
        Track(
          title: 'Lunar Drift',
          artist: 'Demo',
          uri: 'https://example.com/song1.mp3',
          source: TrackSource.stream,
          sourceId: 'demo',
        ),
        Track(
          title: 'Rain Patterns',
          artist: 'Demo',
          uri: 'https://example.com/song2.mp3',
          source: TrackSource.stream,
          sourceId: 'demo',
        ),
        Track(
          title: 'Moss & Light',
          artist: 'Demo',
          uri: 'https://example.com/song3.mp3',
          source: TrackSource.stream,
          sourceId: 'demo',
        ),
      ];

      // ── 竖屏：可展开目录树 ──────────────────────────────
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: Scaffold(
              body: FolderView(tracks: tracks),
            ),
          ),
        ),
      );
      await tester.pump();
      // 根「全部」+ 在线虚拟目录「音源」（P1-1 修复前此处必崩）
      expect(find.text('全部'), findsOneWidget);
      expect(find.text(termsSource), findsWidgets);

      // ── 横屏：master（左目录树）+ detail（右歌曲列表）──
      tester.view.physicalSize = const Size(900, 500);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('Lunar Drift'), findsOneWidget, reason: '横屏 detail 渲染歌曲');
    });
  });

  group('M1 · 横屏（≥600dp）无 RenderFlex overflow', () {
    testWidgets('800x500 横屏下场景/曲库(卡片)/设置页渲染无异常', (tester) async {
      tester.view.physicalSize = const Size(800, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.oobeDone': true,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[prefsProvider.overrideWithValue(prefs), oobeDoneProvider.overrideWith((ref) => true)],
          child: const StelarithMusicApp(),
        ),
      );
      await settle(tester);

      // 场景页（默认，含微光圆点入口）
      expect(find.text('场景'), findsWidgets);

      // 曲库卡片视图（演示流有曲目 → 网格渲染）
      await tester.tap(find.text('曲库'));
      await settle(tester);
      expect(find.text('卡片'), findsOneWidget);

      // 设置页（布局驱动：默认合集=音频）
      await tester.tap(find.text('设置'));
      await settle(tester);
      expect(find.text('音频'), findsWidgets);
      expect(find.text('音量'), findsWidgets); // 音频合集下的「音量」组
    });
  });
}

/// 通知中心媒体卡标题来自 Terms.nowPlaying（当前播放），避免硬编码重复。
const String termsNowPlaying = '当前播放';

/// 命名词典「音源」实体文案（Terms.source）。
const String termsSource = '音源';

/// 整 App 集成用例统一使用的「宽松画布」。
///
/// 默认测试画布是 800×600，扣掉标题栏 + 搜索栏 + 底部 MiniPlayer/Dock 后，
/// 页面正文只剩 ~187dp 高：设置页左侧竖栏被迫滚动，目标 tile 落在 Viewport
/// 之外（painted 位置仍可算出，但 hitTest 被 Viewport 边界拒绝），
/// 表现为「would not hit test」。集成用例关注的是内容与交互契约，
/// 不是极小窗口的滚动行为，故统一放到 1000×1400 的常规平板尺寸。
void useRoomySurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 固定帧 pump（替代 pumpAndSettle）：
/// AppShell 用 IndexedStack 保活 5 页（v1 契约），场景页等含常驻动画，
/// pumpAndSettle 永不收敛。这里只推进有限帧完成路由过渡即可。
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 循环 pump 直到 finder 命中（上限 50 帧，每帧 100ms 假时间）。
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (int i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets, reason: '等待目标出现超时');
}
