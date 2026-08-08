/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐空间 · 浅色扁平化设计系统 Token
/// ════════════════════════════════════════════════════════════════════════
///
/// 依据：`docs/PRD_UI_重构.md` §6「配色方案 Token 定义」与 §4.2「组件级映射」。
/// 全部为**编译期常量**（`static const`），不依赖任何运行时 HSL 派生
/// （对应需求 P0-A1）。
///
/// ### 强制约定 C1
/// 除 `lib/core/theme/` 目录、暗色画布孤岛资产（CanvasPage / PalettePanel /
/// Orb / ControlBar / MorePanel 等）与场景数据默认值（`Scene.bgTop` 一类）之外，
/// 业务代码**禁止**直接书写 `Color(0x...)` 字面量，一律从本文件取色。
///
/// ### 几何基准
/// 设计稿内屏 972×1818 px，缩放系数 **2.5**（dp = 设计 px ÷ 2.5），
/// 基准宽度 **390dp**。
library;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────
// 1. 语义色 Token —— PRD §6.2 中性色阶 + §6.3 语义色
// ─────────────────────────────────────────────────────────────────────────

/// 色板：**唯一取色入口**。
///
/// 分两层：
/// * **中性色阶** `neutral0` … `neutral400` —— 一条单调递减的「深度」体系；
/// * **语义别名** `bgPage` / `textPrimary` … —— 业务代码应优先使用语义名，
///   只有语义表未覆盖的边缘场景才直接引用色阶。
abstract final class AppColors {
  // ── 中性色阶（Neutral Ladder）· PRD §6.2 ─────────────────
  /// `#FFFFFF` 页面底色、卡片、迷你播放器胶囊。
  static const Color neutral0 = Color(0xFFFFFFFF);

  /// `#F5F5F5` 内容容器、控制按钮底（双源验证）。
  static const Color neutral50 = Color(0xFFF5F5F5);

  /// `#EEEEEE` 设置卡片。
  static const Color neutral100 = Color(0xFFEEEEEE);

  /// `#EAEAEA` 设置左分类栏、通用描边。
  static const Color neutral150 = Color(0xFFEAEAEA);

  /// `#E8E8E8` 搜索栏底（已裁决 Q3）。
  static const Color neutral200 = Color(0xFFE8E8E8);

  /// `#E7E7E7` 设置分类 tile。
  static const Color neutral250 = Color(0xFFE7E7E7);

  /// `#E6E6E6` Dock 容器底。
  static const Color neutral300 = Color(0xFFE6E6E6);

  /// `#D9D9D9` 占位图 / 骨架屏 / 进度条底轨。
  static const Color neutral400 = Color(0xFFD9D9D9);

  // ── 背景 / 表面 ──────────────────────────────────────────
  /// Scaffold 底色（全部 5 个 Shell 页）。
  static const Color bgPage = neutral0;

  /// 内容容器底色。
  static const Color bgSurface = neutral50;

  /// 二级容器（设置卡片等）。
  static const Color bgSurfaceSunken = neutral100;

  /// 设置页左侧竖向分类栏。
  static const Color bgRail = neutral150;

  /// 设置分类 tile（未选中）。
  static const Color bgTile = neutral250;

  /// 底部导航药丸容器。
  static const Color bgDock = neutral300;

  /// 搜索栏输入底（已裁决 Q3 = `#E8E8E8`）。
  static const Color bgInput = neutral200;

  /// 专辑卡、迷你播放器胶囊。
  static const Color bgCard = neutral0;

  /// 迷你播放器控制按钮底。
  static const Color bgControl = neutral50;

  /// 封面占位、骨架屏。
  static const Color bgPlaceholder = neutral400;

  // ── 品牌 / 强调 ──────────────────────────────────────────
  /// 主强调色：Tab 选中圆、进度条已播放段、主按钮。
  static const Color accent = Color(0xFF7C6BFF);

  /// 按下态（`accent` 明度 −8%）。
  static const Color accentPressed = Color(0xFF6A57F0);

