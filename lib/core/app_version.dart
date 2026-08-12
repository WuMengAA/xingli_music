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
  static const int day = 12;

  /// 阶段。
  static const AppStage stage = AppStage.alpha;

  /// 当日构建次数（01 起；同日每次构建 +1，发版时手动递增）。
  static const int buildCount = 9;

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
