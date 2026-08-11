/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐空间 · 固定浅色主题
/// ════════════════════════════════════════════════════════════════════════
///
/// 需求依据：
/// * **P0-A2** —— `themeMode` 固定为 `ThemeMode.light`，以**显式
///   `ColorScheme.light(...)`** 构建，不再使用 `ColorScheme.fromSeed`。
/// * **P0-A3** —— `#FFFFFF` 页面底色 / `#F5F5F5` 内容容器底色。
///
/// ### 关键设计：主题脱离 Provider
/// 旧实现由 `effectivePrimaryProvider` 驱动 `MaterialApp.theme`，
/// 导致调色盘一改动就重建整棵树。新实现把主题提升为**顶层不可变常量**
/// [kLightTheme]，一次性构建、全生命周期复用；
/// 用户主色只在**暗色画布孤岛**（`CanvasPage`）内通过
/// `Theme(data: buildAppTheme(primary))` 局部覆盖。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme_colors.dart';
import 'light_tokens.dart';


/// 全局唯一浅色主题实例（一次性构建，不随任何 Provider 变化）。
final ThemeData kLightTheme = buildLightTheme();

/// 显式浅色 `ColorScheme`（P0-A2：禁止 `fromSeed`）。
const ColorScheme kLightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: AppColors.accent,
  onPrimary: AppColors.onAccent,
  primaryContainer: AppColors.accentSoft,
  onPrimaryContainer: AppColors.accent,
  secondary: AppColors.accent,
  onSecondary: AppColors.onAccent,
  secondaryContainer: AppColors.accentSoft,
  onSecondaryContainer: AppColors.accent,
  tertiary: AppColors.accent,
  onTertiary: AppColors.onAccent,
  tertiaryContainer: AppColors.accentSoft,
  onTertiaryContainer: AppColors.accent,
  error: AppColors.danger,
  onError: AppColors.onAccent,
  errorContainer: AppColors.dangerSoft,
  onErrorContainer: AppColors.danger,
  surface: AppColors.bgPage,
  onSurface: AppColors.textPrimary,
  surfaceDim: AppColors.bgSurfaceSunken,
  surfaceBright: AppColors.bgPage,
  surfaceContainerLowest: AppColors.bgPage,
  surfaceContainerLow: AppColors.bgSurface,
  surfaceContainer: AppColors.bgSurfaceSunken,
  surfaceContainerHigh: AppColors.bgRail,
  surfaceContainerHighest: AppColors.bgTile,
  onSurfaceVariant: AppColors.textSecondary,
  outline: AppColors.borderDefault,
  outlineVariant: AppColors.divider,
  shadow: Color(0xFF000000),
  scrim: AppColors.scrim,
  inverseSurface: AppColors.textPrimary,
  onInverseSurface: AppColors.bgPage,
  inversePrimary: AppColors.accentSoft,
);