  /// 浅紫底（`accent` 12% 混白）。
  static const Color accentSoft = Color(0xFFEAE7FF);

  /// 紫色底上的图标 / 文字。
  static const Color onAccent = neutral0;

  // ── 文字 ─────────────────────────────────────────────────
  /// 标题、歌名、主要内容（对 `#FFFFFF` 17.4:1 · AAA）。
  static const Color textPrimary = Color(0xFF1A1A1A);

  /// 副标题、辅助说明（5.7:1 · AA）。
  static const Color textSecondary = Color(0xFF666666);

  /// 占位文字、歌手名、未选中 Tab 文字、时长（2.8:1，
  /// **仅限占位与非关键辅助信息**，不得承载必要正文 —— PRD §6.3 注）。
  static const Color textTertiary = Color(0xFF999999);

  /// 紫色底上的文字。
  static const Color textOnAccent = neutral0;

  /// 选中 Tab 文字、链接。
  static const Color textAccent = accent;

  // ── 图标 ─────────────────────────────────────────────────
  /// 未选中 Tab 图标、搜索图标、次要图标。
  static const Color iconInactive = Color(0xFF999999);

  /// 选中态图标（非圆底场景）。
  static const Color iconActive = accent;

  /// 紫色圆内图标（已裁决 Q2 · 方案 A）。
  static const Color iconOnAccent = neutral0;

  /// 播放 / 暂停等主操作图标。
  static const Color iconPrimary = Color(0xFF1A1A1A);

  // ── 描边 / 分割 ──────────────────────────────────────────
  /// 专辑卡描边、通用 1px 边框。
  static const Color borderDefault = neutral150;

  /// Dock 药丸描边（SVG 明确为白色）。
  static const Color borderDock = neutral0;

  /// 列表分割线。
  static const Color divider = neutral100;

  // ── 进度 ─────────────────────────────────────────────────
  /// 播放进度条未播放段底轨（已播放段用 [accent]）。
  static const Color progressTrack = neutral400;

  // ── 状态（PRD 未列，工程补充；保持浅色体系观感）───────────
  /// 错误 / 危险操作。
  static const Color danger = Color(0xFFE05B5B);

  /// 错误提示浅底。
  static const Color dangerSoft = Color(0xFFFCEAEA);

  /// 成功 / 已连接。
  static const Color success = Color(0xFF3BA776);

  /// 警告 / 需要注意。
  static const Color warning = Color(0xFFE0A33B);

  /// 全屏遮罩（对话框 / 底部弹层）。
  static const Color scrim = Color(0x66000000);
}

// ─────────────────────────────────────────────────────────────────────────
// 2. 圆角 Token —— PRD §6.4
// ─────────────────────────────────────────────────────────────────────────

/// 圆角半径与常用 [BorderRadius] 快捷常量。
abstract final class AppRadius {
  /// 8dp · 小控件。
  static const double sm = 8;

  /// 18dp · 设置分类 tile。
  static const double md = 18;

  /// 24dp · 专辑卡、设置卡片。
  static const double lg = 24;

  /// 36dp · 内容容器、迷你播放器胶囊。
  static const double xl = 36;

  /// 999dp · 完全圆角（搜索栏、Dock、进度条、控制按钮）。
  static const double pill = 999;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(pill));
}

// ─────────────────────────────────────────────────────────────────────────
// 3. 间距 Token —— PRD §6.4
// ─────────────────────────────────────────────────────────────────────────

/// 间距刻度。
abstract final class AppSpace {
  /// 4dp · 设置 tile 间距。
  static const double xs = 4;

  /// 5dp · 迷你播放器与 Dock / 内容容器的间距。
  static const double sm = 5;

  /// 10dp · 专辑卡内文本左边距（PRD §4.2 专辑卡文本行）。
  static const double cardTextInset = 10;

  /// 14dp · 屏幕外边距。
  static const double md = 14;

