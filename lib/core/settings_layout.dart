/// ════════════════════════════════════════════════════════════════════════
/// 设置布局数据模型（可拖拽自定义 · 随包分发）
/// ════════════════════════════════════════════════════════════════════════
///
/// 用户痛点：设置布局若只存设备 prefs 无法跨设备传播；作为开发者需要
/// **图形化自定义**并**固化进包**。方案：
///   - 布局 = `collection → group → item` 三层数据（本文件模型 + 默认布局）。
///   - 默认布局常量 = 代码内嵌（随版本分发，所有用户一致）。
///   - 图形化编辑器（settings_organizer_page）可拖拽排布、新建分类/组，
///     导出为 JSON 资产 `assets/settings_layout.json` 覆盖默认 → 重新构建即
///     随包分发（解决「无法通用传播」）。
///   - 运行时：有资产 JSON 用资产，否则用代码内嵌默认布局。
library;

import 'dart:convert';

/// 设置项种类（决定渲染控件）。
enum SettingKind {
  /// 跳转子页（入口行）。
  entry,

  /// 滑块（音量类）。
  slider,

  /// 单选 chips（模式类）。
  chips,

  /// 开关（布尔类）。
  toggle,

  /// 组合块（一组控件，如特效开关组 / 折叠音量）。
  block,
}

/// 一个可拖拽的设置项（注册表条目）。
class SettingItem {
  const SettingItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.kind = SettingKind.entry,
  });

  /// 唯一标识（注册表 / 布局引用用）。
  final String id;

  final String title;

  /// 描述（编辑器里显示）。
  final String subtitle;

  final SettingKind kind;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'kind': kind.name,
      };

  static SettingItem fromJson(Map<String, dynamic> j) => SettingItem(
        id: j['id'] as String,
        title: j['title'] as String? ?? j['id'] as String,
        subtitle: j['subtitle'] as String? ?? '',
        kind: SettingKind.values.firstWhere(
          (SettingKind k) => k.name == j['kind'],
          orElse: () => SettingKind.entry,
        ),
      );
}

/// 组（中间层）：一组设置项，可命名、可拖拽排序。
class SettingGroup {
  const SettingGroup({required this.id, required this.name, this.items = const <SettingItem>[]});

  final String id;
  final String name;
  final List<SettingItem> items;

  SettingGroup copyWith({String? name, List<SettingItem>? items}) =>
      SettingGroup(id: id, name: name ?? this.name, items: items ?? this.items);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'items': <Map<String, dynamic>>[for (final SettingItem i in items) i.toJson()],
      };

  static SettingGroup fromJson(Map<String, dynamic> j) => SettingGroup(
        id: j['id'] as String,
        name: j['name'] as String? ?? '未命名组',
        items: <SettingItem>[
          for (final dynamic i in (j['items'] as List<dynamic>? ?? <dynamic>[]))
            SettingItem.fromJson(i as Map<String, dynamic>),
        ],
      );
}

/// 合集（最高层）：「画面」「机制」「音频」等。
class SettingCollection {
  const SettingCollection({
    required this.id,
    required this.name,
    this.groups = const <SettingGroup>[],
  });

  final String id;
  final String name;
  final List<SettingGroup> groups;

  SettingCollection copyWith({String? name, List<SettingGroup>? groups}) =>
      SettingCollection(
          id: id, name: name ?? this.name, groups: groups ?? this.groups);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'groups': <Map<String, dynamic>>[for (final SettingGroup g in groups) g.toJson()],
      };

  static SettingCollection fromJson(Map<String, dynamic> j) => SettingCollection(
        id: j['id'] as String,
        name: j['name'] as String? ?? '未命名合集',
        groups: <SettingGroup>[
          for (final dynamic g in (j['groups'] as List<dynamic>? ?? <dynamic>[]))
            SettingGroup.fromJson(g as Map<String, dynamic>),
        ],
      );
}

/// 完整设置布局。
class SettingsLayout {
  const SettingsLayout({this.collections = const <SettingCollection>[]});

  final List<SettingCollection> collections;

