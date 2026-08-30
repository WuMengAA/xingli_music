/// liquid_glass_compat —— 液态玻璃 Flutter 适配包
///
/// 移植自 martin65536/liquid-glass-webgl（WebGL 版）与
/// Kyant0/AndroidLiquidGlass（Android 原版）。
library;

export 'src/core/continuous_curve.dart'
    show ContinuousCurvatureRoundedRectangleCornerBuilder, continuousCurvatureRoundedRectPath;
export 'src/core/continuous_sdf.dart'
    show
        SdfTexture,
        chamferSignedDistanceField,
        generateContinuousCurvatureSdf,
        sdfToRgba8,
        clearSdfCache;
export 'src/core/palette.dart'
    show
        GlassPalette,
        GlassThemeMode,
        glassPaletteFor,
        lightGlassPalette,
        darkGlassPalette,
        lerpColor;
export 'src/core/performance.dart'
    show
        GlassPerformancePreset,
        GlassPerformanceSettings,
        settingsFor,
        kDefaultPerformancePreset;
export 'src/core/spring.dart'
    show
        Spring1D,
        SpringCritical1D,
        springStepCritical,
        springStepUnderdamped,
        kSpringThreshold,
        kSpringK,
        kToggleValueK,
        kToggleValueOmegaN,
        kLgDp;
export 'src/widgets/glass_surface.dart' show GlassSurface, GlassVisuals;
export 'src/widgets/glass_card.dart' show GlassCard;
export 'src/widgets/glass_button.dart' show GlassButton;
export 'src/widgets/glass_toggle.dart' show GlassToggle;
export 'src/widgets/glass_slider.dart' show GlassSlider;
export 'src/widgets/glass_dialog.dart' show GlassDialog, GlassDialogAction, showGlassDialog;
export 'src/widgets/glass_dock.dart' show GlassDock, GlassDockItem;
export 'src/widgets/glass_scroll_container.dart'
    show GlassScrollContainer, GlassLazyScrollContainer;
export 'src/widgets/glass_progressive_blur.dart' show GlassProgressiveBlur;
export 'src/widgets/adaptive_luminance_glass.dart' show AdaptiveLuminanceGlass;