  /// 18dp · 容器内边距。
  static const double lg = 18;

  /// 36dp · 曲库列间距。
  static const double xl = 36;

  /// 16dp · 曲库行间距（PRD §4.2 网格布局）。
  static const double gridRowGap = 16;
}

// ─────────────────────────────────────────────────────────────────────────
// 4. 尺寸 Token —— PRD §6.4 / §4.2 / §4.3
// ─────────────────────────────────────────────────────────────────────────

/// 固定尺寸。
abstract final class AppSize {
  /// 搜索栏高度。
  static const double heightSearch = 40;

  /// 迷你播放器单个胶囊高度。
  static const double heightMiniPill = 72;

  /// 迷你播放器整组高度（进度条 8 + 胶囊 72 = 80）。
  static const double heightMiniGroup = 80;

  /// Dock 药丸高度。
  static const double heightDock = 76;

  /// 播放进度条高度。
  static const double heightProgress = 8;

  /// 进度条左右边距（PRD §4.2：(972−800)/2 ÷ 2.5 ≈ 34dp）。
  static const double progressInset = 34;

  /// 通用图标尺寸（Tab / tile / 控制按钮）。
  static const double icon = 26;

  /// 小号图标（搜索栏、行内辅助）。
  static const double iconSm = 20;

  /// Tab 选中紫色圆直径（已裁决 Q2 · 方案 A）。
  static const double tabIndicator = 44;

  /// 迷你播放器左胶囊缩略图边长。
  static const double thumb = 48;

  /// 专辑卡封面区边长。
  static const double cover = 72;

  /// 设置页左侧分类栏宽度。
  static const double rail = 52;

  /// 设置分类 tile 尺寸（48×76）。
  static const double tileWidth = 48;
  static const double tileHeight = 76;

  /// 迷你播放器控制按钮（36×48）。
  static const double miniButtonWidth = 36;
  static const double miniButtonHeight = 48;

  /// 最小触控热区（P1-11）。
  static const double touchMin = 44;

  /// Dock 圆角（高 76 → 38 为半高药丸）。
  static const double dockRadius = heightDock / 2;

  /// 屏幕外边距（内容容器 / 迷你播放器 / Dock 共用的水平外边距）。
  ///
  /// 【裁决 A1 · 满宽】取 0dp，设计稿的 14dp 外边距不落地，
  /// 改由容器内边距 [AppSpace.lg] 承担留白。
  /// 三个 Shell 组件共用本 Token —— 要改回 14dp 只需改这一处。
  static const double shellEdgeInset = 0;

  /// 窄屏兜底阈值（P1-10：< 375dp 时等比缩小迷你播放器）。
  static const double narrowBreakpoint = 375;

  /// 几何基准宽度。
  static const double baseWidth = 390;
}

// ─────────────────────────────────────────────────────────────────────────
// 5. 阴影 Token —— PRD §6.5
// ─────────────────────────────────────────────────────────────────────────

/// 阴影。
///
/// 【裁决 A4】两个变体都定义；当前 [card] 指向**忠实还原**版本
/// [cardFaithful]，待真机与 PDF 比对后可一处切换到 [cardSoft]。
abstract final class AppShadow {
  /// 忠实还原设计稿滤镜 `filter12_d`（offset 0 / blur 2 / dilate 1 / 黑 25%）。
  static const BoxShadow cardFaithful = BoxShadow(
    color: Color(0x40000000),
    blurRadius: 2,
    spreadRadius: 0.5,
    offset: Offset.zero,
  );

