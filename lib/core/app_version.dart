/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 版本规范（R18/R19/R20）
/// ════════════════════════════════════════════════════════════════════════
///
/// 规则（用户 2026-08-09 定版）：
///   `0.26.8.9_alpha_cl01`
///    └┬─┘└┬┘└┬┘└┬┘ └┬┘ └┬┘
///    大版本 年 月 日 阶段 构建次数
///
///  - 大版本：0（早期）
///  - 年/月/日：当日日期（YY.MM.DD）
///  - 阶段：alpha = 阿尔法/早期内测；beta = 内测；rc = 候选；release = 正式
///  - clNN：当日构建次数（01 起，同日每次构建 +1）
///  - 版本代号 [codename]：发版命名（如「星辉」），未定稿为「待定」
///
/// pubspec 的 `version` 字段仍是合法语义版本 `0.YY.MM+DD`，
/// 展示串由本文件统一生成，设置页「关于」展示完整串。
library;

/// 版本阶段。
enum AppStage {
  alpha('alpha', '阿尔法（早期内测）'),
  beta('beta', '贝塔（内测）'),
  rc('rc', '候选发布'),
  release('release', '正式版');

  const AppStage(this.tag, this.label);
  final String tag;
  final String label;
}

/// 版本信息（编译期常量，发版时手动维护）。
abstract final class AppVersion {
  // ── 编辑时手动维护（每次发版更新）──────────────
  // 版本代号演进表（用户 2026-08-11 定版；随阶段推进逐级升级，
  // 只需改 [codename] 一处）：
  //   星尘初聚 —— 星尘开始凝聚，尚未成型
  //   星轨初现 —— 轨迹逐渐清晰，方向显现
  //   星河流转 —— 星河开始流动，状态稳定
  //   星光满照 —— 星光充盈，感知生效
  //   星河静默 —— 星河流动放缓，不再扩展
  //   星尘余响 —— 星尘散去，余响犹在
  // 展示格式：星璃音乐·<代号>

  /// 大版本。
  static const int major = 0;

  /// 年份（两位）。
  static const int year = 26;

  /// 月份。
  static const int month = 8;

  /// 日期。
  /// R26r21：过 00:00 进下一天（按真实日期推进）；次日 cl 清零。
  static const int day = 14;

  /// 阶段。
  static const AppStage stage = AppStage.alpha;

