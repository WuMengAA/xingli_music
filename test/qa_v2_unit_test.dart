import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/core/terms/naming_dict.dart';
import 'package:xingli_music/models/experiment.dart';
import 'package:xingli_music/models/library_folder.dart';
import 'package:xingli_music/models/notification_event.dart';
import 'package:xingli_music/models/scene.dart';
import 'package:xingli_music/models/source_health.dart';
import 'package:xingli_music/models/track.dart';
import 'package:xingli_music/models/voxel.dart';
import 'package:xingli_music/providers/explore/experiment_providers.dart';
import 'package:xingli_music/providers/library/library_view_providers.dart';
import 'package:xingli_music/providers/audio/source_health_providers.dart';
import 'package:xingli_music/providers/settings/notification_providers.dart';
import 'package:xingli_music/services/audio/eq_engine.dart';
import 'package:xingli_music/widgets/library/folder_view.dart';
import 'package:xingli_music/widgets/voxel/voxel_canvas_controller.dart';

void main() {
  group('M1 · 命名词典 Terms', () {
    test('8 个核心实体全部就位且为单一出处常量', () {
      expect(Terms.scene, '场景');
      expect(Terms.library, '曲库');
      expect(Terms.track, '歌曲');
      expect(Terms.album, '专辑');
      expect(Terms.folder, '目录');
      expect(Terms.source, '音源');
      expect(Terms.server, '服务器');
      expect(Terms.notificationCenter, '通知中心');
    });
  });

  group('M5 · Scene 模型 JSON 兼容（R-02）', () {
    test('旧数据（无 v2 新字段）反序列化不崩且取默认值', () {
      final Map<String, dynamic> oldJson = <String, dynamic>{
        'id': 'rain',
        'name': '雨',
        'mood': '宁静',
        'desc': '雨声场景',
        'track': '',
        'artist': '',
        'soundscape': '程序合成音景',
        'icon': 'star',
        'visual': <String, dynamic>{
          'gradientColors': <int>[0xFF1A1A2E, 0xFF16213E],
          'stops': <double>[0.2, 1.0],
          'accent': 0xFF7B9BFF,
          'glyph': '❖',
        },
        'visualWeight': 0.8,
        'valence': 0.5,
        'energy': 0.5,
      };
      final Scene s = Scene.fromJson(oldJson);
      expect(s.visible, isTrue, reason: '旧数据缺失 visible 应默认 true');
      expect(s.bgmUri, isNull);
      expect(s.bgmTitle, isNull);
      expect(s.bgmArtist, isNull);
      expect(s.id, 'rain');
      expect(s.visual.accent, const Color(0xFF7B9BFF));
    });

    test('新字段全量 JSON 往返一致', () {
      const Scene s = Scene(
        id: 'custom_1',
        name: '我的雪夜',
        mood: '清冷',
        desc: '自定义',
        track: '',
        artist: '',
        soundscape: '程序合成音景',
        icon: 'snowflake',
        visual: SceneVisual(
          gradientColors: <Color>[Color(0xFF1A1A2E), Color(0xFF2E2E3E)],
          stops: <double>[0.2, 1.0],
          accent: Color(0xFF7C6BFF),
          glyph: '❄',
        ),
        visualWeight: 0.8,
        valence: 0.6,
        energy: 0.4,
        visible: false,
        bgmUri: 'file:///tmp/bgm.mp3',
        bgmTitle: '雪落下的声音',
        bgmArtist: '示例歌手',
      );
      final Scene back = Scene.fromJson(s.toJson());
      expect(back.visible, isFalse);
      expect(back.bgmUri, 'file:///tmp/bgm.mp3');
      expect(back.bgmTitle, '雪落下的声音');
      expect(back.bgmArtist, '示例歌手');
      expect(back.visual.accent, const Color(0xFF7C6BFF));
      expect(back.visual.gradientColors.length, 2);
    });

    test('SceneVisual 缺省字段兜底', () {
      final SceneVisual v = SceneVisual.fromJson(<String, dynamic>{});
      expect(v.gradientColors, isEmpty);
      expect(v.accent, const Color(0xFF9B7BFF));
      expect(v.glyph, '✦');
    });
  });

  group('M2 · 实验同意持久化', () {
    test('ExperimentConsent JSON 往返', () {
      final ExperimentConsent c = ExperimentConsent.fromJson(<String, dynamic>{
        'agreed': true,
        'enabled': <String, dynamic>{'recommend': false},
      });
      expect(c.agreed, isTrue);
      expect(c.enabled['recommend'], isFalse);
      final ExperimentConsent back =
          ExperimentConsent.fromJson(c.toJson());
      expect(back.agreed, isTrue);
      expect(back.enabled['recommend'], isFalse);
    });

    test('ExperimentConsent 缺省 agreed=false；损坏数据经 Notifier 回退 initial', () async {
      expect(ExperimentConsent.fromJson(<String, dynamic>{}).agreed, isFalse);

      // 直接 fromJson 遇到类型损坏会抛异常；应用层 Notifier._load 捕获并回退
      SharedPreferences.setMockInitialValues(<String, Object>{
        'experiment_consent_v1':
            '{"agreed": "not-a-bool", "enabled": {"a": 1}}',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ExperimentConsentNotifier n = ExperimentConsentNotifier(prefs);
      expect(n.state.agreed, isFalse);
      expect(n.state.enabled, isEmpty);
    });

    test('isEnabled 回退 enabledByDefault', () {
      const ExperimentItem defaultOn = ExperimentItem(
        id: 'on',
        name: '',
        description: '',
        icon: Icons.star_rounded,
        status: ExperimentStatus.experimenting,
        builder: _emptyBuilder,
      );
      const ExperimentItem defaultOff = ExperimentItem(
        id: 'off',
        name: '',
        description: '',
        icon: Icons.star_rounded,
        status: ExperimentStatus.experimenting,
        enabledByDefault: false,
        builder: _emptyBuilder,
      );
      final ExperimentConsent c = ExperimentConsent.fromJson(<String, dynamic>{
        'agreed': true,
        'enabled': <String, dynamic>{'off': true},
      });
      expect(c.isEnabled(defaultOn), isTrue);
      expect(c.isEnabled(defaultOff), isTrue, reason: '显式配置优先于默认');
    });

    test('Notifier agree/revoke/setEnabled 持久化到 SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final ExperimentConsentNotifier n1 =
          ExperimentConsentNotifier(prefs);
      expect(n1.state.agreed, isFalse);

      await n1.agree();
      expect(n1.state.agreed, isTrue);

      await n1.setEnabled('recommend', false);
      expect(n1.state.enabled['recommend'], isFalse);

      // 重新构造（模拟重启）→ 从 prefs 加载
      final ExperimentConsentNotifier n2 =
          ExperimentConsentNotifier(prefs);
      expect(n2.state.agreed, isTrue);
      expect(n2.state.enabled['recommend'], isFalse);

      await n2.revoke();
      expect(n2.state.agreed, isFalse);
      expect(n2.state.enabled, isEmpty);

      final ExperimentConsentNotifier n3 =
          ExperimentConsentNotifier(prefs);
      expect(n3.state.agreed, isFalse);
    });
  });

  group('M3 · 曲库视图样式持久化', () {
    test('LibraryViewStyleNotifier 默认 card，setStyle 持久化并重新加载', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final LibraryViewStyleNotifier n1 = LibraryViewStyleNotifier(prefs);
      expect(n1.state, LibraryViewStyle.card);

      await n1.setStyle(LibraryViewStyle.album);
      expect(n1.state, LibraryViewStyle.album);

      final LibraryViewStyleNotifier n2 = LibraryViewStyleNotifier(prefs);
      expect(n2.state, LibraryViewStyle.album, reason: '重启后样式保持');
    });
  });

  group('M4 · 音源健康状态', () {
    test('SourceHealthNotifier 状态机 connecting→ok/failed', () {
      final SourceHealthNotifier n = SourceHealthNotifier();
      expect(n.healthOf('srv').status, SourceHealthStatus.unknown);

      n.startTest('srv');
      expect(n.healthOf('srv').status, SourceHealthStatus.connecting);
      expect(n.healthOf('srv').lastTestedAt, isNull);

      n.markOk('srv');
      expect(n.healthOf('srv').status, SourceHealthStatus.ok);
      expect(n.healthOf('srv').lastTestedAt, isNotNull);

      n.markFailed('srv', detail: '超时');
      expect(n.healthOf('srv').status, SourceHealthStatus.failed);
      expect(n.healthOf('srv').errorDetail, '超时');

      n.remove('srv');
      expect(n.healthOf('srv').status, SourceHealthStatus.unknown);
    });

    test('SourceHealth 文案', () {
      expect(const SourceHealth().statusLabel, '未测试');
      expect(const SourceHealth(status: SourceHealthStatus.ok).statusLabel, '正常');
      expect(const SourceHealth(status: SourceHealthStatus.failed).statusLabel, '失败');
      expect(const SourceHealth().lastTestedLabel, '--');
    });
  });

  group('M2-C · EQ 预设与引擎', () {
    test('7 组预设数值与 10 段结构一致', () {
      final Map<String, EqPreset> byId = <String, EqPreset>{
        for (final EqPreset p in kEqPresets) p.id: p,
      };
      // 每组预设都是 10 段
      for (final EqPreset p in kEqPresets) {
        expect(p.gains.length, kEqFrequencies.length);
      }
      // 平坦全 0
      expect(byId['flat']!.gains.every((double g) => g == 0), isTrue);
      // 低音增强：低频段为正、高频段为负
      expect(byId['bass']!.gainAt(0), greaterThan(0));
      expect(byId['bass']!.gainAt(1), greaterThan(0));
      expect(byId['bass']!.gainAt(9), lessThan(0));
      // 人声突出：中频段最大（1kHz 档 +4，R-EQ 收紧 ±6）
      expect(byId['vocal']!.gainAt(5), 4);
      // 高音清亮：高频段为正
      expect(byId['treble']!.gainAt(8), greaterThan(0));
      expect(byId['treble']!.gainAt(9), greaterThan(0));
      // R-EQ：所有预设增益都在 ±6dB 内（防削波震耳）
      for (final EqPreset p in kEqPresets) {
        for (final double g in p.gains) {
          expect(g, lessThanOrEqualTo(kEqMaxGain));
          expect(g, greaterThanOrEqualTo(kEqMinGain));
        }
      }
      // ≥6 组预设（R9）
      expect(kEqPresets.length, greaterThanOrEqualTo(6));
    });

    test('EqPreset JSON 往返 + 缺省兜底', () {
      const EqPreset p = EqPreset(
        id: 'bass',
        name: '低音增强',
        gains: <double>[6, 6, 5, 3, 1, 0, -1, -2, -2, -3],
      );
      final EqPreset back = EqPreset.fromJson(p.toJson());
      expect(back.gainAt(0), 6);
      expect(back.gainAt(9), -3);
      final EqPreset empty = EqPreset.fromJson(<String, dynamic>{});
      expect(empty.id, 'flat');
      expect(empty.name, '平坦');
      expect(empty.gains.length, kEqFrequencies.length);
    });

    test('模拟层 supported=false（桌面/非 Android 行为）', () {
      final SimulatedEqEngine engine = SimulatedEqEngine();
      expect(engine.supported, isFalse);
      expect(engine.unsupportedNote, contains('不支持真实 EQ'));
      // 模拟层无副作用，不应抛异常
      engine.applySimulation(kEqPresets.first);
    });
  });

  group('M5 · Voxel 模型与控制器', () {
    test('VoxelSoundScene JSON 往返 + 缺省兜底', () {
      const VoxelSoundScene s = VoxelSoundScene(
        id: 'voxel_1',
        name: '雨林',
        cols: 8,
        rows: 8,
        blocks: <String, String>{'3,5': 'rain', '1,2': 'wind'},
      );
      final VoxelSoundScene back = VoxelSoundScene.fromJson(s.toJson());
      expect(back.id, 'voxel_1');
      expect(back.blocks['3,5'], 'rain');

      final VoxelSoundScene fromMinimal =
          VoxelSoundScene.fromJson(<String, dynamic>{});
      expect(fromMinimal.cols, 8);
      expect(fromMinimal.rows, 8);
      expect(fromMinimal.blocks, isEmpty);

      final VoxelSoundScene decoded = VoxelSoundScene.decode(s.encode());
      expect(decoded.blocks.length, 2);
    });

    test('坐标 key 约定 "col,row"', () {
      expect(VoxelCanvasController.keyOf(3, 5), '3,5');
      expect(VoxelCanvasController.parseKey('3,5'), (3, 5));
      expect(VoxelCanvasController.parseKey('abc'), isNull);
      expect(VoxelCanvasController.parseKey('1,2,3'), isNull);
    });

    test('等距投影正变换/逆变换一致（架构 §3.2.3）', () {
      const double tileW = 46;
      const double tileH = 28;
      const double offsetX = 200;
      const double offsetY = 100;
      // 对每个网格中心点验证逆变换能还原 (col,row)
      for (int col = 0; col < 8; col++) {
        for (int row = 0; row < 8; row++) {
          final double sx = (col - row) * tileW / 2 + offsetX;
          final double sy = (col + row) * tileH / 2 + offsetY;
          // 逆变换（与 VoxelCanvasView._hitTest 同公式）
          final double u = (sx - offsetX) / (tileW / 2);
          final double v = (sy - offsetY) / (tileH / 2);
          final int c = ((u + v) / 2).floor();
          final int r = ((v - u) / 2).floor();
          expect(c, col, reason: '($col,$row) 逆变换 col');
          expect(r, row, reason: '($col,$row) 逆变换 row');
        }
      }
    });

    test('VoxelCanvasController 放置/删除/切换', () {
      final VoxelCanvasController c = VoxelCanvasController(cols: 8, rows: 8);
      c.setBlock(3, 5);
      expect(c.blocks['3,5'], 'rain', reason: '默认选中第一个类型 rain');

      c.toggleBlock(3, 5); // 已存在 → 删除
      expect(c.blocks.containsKey('3,5'), isFalse);

      c.toggleBlock(0, 0); // 不存在 → 放置
      expect(c.blocks['0,0'], 'rain');

      c.setBlock(-1, -1); // 越界 no-op
      expect(c.blocks.length, 1);
      expect(c.inBounds(7, 7), isTrue);
      expect(c.inBounds(8, 0), isFalse);
    });

    test('VoxelCanvasController undo/redo/clear', () {
      final VoxelCanvasController c = VoxelCanvasController(cols: 8, rows: 8);
      expect(c.canUndo, isFalse);
      c.setBlock(1, 1);
      c.setBlock(2, 2);
      expect(c.blocks.length, 2);

      c.undo();
      expect(c.blocks.length, 1);
      expect(c.blocks.containsKey('1,1'), isTrue, reason: '撤销的是最后一步 2,2');
      expect(c.canUndo, isTrue);
      expect(c.canRedo, isTrue);

      c.redo();
      expect(c.blocks.length, 2);

      c.clear();
      expect(c.blocks, isEmpty);
      expect(c.canUndo, isTrue, reason: 'clear 也可撤销');
    });

    test('VoxelCanvasController load/toScene/countByType/allCells', () {
      final VoxelCanvasController c = VoxelCanvasController(cols: 8, rows: 8);
      const VoxelSoundScene s = VoxelSoundScene(
        id: 'v1',
        name: 's',
        cols: 8,
        rows: 8,
        blocks: <String, String>{'0,0': 'rain', '1,1': 'rain', '2,2': 'wind'},
      );
      c.load(s);
      expect(c.blocks.length, 3);
      final Map<String, int> counts = c.countByType();
      expect(counts['rain'], 2);
      expect(counts['wind'], 1);
      expect(c.allCells(), contains((0, 0)));
      expect(c.allCells(), contains((2, 2)));

      final VoxelSoundScene out = c.toScene('x', 'y');
      expect(out.id, 'x');
      expect(out.cols, 8);
      expect(out.blocks.length, 3);
    });

    test('音效块预设库非空且 id 唯一', () {
      expect(kVoxelBlockTypes, isNotEmpty);
      final Set<String> ids = kVoxelBlockTypes.map((VoxelBlockType t) => t.id).toSet();
      expect(ids.length, kVoxelBlockTypes.length);
      expect(voxelBlockTypeById('rain').id, 'rain');
      expect(voxelBlockTypeById('unknown').id, kVoxelBlockTypes.first.id);
    });
  });

  group('M6 · 通知事件日志', () {
    test('NotificationLogNotifier append/clear/上限 50', () {
      final NotificationLogNotifier n = NotificationLogNotifier();
      expect(n.state, isEmpty);
      n.append('播放', '歌名 · 歌手');
      expect(n.state.length, 1);
      expect(n.state.first.title, '播放');
      expect(n.state.first.message, '歌名 · 歌手');
      expect(n.state.first.timeLabel, isNotEmpty);

      for (int i = 0; i < 60; i++) {
        n.append('场景', '切换');
      }
      expect(n.state.length, 50, reason: '内存态日志上限 50');
      n.clear();
      expect(n.state, isEmpty);
    });

    test('NotificationEvent 字段完整', () {
      final NotificationEvent e = NotificationEvent(
        id: '1',
        title: 't',
        message: 'm',
        at: DateTime(2026, 8, 9, 12, 3, 0),
      );
      expect(e.timeLabel, '12:03:00');
    });
  });

  group('M3 · 文件夹目录树派生', () {
    test('本地路径按层级建树且 trackCount 递归', () {
      final List<Track> tracks = <Track>[
        const Track(
          title: 'a',
          artist: 'x',
          uri: 'd:/Music/Album1/song1.mp3',
          source: TrackSource.local,
        ),
        const Track(
          title: 'b',
          artist: 'x',
          uri: 'd:/Music/Album1/song2.mp3',
          source: TrackSource.local,
        ),
        const Track(
          title: 'c',
          artist: 'y',
          uri: 'd:/Music/Album2/song3.mp3',
          source: TrackSource.local,
        ),
      ];
      final LibraryFolderNode root = buildFolderTree(tracks);
      expect(root.trackCount, 3);
      expect(root.children.length, 1, reason: '盘符被剥离，Music 为一级目录');
      final LibraryFolderNode music = root.children.first;
      expect(music.name, 'Music');
      expect(music.children.length, 2);
      final LibraryFolderNode album1 = music.children.first;
      expect(album1.tracks.length, 2);
    });

    test('在线曲目归入「音源」虚拟目录', () {
      final List<Track> tracks = <Track>[
        const Track(
          title: 'radio',
          artist: 'x',
          uri: 'http://radio.example/live',
          source: TrackSource.stream,
          sourceId: 'myradio',
        ),
      ];
      final LibraryFolderNode root = buildFolderTree(tracks);
      final LibraryFolderNode sources = root.children.first;
      expect(sources.name, Terms.source);
      expect(sources.children.first.name, 'myradio');
      expect(root.trackCount, 1);
    });
  });
}

Widget _emptyBuilder() => const SizedBox.shrink();
