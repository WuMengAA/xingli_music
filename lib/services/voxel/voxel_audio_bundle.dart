/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 · 内置音频素材槽定义（30 首主题乐 + 动作音效）
/// ════════════════════════════════════════════════════════════════════════
///
/// 与 [world_audio_engine]（环境空间音效：水/叶/鸟/风）互补：
/// - 本文件只定义**槽位与命名约定**，不加载任何音频；
/// - [voxel_music_engine] 负责背景音乐轮换；
/// - [voxel_action_sfx_engine] 负责玩家动作音效。
///
/// 版权：Minecraft 原声为 Mojang/微软版权资产，工程不内置、不分发。
/// 用户把自己的合法音频按约定命名放入目录即可生效；缺失文件 = 安全 no-op。
library;

/// 背景音乐槽位数（30 首主题音乐）。
const int kVoxelMusicSlotCount = 30;

/// 背景音乐资源目录（曲目命名 `track_01.m4a` … `track_30.m4a`）。
const String kVoxelMusicDir = 'assets/voxel_audio/music';

/// 动作音效资源目录（见 [kVoxelSfxFiles]）。
const String kVoxelSfxDir = 'assets/voxel_audio/sfx';

/// 体素世界玩家动作触发的音效类型。
enum VoxelActionSfx {
  /// 行走脚步。
  step,

  /// 放置方块。
  place,

  /// 破坏方块。
  breakBlock,

  /// 攻击 / 受击。
  hit,

  /// 起跳。
  jump,

  /// 落地。
  land,

  /// 跌落受伤。
  fall,

  /// 入水。
  splash,

  /// 门。
  door,

  /// 箱子。
  chest,

  /// 进食。
  eat,

  /// 出水换气。
  breath,
}

/// 动作 → 素材文件名（缺失文件 = 安全 no-op）。
const Map<VoxelActionSfx, String> kVoxelSfxFiles = <VoxelActionSfx, String>{
  VoxelActionSfx.step: '$kVoxelSfxDir/step.m4a',
  VoxelActionSfx.place: '$kVoxelSfxDir/place.m4a',
  VoxelActionSfx.breakBlock: '$kVoxelSfxDir/break.m4a',
  VoxelActionSfx.hit: '$kVoxelSfxDir/hit.m4a',
  VoxelActionSfx.jump: '$kVoxelSfxDir/jump.m4a',
  VoxelActionSfx.land: '$kVoxelSfxDir/land.m4a',
  VoxelActionSfx.fall: '$kVoxelSfxDir/fall.m4a',
  VoxelActionSfx.splash: '$kVoxelSfxDir/splash.m4a',
  VoxelActionSfx.door: '$kVoxelSfxDir/door.m4a',
  VoxelActionSfx.chest: '$kVoxelSfxDir/chest.m4a',
  VoxelActionSfx.eat: '$kVoxelSfxDir/eat.m4a',
  VoxelActionSfx.breath: '$kVoxelSfxDir/breath.m4a',
};

/// 30 首背景音乐预期清单（仅作文档；文件按 `track_01` … `track_30` 命名）。
const List<String> kVoxelMusicManifest = <String>[
  'track_01', 'track_02', 'track_03', 'track_04', 'track_05',
  'track_06', 'track_07', 'track_08', 'track_09', 'track_10',
  'track_11', 'track_12', 'track_13', 'track_14', 'track_15',
  'track_16', 'track_17', 'track_18', 'track_19', 'track_20',
  'track_21', 'track_22', 'track_23', 'track_24', 'track_25',
  'track_26', 'track_27', 'track_28', 'track_29', 'track_30',
];