  /// 当日构建次数（01 起；同日每次构建 +1，发版时手动递增，次日清零）。
  /// cl36：安卓切歌防闪退补丁 + 通知系统重做(rootOverlay/多实例堆叠) +
  /// 水面默认关闭(高画质外) + 游戏中返回键(提醒/双击保存退出) +
  /// 存档最近保存时间 + 崩溃界面兜底(ErrorWidget.builder→CrashScreen)。
  /// cl37：生存模式 bug 修复——新建/读档作弊关强制生存(禁创造)、
  /// 饥饿衰减提速至分钟级、进生存保留存档数值(不再 respawn 覆盖)、
  /// 新建存档作弊/浮空岛默认关。
  /// cl38：开放世界地基 P0+P1——编辑层坐标从打包 key(x*65536+z*256+y，
  /// z 锁 0-255/x±32767) 改为 chunk 分桶(cx,cz)+局部编码(任意坐标/负坐标/
  /// 大范围生效，序列化 schema:2、旧档安全跳过)；玩家生存状态抽离为
  /// playerVitalsProvider 单例真相源(Riverpod)，跨系统共享、避免双重 dispose。
  /// cl39：安卓运行时 4 连崩修复——①播放易卡死（占位符解析无超时→加 20s
  /// 超时，loading 不再无限期挂起）；②歌名/曲名对不上（选曲即写 nowPlaying
  /// 与引擎加载成功才写双真源错位→新增 currentTrackProvider+nowPlayingBridge
  /// 桥接统一到引擎真源）；③播网易云源崩溃（resolver 兜底 catch(_) 回落
  /// openPath 打开非法 URI 原生崩→改抛 StreamResolveException，并在 open 分支
  /// 加本地文件护栏，占位符失败绝不 openPath）；④进世界/进存档卡死崩溃
  /// （VoxelMusicEngine().init().then 缺 .catchError→未处理异步错误安卓原生
  /// 崩，与 WorldAudioEngine 路径对称加兜底；_enter 写盘无保护→加 try/catch）。
  /// cl40：安卓「仍卡死」真凶修复——全局播放/进世界 toast（global_notification_toast）
  /// 的 build() 返回 IgnorePointer(child: Positioned(...))，Positioned 被单子组件包裹，
  /// 父用基类 ParentData，强转 StackParentData 失败 → WidgetsBinding.drawFrame 持续抛
  /// _CastError → 主线程重建死循环 → 系统判 ANR（只能强关）；对调层级为
  /// Positioned(child: IgnorePointer(AnimatedBuilder(...))) 修复。另 release 资源压缩
  /// (shrinkResources) 把仅 Dart 引用的 drawable/ic_notification 剥除致通知栏崩溃，
  /// 新增 res/raw/keep.xml 强制保留。
  /// cl41：修复「播 1 秒后静音、须拖主音量条才恢复」。根因=切歌时 playMusic 在
  /// line 350 启动旧曲淡出（_fadeMusic 操作共享 _music 播放器、末步 setVolume(0)），
  /// 但新曲路径（line 369）直接 setVolume 不走 _fadeMusic，_fadeSeq 守卫从未被触发，
  /// 旧淡出在 ~1.5s 后台跑完把新曲音量压成 0。新增 _cancelFades() 在
  /// playMusic/续播/resume 直接 setVolume 前显式作废在途淡出修复。
  /// cl42：体素渲染/UX 大修（10 项用户反馈 #382-#391）。①LOD 默认开启
  /// （lodQualityProvider off→balanced，tiers 非空才采样减面）+ 裙边裂口修复
  /// （-0.5 死区→0.0 闭合微缝）；③④⑤云视距/太阳无极过渡+泛光/向下平行面剔除
  /// 复核；⑥背包物品改为居中 3×9 表格；⑦退出按钮移到背包/合成标签左侧；
  /// ⑧搜索+音质并入底部音乐卡片；⑨游戏内顶部居中液态玻璃播放器（删
  /// _WorldMusicConsole、封存纯色全屏 NowPlayingPage）；⑩音源搜索改弹出式
  /// 底部卡片（全局可调、无风险）。
  /// cl43：②描边视距严重不符根因修复——原硬编码 kEdgeMaxDepth=15.0 二值截断，
  /// 描边在 15 格一刀切、且不论视距 2/4/6/8 都纹丝不动（用户反馈「环绕自身 5 格
  /// 立方圆」）。改为随 camera.far*0.5 派生（夹 [16,72] 面数护栏）+ 末段 30%
  /// 距离 alpha 线性淡出，硬边界环变察觉不到的渐隐；⑨顶部播放器改为顶栏 Column
  /// 子项（防窄屏折行 chips 重叠，旧固定 top:92 同型坑）+ 清孤儿 import。
  static const int buildCount = 43;

  /// 版本代号（见上方演进表；当前阶段「星尘初聚」）。
  static const String codename = '星尘初聚';

  // ── 派生 ────────────────────────────────────────
  /// 语义版本（pubspec version 的展示版）：`0.26.8+11`。
  static String get semver => '$major.$year.$month+$day';

  /// 完整展示串：`0.26.8.11_alpha_cl01`。
  static String get display =>
      '$major.$_yy.$_mm.$_dd${_stageSuffix}_cl${buildCount.toString().padLeft(2, '0')}';

  /// 品牌式展示：`星璃音乐·星尘初聚`。
  static String get brand => '星璃音乐·$codename';

  /// 设置页/关于页短展示（无 cl）：`0.26.8.10_alpha`。
  static String get displayShort => '$major.$_yy.$_mm.$_dd$_stageSuffix';

  static String get _yy => year.toString().padLeft(2, '0');
  static String get _mm => month.toString().padLeft(2, '0');
  static String get _dd => day.toString().padLeft(2, '0');
  static String get _stageSuffix => stage == AppStage.release ? '' : '_${stage.tag}';
}
