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
/// 【iOS 化 · cl13】依据 `docs/UI_IOS_DESIGN_TOKENS.md` §1，全面切换到
/// **Apple iOS 系统色值**（HIG 一致）。浅色用经典 iOS 灰底层级 +
/// `systemBlue` 强调色；原紫色皮肤体系（`withSkin` 派生）已废弃，
/// 强调色固定为 `systemBlue #007AFF`。
///
/// 分两层：
/// * **中性色阶** `neutral0` … `neutral400` —— 对齐 iOS 三级系统背景 +
///   separator / placeholder 等；
/// * **语义别名** `bgPage` / `textPrimary` … —— 业务代码应优先使用语义名，
///   只有语义表未覆盖的边缘场景才直接引用色阶。
abstract final class AppColors {
  // ── 中性色阶（对齐 iOS 系统层级）──────────────────────────
  /// `#FFFFFF` · systemBackground（一级页面底）。
  static const Color neutral0 = Color(0xFFFFFFFF);

  /// `#F2F2F7` · secondarySystemBackground（二级容器 / 列表组底）。
  static const Color neutral50 = Color(0xFFF2F2F7);

  /// `#E5E5EA` · tertiarySystemBackground / systemGray5（三级容器）。
  static const Color neutral100 = Color(0xFFE5E5EA);

  /// `#D1D1D6` · systemGray4（通用描边 / 占位图）。
  static const Color neutral150 = Color(0xFFD1D1D6);

  /// `#C7C7CC` · systemGray3（搜索栏底）。
  static const Color neutral200 = Color(0xFFC7C7CC);

  /// `#AEAEB2` · systemGray2（设置分类 tile）。
  static const Color neutral250 = Color(0xFFAEAEB2);

  /// `#8E8E93` · systemGray（Dock 等低频底）。
  static const Color neutral300 = Color(0xFF8E8E93);

  /// `#3C3C43` · separator 暗化占位（`rgba(60,60,67,0.29)` ≈ #3C3C43）。
  static const Color neutral400 = Color(0x4D3C3C43);

  // ── 背景 / 表面（iOS 系统背景层级）───────────────────────
  /// Scaffold 底色（全部 5 个 Shell 页）= systemBackground。
  static const Color bgPage = neutral0;

  /// 内容容器底色 = secondarySystemBackground。
  static const Color bgSurface = neutral50;

  /// 二级容器（设置卡片等）= tertiarySystemBackground。
  static const Color bgSurfaceSunken = neutral100;

  /// 设置页左侧竖向分类栏。
  static const Color bgRail = neutral50;

  /// 设置分类 tile（未选中）。
  static const Color bgTile = neutral100;

  /// 底部导航 TabBar 容器（iOS 原生毛玻璃，不实底）。
  static const Color bgDock = neutral50;

  /// 搜索栏输入底 = systemGray3。
  static const Color bgInput = neutral200;

  /// 专辑卡、迷你播放器胶囊 = systemBackground（卡片浮于 surface 之上）。
  static const Color bgCard = neutral0;

  /// 迷你播放器控制按钮底 = secondarySystemBackground。
  static const Color bgControl = neutral50;

  /// 封面占位、骨架屏 = systemGray4。
  static const Color bgPlaceholder = neutral150;

  // ── 品牌 / 强调（iOS systemBlue · 紫色体系已废弃）─────────
  /// 主强调色：Tab 选中、进度条已播放段、主按钮 = systemBlue。
  static const Color accent = Color(0xFF007AFF);

  /// 按下态（systemBlue 明度 −8%）。
  static const Color accentPressed = Color(0xFF0062CC);

  /// 浅蓝底（accent 12% 混白）。
  static const Color accentSoft = Color(0xFFE5F1FF);

  /// 强调色底上的图标 / 文字（白）。
  static const Color onAccent = neutral0;

  // ── 文字（iOS label 层级）────────────────────────────────
  /// 标题、歌名、主要内容 = label `#000000`。
  static const Color textPrimary = Color(0xFF000000);

  /// 副标题、辅助说明 = secondaryLabel `rgba(60,60,67,0.6)`。
  static const Color textSecondary = Color(0x993C3C43);

  /// 占位文字、歌手名、未选中 Tab 文字、时长 = tertiaryLabel
  /// `rgba(60,60,67,0.3)`（**仅限占位与非关键辅助信息**）。
  static const Color textTertiary = Color(0x4D3C3C43);

  /// 强调色底上的文字（白）。
  static const Color textOnAccent = neutral0;

  /// 选中 Tab 文字、链接 = systemBlue。
  static const Color textAccent = accent;

  // ── 图标 ─────────────────────────────────────────────────
  /// 未选中 Tab 图标、搜索图标、次要图标 = tertiaryLabel。
  static const Color iconInactive = Color(0x4D3C3C43);

  /// 选中态图标（非圆底场景）= systemBlue。
  static const Color iconActive = accent;

  /// 强调色圆内图标 = 白。
  static const Color iconOnAccent = neutral0;

  /// 播放 / 暂停等主操作图标 = label。
  static const Color iconPrimary = Color(0xFF000000);