  /// 工程推荐变体：真机上更接近「微阴影」观感。
  static const BoxShadow cardSoft = BoxShadow(
    color: Color(0x14000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  /// 当前生效的卡片阴影（唯一切换点）。
  static const BoxShadow card = cardFaithful;

  /// 便捷列表形式，直接喂给 [BoxDecoration.boxShadow]。
  static const List<BoxShadow> cardList = <BoxShadow>[card];
  static const List<BoxShadow> softList = <BoxShadow>[cardSoft];
}

// ─────────────────────────────────────────────────────────────────────────
// 6. 字体 Token —— PRD §6.6
// ─────────────────────────────────────────────────────────────────────────

/// 文字样式。字体族跟随系统（iOS = PingFang SC，Android = Noto Sans CJK），
/// 不引入自定义字体。
abstract final class AppTextStyles {
  /// 18 / w600 · 页面与区块标题。
  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  /// 16 / w600 · 区块小标题。
  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  /// 14 / w400 · 正文、设置项。
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// 14 / w400 / 次级色 · 说明性正文。
  static const TextStyle bodyMuted = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  /// 14 / w600 · 迷你播放器歌名、专辑卡曲名。
  static const TextStyle trackName = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  /// 12 / w400 · 歌手名。
  static const TextStyle artist = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.25,
  );

  /// 11 / w400 · 时长、辅助信息。
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.2,
  );

  /// 10 / w500 · Dock Tab 文字标签。
  static const TextStyle tabLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AppColors.iconInactive,
    height: 1.2,
  );

  /// 9 / w400 · 设置分类 tile 文字（52dp 栏内仅容 2 个汉字）。
  static const TextStyle tileLabel = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.15,
  );

  /// 14 / w400 / 占位色 · 搜索栏 hint。
  static const TextStyle hint = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.2,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// 6b. 命名兼容别名
// ─────────────────────────────────────────────────────────────────────────
//
// 重构期间两位工程师并行落地，出现了两套等价命名（`AppNeutral.n0` ↔
// `AppColors.neutral0`、`AppText` ↔ `AppTextStyles`）。为避免互相覆盖导致
// 编译中断，这里把两套名字都保留为**同一常量的别名**（零运行时开销）。
//
// 📌 收敛方向：新代码一律使用 `AppColors.neutralXX` 与 `AppTextStyles`，
//    本节别名待全量替换完成后可整体删除。

/// 中性色阶别名 —— 等价于 `AppColors.neutralXX`。
abstract final class AppNeutral {
  static const Color n0 = AppColors.neutral0;
  static const Color n50 = AppColors.neutral50;
  static const Color n100 = AppColors.neutral100;
  static const Color n150 = AppColors.neutral150;
  static const Color n200 = AppColors.neutral200;
  static const Color n250 = AppColors.neutral250;
  static const Color n300 = AppColors.neutral300;
  static const Color n400 = AppColors.neutral400;
}

/// 文字样式别名 —— 等价于 [AppTextStyles]。
abstract final class AppText {
  static const TextStyle title = AppTextStyles.title;
  static const TextStyle subtitle = AppTextStyles.subtitle;
  static const TextStyle body = AppTextStyles.body;
  static const TextStyle bodyMuted = AppTextStyles.bodyMuted;
  static const TextStyle trackName = AppTextStyles.trackName;
  static const TextStyle artist = AppTextStyles.artist;
  static const TextStyle caption = AppTextStyles.caption;
  static const TextStyle tabLabel = AppTextStyles.tabLabel;
  static const TextStyle tileLabel = AppTextStyles.tileLabel;
  static const TextStyle hint = AppTextStyles.hint;
}

// ─────────────────────────────────────────────────────────────────────────
// 7. 动效 Token
// ─────────────────────────────────────────────────────────────────────────

/// 动画时长与曲线。
abstract final class AppMotion {
  /// 150ms · 微交互（按下反馈）。
  static const Duration fast = Duration(milliseconds: 150);

  /// 200ms · Tab 选中态过渡（P1-03 / P0-B3）。
  static const Duration tab = Duration(milliseconds: 200);

  /// 240ms · 常规过渡。
  static const Duration normal = Duration(milliseconds: 240);

  /// 400ms · 大面积转场。
  static const Duration slow = Duration(milliseconds: 400);

  /// 缓动曲线。
  static const Curve ease = Curves.easeOutCubic;
}
