import 'package:flutter/material.dart';

import 'light_tokens.dart';

// ═════════════════════════════════════════════════════════════
// ⚠️ 作用域声明（UI 全面重构后，务必遵守）
//
// 本文件的 `buildAppTheme()` 是**动态派生暗色主题**，自 UI 重构起
// 其作用域已收缩为「暗色主题孤岛」，**仅允许**在以下两处使用：
//
//   1. lib/pages/canvas/canvas_page.dart      —— 沉浸画布
//   2. lib/pages/settings/palette_studio_page.dart —— 调色盘工作台
//
// 使用形式固定为：
//   Theme(data: buildAppTheme(ref.watch(effectivePrimaryProvider)), child: ...)
//
// 🚫 **禁止**在主 Shell（app.dart / app_shell.dart）、4 个 Tab 页、
//    Home 页、设置页与设置子页中 import 或使用本文件。
//    那些位置一律使用 `core/theme/light_theme.dart` + `core/theme/light_tokens.dart`。
//
// 同样受此约束的还有：core/theme/palette.dart、core/theme/design_tokens.dart。
// 详见 docs/ARCHITECTURE_UI_重构.md §1.1 优化③ 与 §7 约定 C3。
// ═════════════════════════════════════════════════════════════

/// 星璃品牌固定色（不随主色变化的部分）
abstract final class StelarithColors {
  static const Color deepSpacePurple = Color(0xFF101420); // 深色基底
  static const Color milkWhite = Color(0xFFF8F4ED); // 奶白（文字）
  static const Color starlightGold = Color(0xFFF5D98F); // 星光金
}

/// 由主色动态构建 Material 3 主题。
///
/// 所有官方控件（Card / IconButton / Slider / LinearProgressIndicator / ListTile…）
/// 自动从 ColorScheme 取色，保证全局观感统一、跟随用户主色。
///
/// ────────────────────────────────────────────────────────────────────────
/// ⚠️ **作用域已收缩（UI 浅色重构 · T01）**
///
/// 本函数**不再驱动 `MaterialApp.theme`**。全局主题改由
/// `core/theme/light_theme.dart` 的顶层常量 `kLightTheme` 提供
/// （固定浅色、显式 `ColorScheme.light`、`themeMode: light`，见 P0-A1/A2/A3）。
///
/// 保留本函数是为了服务**暗色画布孤岛**：`CanvasPage` 及其内部的
/// `PalettePanel` / `Orb` / `ControlBar` / `MorePanel` / `ReactiveParticles`
/// 等沉浸式资产，仍需要跟随 `effectivePrimaryProvider` 的深色主题。
/// 它们通过在 `CanvasPage.build()` 最外层包一层
/// `Theme(data: buildAppTheme(primary))` 局部覆盖，
/// **不得**再被 Shell 或 4 个主 Tab 页引用（P0-A4 / 约定 C3）。
/// ────────────────────────────────────────────────────────────────────────
ThemeData buildAppTheme(Color primary, {Brightness brightness = Brightness.dark}) {
  final bool isDark = brightness == Brightness.dark;

  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
    surface: StelarithColors.deepSpacePurple,
  );

  final Color baseText = isDark ? StelarithColors.milkWhite : scheme.onSurface;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: StelarithColors.deepSpacePurple,
    // cl04：去 Material 水波纹 → 原生按压感（CanvasPage 沉浸孤岛一致）。
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.white.withValues(alpha: 0.08),

    // ── 文字：统一由主题驱动 ─────────────────────────
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        color: baseText.withValues(alpha: 0.9),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        fontFamilyFallback: kFontFallback,
      ),
      titleLarge: TextStyle(
        color: baseText.withValues(alpha: 0.9),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
        fontFamilyFallback: kFontFallback,
      ),
      titleMedium: TextStyle(
        color: baseText.withValues(alpha: 0.8),
        fontWeight: FontWeight.w400,
        letterSpacing: 0.3,
        fontFamilyFallback: kFontFallback,
      ),
      bodyLarge: TextStyle(
        color: baseText.withValues(alpha: 0.8),
        fontWeight: FontWeight.w400,
        height: 1.5,
        fontFamilyFallback: kFontFallback,
      ),
      bodyMedium: TextStyle(
        color: baseText.withValues(alpha: 0.65),
        fontWeight: FontWeight.w300,
        height: 1.4,
        fontFamilyFallback: kFontFallback,
      ),
      bodySmall: TextStyle(
        color: baseText.withValues(alpha: 0.45),
        fontWeight: FontWeight.w300,
        fontFamilyFallback: kFontFallback,
      ),
      labelSmall: TextStyle(
        color: baseText.withValues(alpha: 0.35),
        fontWeight: FontWeight.w300,
        fontFamilyFallback: kFontFallback,
      ),
    ),

    // ── 卡片：官方 Card，统一圆角/边框 ───────────────
    cardTheme: CardThemeData(
      color: Colors.white.withValues(alpha: 0.05),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── 图标按钮：统一圆角与 hover 态 ────────────────
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        foregroundColor: baseText.withValues(alpha: 0.75),
        shape: const CircleBorder(),
      ),
    ),

    // ── 滑块（调色盘亮度）───────────────────────────
    sliderTheme: SliderThemeData(
      activeTrackColor: primary,
      thumbColor: baseText.withValues(alpha: 0.9),
      inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
      overlayColor: primary.withValues(alpha: 0.15),
    ),

    // ── 进度条（卡片播放进度）───────────────────────
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: Colors.white.withValues(alpha: 0.08),
    ),
  );
}