  // ── 描边 / 分割（iOS separator）──────────────────────────
  /// 专辑卡描边、通用 1px 边框 = separator `rgba(60,60,67,0.29)`。
  static const Color borderDefault = Color(0x4D3C3C43);

  /// Dock TabBar 自带毛玻璃描边（不依赖实色，保留中性灰兜底层）。
  static const Color borderDock = Color(0x4D3C3C43);

  /// 列表分割线 = separator。
  static const Color divider = Color(0x4D3C3C43);

  // ── 进度 ─────────────────────────────────────────────────
  /// 播放进度条未播放段底轨 = systemGray4。
  static const Color progressTrack = neutral150;

  // ── 状态（iOS 系统状态色 · 浅色）─────────────────────────
  /// 错误 / 危险操作 = systemRed。
  static const Color danger = Color(0xFFFF3B30);

  /// 错误提示浅底（systemRed 8% 混白）。
  static const Color dangerSoft = Color(0xFFFDECEA);

  /// 成功 / 已连接 = systemGreen。
  static const Color success = Color(0xFF34C759);

  /// 警告 / 需要注意 = systemOrange。
  static const Color warning = Color(0xFFFF9500);

  /// 全屏遮罩（对话框 / 底部弹层）= 黑 40%。
  static const Color scrim = Color(0x66000000);
}

// ─────────────────────────────────────────────────────────────────────────
// 2. 圆角 Token —— PRD §6.4
// ─────────────────────────────────────────────────────────────────────────

/// 圆角半径与常用 [BorderRadius] 快捷常量。
///
/// 【iOS 化 · cl13】分组列表圆角 10pt、卡片 12–16pt、控件胶囊（高/2）。
abstract final class AppRadius {
  /// 10dp · 分组列表 / 小控件（iOS 列表组圆角）。
  static const double sm = 10;

  /// 14dp · 设置分类 tile / 中等卡片。
  static const double md = 14;

  /// 16dp · 专辑卡、设置卡片（iOS 卡片圆角）。
  static const double lg = 16;

  /// 22dp · 内容容器、迷你播放器胶囊（大圆角表面）。
  static const double xl = 22;

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
///
/// 【iOS 化 · cl13】8pt 栅格（4 / 8 / 12 / 16 / 20 / 24）。
abstract final class AppSpace {
  /// 4dp · 设置 tile 间距。
  static const double xs = 4;

  /// 8dp · 迷你播放器与 Dock / 内容容器的间距（8pt 栅格）。
  static const double sm = 8;

  /// 12dp · 专辑卡内文本左边距（8pt 栅格对齐）。
  static const double cardTextInset = 12;

  /// 16dp · 屏幕外边距（8pt 栅格）。
  static const double md = 16;

  /// 20dp · 容器内边距（8pt 栅格）。
  static const double lg = 20;

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

  /// Dock / TabBar 高度（iOS 化后由 [AppDock.kTabBarHeight] 接管实际高度，
  /// 此处保留供 AppShell 悬浮预留计算）。
  static const double heightDock = 76;

  /// Dock 离底悬浮间隙（R32：iOS26 悬浮 Dock——浮于底部之上，非贴底）。
  static const double dockFloatGap = 12;

  /// 播放进度条高度。
  static const double heightProgress = 8;

  /// 进度条左右边距（PRD §4.2：(972−800)/2 ÷ 2.5 ≈ 34dp）。
  static const double progressInset = 34;

  /// 通用图标尺寸（Tab / tile / 控制按钮）。
  static const double icon = 26;

  /// 小号图标（搜索栏、行内辅助）。
  static const double iconSm = 20;

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

  // ── v2 横屏 Token（M1 · P0-M1-4 / Q1 方案 C）────────────────
  /// 横屏断点：宽 ≥ 600dp 启用横屏布局（PRD §4.1 / 架构 §7.5）。
  static const double landscapeBreakpoint = 600;

  /// 横屏时底部 Dock 最大宽度（方案 C：底部收窄居中限宽）。
  static const double landscapeDockMaxWidth = 560;

  /// 横屏时迷你播放器最大宽度。
  static const double landscapeMiniMaxWidth = 760;

  /// 横屏时内容容器最大宽度（居中，页面在容器内重排）。
  static const double contentMaxWidth = 1200;

  /// 通用信息行封面边长（InfoRow，P0-M1-3）。
  static const double infoCover = 48;
}

// ─────────────────────────────────────────────────────────────────────────
// 5. 阴影 Token —— PRD §6.5
// ─────────────────────────────────────────────────────────────────────────

/// 阴影。
///
/// 【iOS 化 cl13 §6.3】iOS 的层级语言是「底色分层 + 1px 描边」，**不用投影**。
/// 因此卡片阴影统一去化：保留令牌定义以便个别需要浮起的场景（如浮层/Popover）
/// 仍能取用，但常规卡片（[card]/[cardList]）改为空，纯靠 border + 分层底色区分。
abstract final class AppShadow {
  /// 忠实还原设计稿滤镜 `filter12_d`（offset 0 / blur 2 / dilate 1 / 黑 25%）。
  /// 仅保留定义，常规卡片已不再使用。
  static const BoxShadow cardFaithful = BoxShadow(
    color: Color(0x40000000),
    blurRadius: 2,
    spreadRadius: 0.5,
    offset: Offset.zero,
  );

