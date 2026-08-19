/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐空间 · 实体命名词典（v2 M1 · P0-M1-2 单一出处）
/// ════════════════════════════════════════════════════════════════════════
///
/// 依据 `docs/PRD_V2_增量.md` P0-M1-2 与 `docs/ARCHITECTURE_V2_增量.md` §7.1：
/// 页面文案不得硬编码实体名词；「服务器 vs 音源」「设置 vs 设定」一律以
/// 本词典为准。**全局唯一引用**，新增实体先补此处。
library;

/// 命名词典：8 个核心实体 + 常用动词。
///
/// `abstract final class` 禁止实例化，全部 `static const` 编译期常量，
/// 零运行时开销。新 UI 一律 `Terms.*` 引用。
abstract final class Terms {
  // ── 8 个核心实体 ─────────────────────────────────────────
  /// 场景（ScenePage / 场景编辑器 / 场景包）。
  static const String scene = '场景';

  /// 曲库（聚合全部已启用音源后的歌曲集合）。
  static const String library = '曲库';

  /// 歌曲（单曲）。
  static const String track = '歌曲';

  /// 专辑（按 `Track.album` 聚合）。
  static const String album = '专辑';

  /// 目录（本地文件夹层级，曲库「文件夹」视图）。
  static const String folder = '目录';

  /// 音源（本地目录 / 服务器 / 电台的上位概念）。
  static const String source = '音源';

  /// 服务器（自建 Subsonic 服务器）。
  static const String server = '服务器';

  /// 通知中心（三合一：运行状态 / 媒体控制 / 场景状态）。
  static const String notificationCenter = '通知中心';

  // ── 延伸命名空间（世界 / 画布 / 播放，避免各页自行拼写「我的世界」等）──
  /// 星璃世界（底部 Dock「世界」Tab 入口；原误用《我的世界》商标，统一更名）。
  static const String world = '星璃世界';

  /// 体素世界（3D 开放世界本体）。
  static const String voxelWorld = '体素世界';

  /// 2.5D 音效画布（场景音效可视化编辑界面）。
  static const String canvas = '2.5D 音效画布';

  /// 正在播放（整页播放器标题）。
  static const String playing = '正在播放';

  /// 存档（名词；区别于动词 [save]）。
  static const String manualSave = '存档';

  // ── 常用动词 / 短语（避免各页自行拼写）───────────────────
  /// 添加（音源 / 场景等）。
  static const String add = '添加';

  /// 编辑。
  static const String edit = '编辑';

  /// 删除。
  static const String delete = '删除';

  /// 保存。
  static const String save = '保存';

  /// 取消。
  static const String cancel = '取消';

  /// 搜索。
  static const String search = '搜索';

  /// 测试连接。
  static const String testConnection = '测试连接';

  /// 启用 / 停用（开关动词）。
  static const String enable = '启用';
  static const String disable = '停用';

  /// 播放。
  static const String play = '播放';

  /// 暂停。
  static const String pause = '暂停';

  /// 当前播放。
  static const String nowPlaying = '当前播放';

  /// 实验（探索实验室）。
  static const String experiment = '实验';
}
