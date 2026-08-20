import 'package:flutter/material.dart';

import 'light_tokens.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 全局语义色 ThemeExtension（R16 主题全局化）
/// ════════════════════════════════════════════════════════════════════════
///
/// 浅色体系一直用 `AppColors`（light_tokens.dart）编译期常量；这些常量
/// 无法跟随主题切换。为了让**明暗主题全局生效**，这里把高频语义色做成
/// `ThemeExtension`：浅色主题注入浅色值、深色主题注入深色值，
/// 业务组件通过 `context.appColors.xxx` 取色即可自动适配明暗。
///
/// 取色约定（新增代码优先）：
///   `context.appColors.bgPage` / `bgSurface` / `textPrimary` / `accent` …

/// 深色模式固定色阶（与 light_theme.dart 的 DarkColors 保持一致）。
///
/// 这里是**独立手调配色板**：所有深色语义色均为作者针对深底逐一定制的
/// 值，**不**由浅色体系反推/取反得到。切换皮肤时由 [AppThemeColors.withSkin]
/// 仅重算强调色族，中性色阶与状态色保持本表不变。
abstract final class AppDarkColors {
  // ── 中性色阶 ──────────────────────────────────
  static const Color bg = Color(0xFF121218);
  static const Color surface = Color(0xFF1C1C26);
  static const Color surfaceHigh = Color(0xFF262634);
  static const Color text = Color(0xFFF2F2F7);
  static const Color textMuted = Color(0xFFB8B8C8);
  static const Color textDim = Color(0xFF8A8A9C);
  static const Color border = Color(0xFF333345);

  /// 占位图 / 骨架屏 / 进度条底轨。
  static const Color placeholder = Color(0xFF32323F);

  /// 深色下的错误浅底。
  static const Color dangerSoft = Color(0xFF3A2429);

  // ── 品牌强调色（starlight 皮肤在深底上的手调值）──
  static const Color accent = Color(0xFF9A8CFF);
  static const Color accentSoft = Color(0xFF2A2740);
  static const Color accentPressed = Color(0xFF8878F0);
  static const Color onAccent = Color(0xFFFFFFFF);

  // ── 状态色（深底手调）─────────────────────────
  static const Color danger = Color(0xFFE06B6B);
  static const Color success = Color(0xFF4CBF8C);
  static const Color warning = Color(0xFFE8B657);

  /// 全屏遮罩 / 进度底轨。
  static const Color scrim = Color(0x99000000);
  static const Color progressTrack = Color(0xFF3A3A4C);

  /// 完整深色语义调色板（手调，独立于浅色）。
  ///
  /// [AppThemeColors.dark] 直接复用，避免在工厂里散落内联字面量。
  static const AppThemeColors palette = AppThemeColors(
    bgPage: bg,
    bgSurface: surface,
    bgSurfaceSunken: surfaceHigh,
    bgCard: surface,
    bgRail: surface,
    bgTile: surfaceHigh,
    bgDock: surface,
    bgInput: surfaceHigh,
    bgControl: surfaceHigh,
    bgPlaceholder: placeholder,
    textPrimary: text,
    textSecondary: textMuted,
    textTertiary: textDim,
    accent: accent,
    accentSoft: accentSoft,
    accentPressed: accentPressed,
    onAccent: onAccent,
    iconPrimary: text,
    iconInactive: textDim,
    border: border,
    divider: border,
    danger: danger,
    dangerSoft: dangerSoft,
    success: success,
    warning: warning,
    scrim: scrim,
    progressTrack: progressTrack,
  );
}