  /// 工程推荐变体：真机上更接近「微阴影」观感。
  /// 仅保留定义，常规卡片已不再使用。
  static const BoxShadow cardSoft = BoxShadow(
    color: Color(0x14000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  /// 当前生效的卡片阴影：iOS 化后为**无阴影**（靠 border + 分层底色）。
  static const BoxShadow card = BoxShadow(
    color: Color(0x00000000),
    blurRadius: 0,
    spreadRadius: 0,
    offset: Offset.zero,
  );

  /// 便捷列表形式，直接喂给 [BoxDecoration.boxShadow]。iOS 化后为空。
  static const List<BoxShadow> cardList = <BoxShadow>[];
  static const List<BoxShadow> softList = <BoxShadow>[];
}

// ─────────────────────────────────────────────────────────────────────────
// 6. 字体 Token —— PRD §6.6
// ─────────────────────────────────────────────────────────────────────────

/// 全局字体回退链（#582 修复黄色双下划线）。
///
/// 当系统默认字体缺少某字形（如场景 glyph `✦` U+2726、各种 emoji / 特殊符号）
/// 时，Flutter 在 debug 模式会渲染「豆腐块 + 黄色双下划线」的缺失字形指示。
/// 这里给出一组跨平台符号 / emoji 字体作为回退，让这些字形走系统符号字体
/// 正常显示，从而消除黄色双下划线。
///
/// 顺序无关紧要：引擎会从主字体（系统默认）起，依次在回退链里寻找首个含该
/// 字形的字体。
const List<String> kFontFallback = <String>[
  'Segoe UI Symbol',
  'Segoe UI Emoji',
  'Noto Sans Symbols',
  'Noto Sans Symbols2',
  'Noto Color Emoji',
  'Apple Color Emoji',
];

/// 文字样式。字体族跟随系统（iOS = PingFang SC，Android = Noto Sans CJK），
/// 不引入自定义字体。
///
/// 【iOS 化 · cl13】对齐 SF Pro 字号阶梯——Large Title 31/w400、
/// Body 全局默认 17/w400、Title1–Title3 / Headline / Callout / Subhead /
/// Footnote / Caption1。全局 Body 由 14pt 放大到 17pt。
abstract final class AppTextStyles {
  /// 31 / w400 · iOS Large Title（页面大标题，固定不折叠）。
  static const TextStyle largeTitle = TextStyle(
    fontSize: 31,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.2,
    fontFamilyFallback: kFontFallback,
  );

  /// 17 / w600 · 页面与区块标题（iOS Title3 尺寸，原 18→17）。
  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
    fontFamilyFallback: kFontFallback,
  );

  /// 16 / w600 · 区块小标题（iOS Headline）。
  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
    fontFamilyFallback: kFontFallback,
  );

  /// 17 / w400 · 正文、设置项（iOS Body，全局默认，原 14→17）。
  static const TextStyle body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.4,
    fontFamilyFallback: kFontFallback,
  );

  /// 17 / w400 / 次级色 · 说明性正文（iOS Body，次级色）。
  static const TextStyle bodyMuted = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
    fontFamilyFallback: kFontFallback,
  );

  /// 17 / w600 · 迷你播放器歌名、专辑卡曲名（iOS Body · Semibold）。
  static const TextStyle trackName = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.25,
    fontFamilyFallback: kFontFallback,
  );

  /// 15 / w400 · 歌手名（iOS Callout，次级色）。
  static const TextStyle artist = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.25,
    fontFamilyFallback: kFontFallback,
  );

  /// 13 / w400 · 时长、辅助信息（iOS Footnote）。
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.2,
    fontFamilyFallback: kFontFallback,
  );

  /// 10 / w500 · Dock Tab 文字标签。
  static const TextStyle tabLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AppColors.iconInactive,
    height: 1.2,
    fontFamilyFallback: kFontFallback,
  );

  /// 11 / w400 · 设置分类 tile 文字（iOS Caption1）。
  static const TextStyle tileLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.15,
    fontFamilyFallback: kFontFallback,
  );

  /// 17 / w400 / 占位色 · 搜索栏 hint（iOS Body）。
  static const TextStyle hint = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.2,
    fontFamilyFallback: kFontFallback,
  );

  /// 17 / w600 · 按钮文字（FilledButton / TextButton / OutlinedButton）。
  ///
  /// ⚠️ 这里刻意**不带 `color`**：按钮文字色由各按钮主题的
  /// `foregroundColor` 决定（实心按钮 = `onAccent` 白字，
  /// 文字/描边按钮 = `accent` 蓝字）。若在此写死颜色，
  /// 会覆盖掉 `ButtonStyle.foregroundColor`，导致实心按钮出现白底白字。
  static const TextStyle button = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
    fontFamilyFallback: kFontFallback,
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
  static const TextStyle largeTitle = AppTextStyles.largeTitle;
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
  static const TextStyle button = AppTextStyles.button;
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