  /// 全部设置项（跨合集拍平，供注册表/编辑器可用项池用）。
  List<SettingItem> get allItems => <SettingItem>[
        for (final SettingCollection c in collections)
          for (final SettingGroup g in c.groups)
            for (final SettingItem i in g.items) i,
      ];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'collections': <Map<String, dynamic>>[
          for (final SettingCollection c in collections) c.toJson(),
        ],
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static SettingsLayout fromJson(Map<String, dynamic> j) => SettingsLayout(
        collections: <SettingCollection>[
          for (final dynamic c in (j['collections'] as List<dynamic>? ?? <dynamic>[]))
            SettingCollection.fromJson(c as Map<String, dynamic>),
        ],
      );
}

/// 默认布局（代码内嵌，随版本分发）。
///
/// 按用户要求「画面是画面、机制是机制」：游戏机制类（玩法/世界生成/性能）
/// 独立成合集，不再混进「画面」。
const SettingsLayout kDefaultSettingsLayout = SettingsLayout(
  collections: <SettingCollection>[
    SettingCollection(
      id: 'audio',
      name: '音频',
      groups: <SettingGroup>[
        SettingGroup(
          id: 'audio_main',
          name: '音量',
          items: <SettingItem>[
            SettingItem(id: 'masterVolume', title: '主音量', kind: SettingKind.slider),
            SettingItem(id: 'otherVolumes', title: '其他音量', kind: SettingKind.block),
            SettingItem(id: 'balanceMode', title: '音量均衡', kind: SettingKind.chips),
            SettingItem(id: 'equalizer', title: '均衡器（10 段）'),
          ],
        ),
        SettingGroup(
          id: 'audio_mine',
          name: '我的音乐',
          items: <SettingItem>[
            // cl46：全局收藏 + 自定义歌单（名称 / 相册背景图 / 排序）。
            SettingItem(id: 'favoritesPlaylists', title: '收藏与歌单'),
            // cl46：听歌排行（播放次数 / 收听时长）。
            SettingItem(id: 'topList', title: '听歌排行'),
            // cl46：自动播放 / 自动过渡（默认开）。
            SettingItem(id: 'autoPlay', title: '自动播放', kind: SettingKind.toggle),
            SettingItem(id: 'autoTransition', title: '自动过渡', kind: SettingKind.toggle),
          ],
        ),
        SettingGroup(
          id: 'audio_source',
          name: '音源',
          items: <SettingItem>[
            SettingItem(id: 'serverSource', title: '服务器与音源'),
            SettingItem(id: 'netease', title: '网易云登录'),
            // R26skel-b3：B站视频源（登录 + 自动匹配当前曲目播放）。
            SettingItem(id: 'bilibili', title: '哔哩哔哩视频源'),
            // R26skel-b6：音乐源音质/清晰度（VIP/大会员自动识别）。
            SettingItem(id: 'musicQuality', title: '网易云音质', kind: SettingKind.chips),
            SettingItem(id: 'biliQuality', title: 'B站清晰度', kind: SettingKind.chips),
          ],
        ),
        SettingGroup(
          id: 'audio_engine',
          name: '播放引擎',
          items: <SettingItem>[
            SettingItem(id: 'musicEngine', title: '播放引擎', kind: SettingKind.chips),
          ],
        ),
      ],
    ),
    // cl46：凡游戏画面、机制统统迁入「游戏」分类。
    SettingCollection(
      id: 'game',
      name: '游戏',
      groups: <SettingGroup>[
        SettingGroup(
          id: 'game_quick',
          name: '游戏设置',
          items: <SettingItem>[
            SettingItem(id: 'whiteNoise', title: '白噪音', kind: SettingKind.toggle),
            SettingItem(id: 'worldAudio', title: '世界音效', kind: SettingKind.toggle),
            SettingItem(id: 'hudEdit', title: '布局编辑', kind: SettingKind.toggle),
            // R26skel-b3：游戏 UI 大小（HUD 摇杆/动作键缩放）。
            SettingItem(id: 'hudScale', title: '游戏 UI 大小', kind: SettingKind.slider),
          ],
        ),
        // 画质：低中高预设（卡片预览选择）+ 分辨率 + 帧率 + 阴影。
        SettingGroup(
          id: 'game_quality',
          name: '画质',
          items: <SettingItem>[
            SettingItem(id: 'perfPreset', title: '画质预设（低 / 中 / 高）'),
            SettingItem(id: 'renderResolution', title: '分辨率', kind: SettingKind.chips),
            SettingItem(id: 'fpsLimit', title: '帧率', kind: SettingKind.chips),
            SettingItem(id: 'shadowRender', title: '阴影（真阴影）', kind: SettingKind.toggle),
            SettingItem(id: 'gameGraphics', title: '游戏画面 · 高级设置'),
          ],
        ),
        // 渲染 · 高级（迁移自「个性 · 画面高级」）。
        SettingGroup(
          id: 'game_render_advanced',
          name: '渲染 · 高级',
          items: <SettingItem>[
            SettingItem(id: 'viewDistance', title: '视距', kind: SettingKind.slider),
            SettingItem(id: 'renderPrecisionScale', title: '渲染精度', kind: SettingKind.slider),
            SettingItem(id: 'lodEnabled', title: 'LOD 开关', kind: SettingKind.toggle),
            SettingItem(id: 'lodStart', title: 'LOD 起始', kind: SettingKind.slider),
            SettingItem(id: 'lodStepBlocks', title: 'LOD 步长（格）', kind: SettingKind.chips),
            SettingItem(id: 'lodSample', title: 'LOD 采样（大方块）', kind: SettingKind.chips),
            SettingItem(id: 'lodMaxChunks', title: 'LOD 最远距离', kind: SettingKind.slider),
            SettingItem(id: 'outlineToggle', title: '方块描边', kind: SettingKind.toggle),
            SettingItem(id: 'boundaryFog', title: '边界雾', kind: SettingKind.toggle),
            SettingItem(id: 'renderPrecision', title: '几何精度（面数）', kind: SettingKind.chips),
            SettingItem(id: 'faceCull', title: '侧面剔除', kind: SettingKind.toggle),
            SettingItem(id: 'occlusionCull', title: '遮挡剔除', kind: SettingKind.toggle),
            SettingItem(id: 'backFaceCull', title: '背面剔除', kind: SettingKind.toggle),
            SettingItem(id: 'frustumCull', title: '视锥剔除', kind: SettingKind.toggle),
            SettingItem(id: 'underwaterFilter', title: '水下滤镜', kind: SettingKind.toggle),
            SettingItem(id: 'flashlight', title: '手电筒模式', kind: SettingKind.toggle),
            SettingItem(id: 'waterFlow', title: '水流动', kind: SettingKind.toggle),
            SettingItem(id: 'aoRender', title: '环境光屏蔽（AO）', kind: SettingKind.toggle),
          ],
        ),
        // 机制：存档机制 / 世界机制 / 自定义世界机制。
        SettingGroup(
          id: 'game_mechanics',
          name: '机制',
          items: <SettingItem>[
            SettingItem(id: 'autoBackup', title: '后台自动备份'),
            SettingItem(id: 'backupInterval', title: '备份间隔', kind: SettingKind.chips),
            SettingItem(id: 'worldSave', title: '世界存档'),
            SettingItem(id: 'worldSfx', title: '世界音效设置'),
            SettingItem(id: 'worldGen', title: '自定义世界机制'),
          ],
        ),
      ],
    ),
    SettingCollection(
      id: 'visual',
      // cl45：用户要求「画面」改名「个性」。
      name: '个性',
      groups: <SettingGroup>[
        SettingGroup(
          id: 'visual_appearance',
          name: '外观',
          items: <SettingItem>[
            SettingItem(id: 'themeMode', title: '主题模式', kind: SettingKind.chips),
            SettingItem(id: 'themeSkin', title: '皮肤', kind: SettingKind.chips),
            SettingItem(id: 'uiDensity', title: '界面密度', kind: SettingKind.chips),
            // R26skel-b3：全局 UI 大小（整体界面缩放）。
            SettingItem(id: 'uiScale', title: '全局 UI 大小', kind: SettingKind.slider),
          ],
        ),
        SettingGroup(
          id: 'visual_scene',
          name: '场景',
          items: <SettingItem>[
            SettingItem(id: 'sceneEditor', title: '场景编辑器'),
            SettingItem(id: 'customSceneList', title: '自定义场景管理'),
            // cl50：场景卡片背景透明度（0.1~0.9，默认 0.25），用户可自调。
            SettingItem(id: 'sceneCardOpacity', title: '场景卡片透明度', kind: SettingKind.slider),
          ],
        ),
        // R26skel-b4：场景背景画质（独立于游戏画质）。
        SettingGroup(
          id: 'visual_scene_bg',
          name: '场景背景',
          items: <SettingItem>[
            SettingItem(id: 'sceneBgQuality', title: '场景背景画质', kind: SettingKind.chips),
            SettingItem(id: 'sceneBgFps', title: '场景背景帧率', kind: SettingKind.chips),
            SettingItem(id: 'sceneBgFog', title: '雾', kind: SettingKind.toggle),
            SettingItem(id: 'sceneBgWater', title: '水波动画', kind: SettingKind.toggle),
            SettingItem(id: 'sceneBgSky', title: '天空渐变', kind: SettingKind.toggle),
            SettingItem(id: 'sceneBgAnim', title: '动画', kind: SettingKind.toggle),
          ],
        ),
        // cl53-F2：把误排在「游戏 · 渲染高级」里的**全局个性**迁回本合集
        // （图形后端 / 噪点 / 玻璃模糊 / 背景动画 / 液态玻璃 / 全局画面预设），
        // 它们影响的是整个 App 的界面质感，不属于游戏预设。
        SettingGroup(
          id: 'visual_fx',
          name: '画面特效',
          items: <SettingItem>[
            SettingItem(id: 'picturePreset', title: '全局画面预设'),
            SettingItem(id: 'engineBackend', title: '图形后端', kind: SettingKind.chips),
            SettingItem(id: 'fxNoise', title: '噪点纹理', kind: SettingKind.toggle),
            SettingItem(id: 'fxBlur', title: '玻璃模糊', kind: SettingKind.toggle),
            SettingItem(id: 'fxBg', title: '背景动画', kind: SettingKind.toggle),
            SettingItem(id: 'fxLiquid', title: '液态玻璃（折射）', kind: SettingKind.toggle),
          ],
        ),
      ],
    ),
    // cl45：原「机制」合集已并入「游戏 · 世界与玩法」（见 game_mechanics 组）。
    SettingCollection(
      id: 'notification',
      name: '通知',
      groups: <SettingGroup>[
        SettingGroup(
          id: 'notification_main',
          name: '通知中心',
          items: <SettingItem>[
            SettingItem(id: 'permissions', title: '权限与授权'),
            SettingItem(id: 'notificationCenter', title: '通知中心', kind: SettingKind.block),
          ],
        ),
      ],
    ),
    SettingCollection(
      id: 'experiment',
      name: '实验',
      groups: <SettingGroup>[
        SettingGroup(
          id: 'experiment_main',
          name: '实验管理',
          items: <SettingItem>[
            SettingItem(id: 'llmSettings', title: '大模型设置'),
            SettingItem(id: 'consentStatus', title: '同意状态', kind: SettingKind.block),
            SettingItem(id: 'experimentToggles', title: '逐项启停', kind: SettingKind.block),
          ],
        ),
      ],
    ),
    SettingCollection(
      id: 'about',
      name: '关于',
      groups: <SettingGroup>[
        SettingGroup(
          id: 'about_main',
          name: '关于',
          items: <SettingItem>[
            SettingItem(id: 'aboutInfo', title: '应用信息', kind: SettingKind.block),
            // cl54-G6：存储占用（软件占用空间统计）。
            SettingItem(id: 'storageUsage', title: '存储'),
            // cl55：版本日志（自动获取最新）+ 版本更新（OTA 入口）。
            SettingItem(id: 'versionLog', title: '版本日志'),
            SettingItem(id: 'versionUpdate', title: '版本更新'),
            SettingItem(id: 'logUpload', title: '日志上报'),
          ],
        ),
        SettingGroup(
          id: 'about_devtools',
          name: '开发者工具',
          items: <SettingItem>[
            SettingItem(id: 'uiTemplateGallery', title: 'UI 模板库'),
            SettingItem(id: 'uiEditor', title: 'UI 编辑器'),
          ],
        ),
      ],
    ),
  ],
);