/// 构建固定浅色主题。
///
/// 所有官方控件（`Card` / `IconButton` / `Slider` / `SnackBar` / `ListTile` …）
/// 都从这里取色，避免业务代码散落 `Color(0x...)` 字面量（约定 C1）。
ThemeData buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: kLightColorScheme,
    // R16：全局语义色（浅色值）
    extensions: const <ThemeExtension<dynamic>>[AppThemeColors.light],
    scaffoldBackgroundColor: AppColors.bgPage,
    canvasColor: AppColors.bgPage,
    dividerColor: AppColors.divider,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,

    // ── 文字 ─────────────────────────────────────────────
    textTheme: const TextTheme(
      headlineSmall: AppTextStyles.title,
      titleLarge: AppTextStyles.title,
      titleMedium: AppTextStyles.subtitle,
      titleSmall: AppTextStyles.trackName,
      bodyLarge: AppTextStyles.body,
      bodyMedium: AppTextStyles.bodyMuted,
      bodySmall: AppTextStyles.artist,
      // labelLarge 是 Material 按钮文字的标准槽位，必须用按钮语义样式，
      // 不能借用 trackName（那是迷你播放器曲名，语义错配）。
      labelLarge: AppTextStyles.button,
      labelMedium: AppTextStyles.tabLabel,
      labelSmall: AppTextStyles.tileLabel,
    ),

    // ── 图标 ─────────────────────────────────────────────
    iconTheme: const IconThemeData(
      color: AppColors.iconPrimary,
      size: AppSize.icon,
    ),
    primaryIconTheme: const IconThemeData(
      color: AppColors.iconOnAccent,
      size: AppSize.icon,
    ),

    // ── AppBar（仅全屏子路由使用；Shell 自身无 AppBar）────
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgPage,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppTextStyles.title,
      iconTheme: IconThemeData(color: AppColors.iconPrimary, size: AppSize.icon),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.bgPage,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),

    // ── 卡片 ─────────────────────────────────────────────
    cardTheme: const CardThemeData(
      color: AppColors.bgCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brLg,
        side: BorderSide(color: AppColors.borderDefault),
      ),
    ),

    // ── 分割线 ───────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),

    // ── 列表项 ───────────────────────────────────────────
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.iconPrimary,
      textColor: AppColors.textPrimary,
      titleTextStyle: AppTextStyles.body,
      subtitleTextStyle: AppTextStyles.artist,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.lg),
    ),

    // ── 输入框（搜索栏、设置表单）──────────────────────────
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgInput,
      isDense: true,
      hintStyle: AppTextStyles.hint,
      labelStyle: AppTextStyles.bodyMuted,
      contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: AppRadius.brPill,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.brPill,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.brPill,
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.brPill,
        borderSide: BorderSide(color: AppColors.danger),
      ),
    ),

    // ── 按钮 ─────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textOnAccent,
        disabledBackgroundColor: AppColors.bgPlaceholder,
        disabledForegroundColor: AppColors.textTertiary,
        textStyle: AppTextStyles.button,
        minimumSize: const Size(0, AppSize.touchMin),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brPill),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textAccent,
        textStyle: AppTextStyles.button,
        minimumSize: const Size(0, AppSize.touchMin),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        textStyle: AppTextStyles.button,
        side: const BorderSide(color: AppColors.borderDefault),
        minimumSize: const Size(0, AppSize.touchMin),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brPill),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.bgCard,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        textStyle: AppTextStyles.button,
        minimumSize: const Size(0, AppSize.touchMin),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brPill),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.iconPrimary,
        backgroundColor: Colors.transparent,
        highlightColor: AppColors.accentSoft,
        shape: const CircleBorder(),
      ),
    ),

    // ── 进度 / 滑块 ──────────────────────────────────────
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.bgPlaceholder,
      circularTrackColor: AppColors.bgPlaceholder,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.bgPlaceholder,
      thumbColor: AppColors.accent,
      overlayColor: AppColors.accentSoft,
      valueIndicatorColor: AppColors.accent,
      trackHeight: 4,
    ),

    // ── 开关 / 勾选 ──────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.onAccent
            : AppColors.bgPage;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.bgPlaceholder;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.accent
            : Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(AppColors.onAccent),
      side: const BorderSide(color: AppColors.borderDefault, width: 1.5),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.iconInactive;
      }),
    ),

    // ── 反馈 ─────────────────────────────────────────────
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.bgPage,
        height: 1.4,
      ),
      actionTextColor: AppColors.accentSoft,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      insetPadding: EdgeInsets.all(AppSpace.md),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: AppRadius.brSm,
      ),
      textStyle: TextStyle(fontSize: 12, color: AppColors.bgPage),
    ),

    // ── 弹层 ─────────────────────────────────────────────
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.bgPage,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: AppTextStyles.title,
      contentTextStyle: AppTextStyles.body,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.bgPage,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: AppColors.bgPlaceholder,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.bgPage,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      textStyle: AppTextStyles.body,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.brMd),
    ),

    // ── 其它 ─────────────────────────────────────────────
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.bgSurface,
      selectedColor: AppColors.accentSoft,
      labelStyle: AppTextStyles.body,
      side: BorderSide(color: AppColors.borderDefault),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.brPill),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.bgPlaceholder),
      radius: const Radius.circular(AppRadius.sm),
      thickness: WidgetStateProperty.all(4),
    ),
  );
}

/// 浅色状态栏样式：透明底 + **深色图标**（P0-A3 配套）。
const SystemUiOverlayStyle kLightOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarBrightness: Brightness.light, // iOS：底色亮 → 系统绘深色图标
  statusBarIconBrightness: Brightness.dark, // Android：深色图标
  systemNavigationBarColor: AppColors.bgPage,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
);

// ════════════════════════════════════════════════════════════════════════
// R16 深色主题（明暗 + 皮肤主色）
// ════════════════════════════════════════════════════════════════════════
//
// 浅色体系以 AppColors 编译期常量为主；深色主题以「深色表面 + 皮肤主色」
// 构建一套完整的 ColorScheme，驱动 Material 官方控件自动适配。
// 业务代码中直接引用 AppColors 的常量为浅色值，深色下会保持原样——
// 本版本聚焦「官方控件随主题切换」，后续可逐步把 AppColors 改为
// Theme.of(context) 取色以完全适配深色。