/// 全局语义色（随主题明暗切换）。
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.bgPage,
    required this.bgSurface,
    required this.bgSurfaceSunken,
    required this.bgCard,
    required this.bgRail,
    required this.bgTile,
    required this.bgDock,
    required this.bgInput,
    required this.bgControl,
    required this.bgPlaceholder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.accentPressed,
    required this.onAccent,
    required this.iconPrimary,
    required this.iconInactive,
    required this.border,
    required this.divider,
    required this.danger,
    required this.dangerSoft,
    required this.success,
    required this.warning,
    required this.scrim,
    required this.progressTrack,
  });

  final Color bgPage;
  final Color bgSurface;
  final Color bgSurfaceSunken;
  final Color bgCard;

  /// 设置页左侧竖向分类栏。
  final Color bgRail;

  /// 设置分类 tile（未选中）。
  final Color bgTile;

  /// 底部导航药丸容器。
  final Color bgDock;

  /// 搜索栏 / 输入框底。
  final Color bgInput;

  /// 迷你播放器控制按钮底。
  final Color bgControl;

  /// 封面占位、骨架屏。
  final Color bgPlaceholder;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentSoft;

  /// 强调色按下态。
  final Color accentPressed;

  /// 强调色底上的图标 / 文字。
  final Color onAccent;

  final Color iconPrimary;
  final Color iconInactive;
  final Color border;
  final Color divider;
  final Color danger;

  /// 错误提示浅底。
  final Color dangerSoft;

  final Color success;

  /// 警告 / 需要注意。
  final Color warning;

  /// 全屏遮罩（对话框 / 底部弹层）。
  final Color scrim;

  final Color progressTrack;

  /// 选中 Tab 文字 / 链接色（语义别名，等价于 [accent]）。
  Color get textAccent => accent;

  /// 选中态图标（语义别名，等价于 [accent]）。
  Color get iconActive => accent;

  /// 强调色圆底内的图标（语义别名，等价于 [onAccent]）。
  Color get iconOnAccent => onAccent;

  /// 强调色底上的文字（语义别名，等价于 [onAccent]）。
  Color get textOnAccent => onAccent;

  /// 毛玻璃半透明叠加色（[LiquidGlass] 默认 tint）。
  ///
  /// 跟随当前皮肤主色 [accent] 派生（不再写死白色），
  /// 深浅主题 + 6 套配色下毛玻璃质感自动同步。
  Color get glassTint => accent.withValues(alpha: 0.10);

  /// 毛玻璃描边色（[LiquidGlass] 默认 borderColor）。
  ///
  /// 跟随主题边框语义色 [border]，深浅主题下自动适配。
  Color get glassBorder => border.withValues(alpha: 0.6);

  /// 背景极光渐变（画布「清新·意境·浅色」观感）。
  ///
  /// 以主题底 [bgPage] 打底，叠皮肤主色 [accent] 派生的柔光，
  /// 深浅主题 + 11 套皮肤下背景氛围自动同步（不再写死粉/紫色），
  /// 与 LiquidGlass 的 glassTint/glassBorder 同源派生。
  LinearGradient get auroraGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          // R27 原生极简：极光降为「清淡氛围主题层」——柔光透明度整体减半，
          // 仅在背景边角留一点色温，不与前景内容争夺注意力。
          accent.withValues(alpha: 0.10),
          bgPage,
          accent.withValues(alpha: 0.07),
        ],
        stops: const <double>[0, 0.55, 1],
      );

  /// 浅色主题值（与 AppColors 一致）。
  static const AppThemeColors light = AppThemeColors(
    bgPage: AppColors.bgPage,
    bgSurface: AppColors.bgSurface,
    bgSurfaceSunken: AppColors.bgSurfaceSunken,
    bgCard: AppColors.bgCard,
    bgRail: AppColors.bgRail,
    bgTile: AppColors.bgTile,
    bgDock: AppColors.bgDock,
    bgInput: AppColors.bgInput,
    bgControl: AppColors.bgControl,
    bgPlaceholder: AppColors.bgPlaceholder,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    accent: AppColors.accent,
    accentSoft: AppColors.accentSoft,
    accentPressed: AppColors.accentPressed,
    onAccent: AppColors.onAccent,
    iconPrimary: AppColors.iconPrimary,
    iconInactive: AppColors.iconInactive,
    border: AppColors.borderDefault,
    divider: AppColors.divider,
    danger: AppColors.danger,
    dangerSoft: AppColors.dangerSoft,
    success: AppColors.success,
    warning: AppColors.warning,
    scrim: AppColors.scrim,
    progressTrack: AppColors.progressTrack,
  );

  /// 深色主题值（手调配色板，见 [AppDarkColors.palette]，不由浅色反推）。
  static const AppThemeColors dark = AppDarkColors.palette;

  /// 按皮肤主色重算强调色族（R16：皮肤切换全局生效）。
  ///
  /// 只覆盖 accent / accentSoft / accentPressed / onAccent 四个与品牌色
  /// 直接相关的槽位，中性色阶与状态色保持不变。
  AppThemeColors withSkin(Color primary, Brightness brightness) {
    final HSLColor hsl = HSLColor.fromColor(primary);
    final bool isDark = brightness == Brightness.dark;

    // 深色主题下把主色提亮，保证在深底上的可读性。
    final Color base = isDark
        ? hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor()
        : primary;

    return copyWith(
      accent: base,
      accentSoft: Color.alphaBlend(
        base.withValues(alpha: isDark ? 0.22 : 0.12),
        isDark ? AppDarkColors.surface : AppColors.neutral0,
      ),
      accentPressed: HSLColor.fromColor(base)
          .withLightness(
              (HSLColor.fromColor(base).lightness - 0.08).clamp(0.0, 1.0))
          .toColor(),
      onAccent: ThemeData.estimateBrightnessForColor(base) == Brightness.dark
          ? AppColors.neutral0
          : AppColors.textPrimary,
    );
  }

  @override
  AppThemeColors copyWith({
    Color? bgPage,
    Color? bgSurface,
    Color? bgSurfaceSunken,
    Color? bgCard,
    Color? bgRail,
    Color? bgTile,
    Color? bgDock,
    Color? bgInput,
    Color? bgControl,
    Color? bgPlaceholder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentSoft,
    Color? accentPressed,
    Color? onAccent,
    Color? iconPrimary,
    Color? iconInactive,
    Color? border,
    Color? divider,
    Color? danger,
    Color? dangerSoft,
    Color? success,
    Color? warning,
    Color? scrim,
    Color? progressTrack,
  }) {
    return AppThemeColors(
      bgPage: bgPage ?? this.bgPage,
      bgSurface: bgSurface ?? this.bgSurface,
      bgSurfaceSunken: bgSurfaceSunken ?? this.bgSurfaceSunken,
      bgCard: bgCard ?? this.bgCard,
      bgRail: bgRail ?? this.bgRail,
      bgTile: bgTile ?? this.bgTile,
      bgDock: bgDock ?? this.bgDock,
      bgInput: bgInput ?? this.bgInput,
      bgControl: bgControl ?? this.bgControl,
      bgPlaceholder: bgPlaceholder ?? this.bgPlaceholder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentPressed: accentPressed ?? this.accentPressed,
      onAccent: onAccent ?? this.onAccent,
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconInactive: iconInactive ?? this.iconInactive,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      scrim: scrim ?? this.scrim,
      progressTrack: progressTrack ?? this.progressTrack,
    );
  }

  @override
  AppThemeColors lerp(covariant AppThemeColors? other, double t) {
    if (other == null) return this;
    return AppThemeColors(
      bgPage: Color.lerp(bgPage, other.bgPage, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgSurfaceSunken: Color.lerp(bgSurfaceSunken, other.bgSurfaceSunken, t)!,
      bgCard: Color.lerp(bgCard, other.bgCard, t)!,
      bgRail: Color.lerp(bgRail, other.bgRail, t)!,
      bgTile: Color.lerp(bgTile, other.bgTile, t)!,
      bgDock: Color.lerp(bgDock, other.bgDock, t)!,
      bgInput: Color.lerp(bgInput, other.bgInput, t)!,
      bgControl: Color.lerp(bgControl, other.bgControl, t)!,
      bgPlaceholder: Color.lerp(bgPlaceholder, other.bgPlaceholder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      iconPrimary: Color.lerp(iconPrimary, other.iconPrimary, t)!,
      iconInactive: Color.lerp(iconInactive, other.iconInactive, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      progressTrack: Color.lerp(progressTrack, other.progressTrack, t)!,
    );
  }
}

/// 便捷取色：`context.appColors.bgPage`。
extension AppThemeColorsContext on BuildContext {
  AppThemeColors get appColors =>
      Theme.of(this).extension<AppThemeColors>() ?? AppThemeColors.light;

  /// 便捷取字：`context.appText.title`（在 [AppTextStyles] 基础上换成主题色）。
  AppTextTheme get appText => AppTextTheme(appColors);
}

/// ════════════════════════════════════════════════════════════════════════
/// 随主题取色的文字样式
/// ════════════════════════════════════════════════════════════════════════
///
/// [AppTextStyles] 是编译期常量，颜色写死为浅色值；深色主题下直接使用会
/// 出现「深底深字」。本类保持**字号 / 字重 / 行高完全不变**，只把 `color`
/// 换成 [AppThemeColors] 中对应的语义色。
///
/// 用法：`Text(x, style: context.appText.body)`。
@immutable
class AppTextTheme {
  const AppTextTheme(this.c);

  final AppThemeColors c;

  /// 18 / w600 · 页面与区块标题。
  TextStyle get title => AppTextStyles.title.copyWith(color: c.textPrimary);

  /// 16 / w600 · 区块小标题。
  TextStyle get subtitle =>
      AppTextStyles.subtitle.copyWith(color: c.textPrimary);

  /// 14 / w400 · 正文、设置项。
  TextStyle get body => AppTextStyles.body.copyWith(color: c.textPrimary);

  /// 14 / w400 / 次级色 · 说明性正文。
  TextStyle get bodyMuted =>
      AppTextStyles.bodyMuted.copyWith(color: c.textSecondary);

  /// 14 / w600 · 迷你播放器歌名、专辑卡曲名。
  TextStyle get trackName =>
      AppTextStyles.trackName.copyWith(color: c.textPrimary);

  /// 12 / w400 · 歌手名。
  TextStyle get artist => AppTextStyles.artist.copyWith(color: c.textTertiary);

  /// 11 / w400 · 时长、辅助信息。
  TextStyle get caption =>
      AppTextStyles.caption.copyWith(color: c.textTertiary);

  /// 10 / w500 · Dock Tab 文字标签。
  TextStyle get tabLabel =>
      AppTextStyles.tabLabel.copyWith(color: c.iconInactive);

  /// 9 / w400 · 设置分类 tile 文字。
  TextStyle get tileLabel =>
      AppTextStyles.tileLabel.copyWith(color: c.textSecondary);

  /// 14 / w400 / 占位色 · 搜索栏 hint。
  TextStyle get hint => AppTextStyles.hint.copyWith(color: c.textTertiary);

  /// 14 / w600 · 按钮文字。
  ///
  /// 刻意**不带 color**（同 [AppTextStyles.button]）：由各按钮主题的
  /// `foregroundColor` 决定，否则实心按钮会白底白字。
  TextStyle get button => AppTextStyles.button;
}