/// 深色模式固定色阶。
abstract final class DarkColors {
  static const Color bg = Color(0xFF121218);
  static const Color surface = Color(0xFF1C1C26);
  static const Color surfaceHigh = Color(0xFF262634);
  static const Color text = Color(0xFFF2F2F7);
  static const Color textMuted = Color(0xFFB8B8C8);
  static const Color textDim = Color(0xFF8A8A9C);
  static const Color border = Color(0xFF333345);
}

/// 构建深色主题（皮肤主色驱动）。
ThemeData buildDarkTheme(Color primary) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.dark,
    surface: DarkColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    // R16：全局语义色（深色值 + 皮肤主色）
    extensions: <ThemeExtension<dynamic>>[
      AppThemeColors.dark.withSkin(primary, Brightness.dark),
    ],
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: DarkColors.bg,
    canvasColor: DarkColors.bg,
    dividerColor: DarkColors.border,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,

    textTheme: TextTheme(
      headlineSmall: TextStyle(
          color: DarkColors.text, fontSize: 18, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(
          color: DarkColors.text, fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(
          color: DarkColors.text, fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(
          color: DarkColors.text, fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: DarkColors.text, fontSize: 14),
      bodyMedium: TextStyle(color: DarkColors.textMuted, fontSize: 14),
      bodySmall: TextStyle(color: DarkColors.textDim, fontSize: 12),
      labelLarge: TextStyle(
          color: DarkColors.text, fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(color: DarkColors.textMuted, fontSize: 12),
      labelSmall: TextStyle(color: DarkColors.textDim, fontSize: 10),
    ),

    iconTheme: IconThemeData(color: DarkColors.text, size: 26),
    primaryIconTheme: IconThemeData(color: scheme.onPrimary, size: 26),

    appBarTheme: AppBarTheme(
      backgroundColor: DarkColors.bg,
      foregroundColor: DarkColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: DarkColors.bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),

    cardTheme: CardThemeData(
      color: DarkColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: DarkColors.border),
      ),
    ),

    dividerTheme: DividerThemeData(color: DarkColors.border, thickness: 1, space: 1),

    listTileTheme: ListTileThemeData(
      iconColor: DarkColors.text,
      textColor: DarkColors.text,
      titleTextStyle: const TextStyle(color: DarkColors.text, fontSize: 14),
      subtitleTextStyle: const TextStyle(color: DarkColors.textMuted, fontSize: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DarkColors.surfaceHigh,
      isDense: true,
      hintStyle: const TextStyle(color: DarkColors.textDim, fontSize: 14),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: DarkColors.surfaceHigh,
        disabledForegroundColor: DarkColors.textDim,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(999))),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 44),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DarkColors.text,
        side: BorderSide(color: DarkColors.border),
        minimumSize: const Size(0, 44),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(999))),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: DarkColors.text,
        backgroundColor: Colors.transparent,
        shape: const CircleBorder(),
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: DarkColors.surfaceHigh,
      circularTrackColor: DarkColors.surfaceHigh,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: primary,
      inactiveTrackColor: DarkColors.surfaceHigh,
      thumbColor: primary,
      overlayColor: primary.withValues(alpha: 0.15),
      valueIndicatorColor: primary,
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        return states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : DarkColors.surfaceHigh;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        return states.contains(WidgetState.selected)
            ? primary
            : DarkColors.surfaceHigh;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        return states.contains(WidgetState.selected)
            ? primary
            : Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(scheme.onPrimary),
      side: BorderSide(color: DarkColors.border, width: 1.5),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8))),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        return states.contains(WidgetState.selected)
            ? primary
            : DarkColors.textDim;
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: DarkColors.surfaceHigh,
      contentTextStyle: const TextStyle(
          fontSize: 14, color: DarkColors.text, height: 1.4),
      actionTextColor: scheme.primary,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: DarkColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24))),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: DarkColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: DarkColors.textDim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: DarkColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18))),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: DarkColors.surfaceHigh,
      selectedColor: primary.withValues(alpha: 0.25),
      labelStyle: const TextStyle(color: DarkColors.text, fontSize: 14),
      side: BorderSide(color: DarkColors.border),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(999))),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(DarkColors.surfaceHigh),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(4),
    ),
  );
}

