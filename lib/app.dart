import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart' as asvc;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

import 'app_shell.dart';
import 'core/theme/app_theme_colors.dart';
import 'core/theme/light_theme.dart';
import 'core/theme/light_tokens.dart';
import 'providers/settings/performance_providers.dart';
import 'providers/audio/audio_providers.dart';
import 'providers/settings/log_upload_providers.dart';
import 'providers/settings/notification_providers.dart';
import 'providers/audio/auto_play_providers.dart';
import 'providers/stats/track_stats_providers.dart';
import 'providers/theme/theme_providers.dart';
import 'providers/ui/locale_provider.dart';
import 'services/audio/audio_handler.dart';
import 'services/audio/audio_service.dart';
import 'services/log_service.dart';
import 'services/permission_service.dart';

/// 全局滚动行为：让页面滑动有「缓冲、平滑」的手感。
///
/// 为什么单独抽一个 ScrollBehavior 包在 MaterialApp 外层：
/// 1) 应用是扁平抽象风格，Android 默认的 overscroll 高亮/拉伸（M3 是 stretch、
///    M2 是 glow）视觉很突兀，这里统一关掉 overscroll 指示器 —— 返回 child 即
///    完全不画指示器。注意：iOS 的弹性来自 BouncingScrollPhysics 而非指示器
///    widget，所以关掉指示器不影响 iOS 的回弹手感。
/// 2) 不同平台给不同的 physics：触摸（Android）用 Clamping 保持扁平、到边即停；
///    桌面（Windows/Linux）用 Bouncing + 快速减速，让拖拽有缓冲惯性、松手后
///    coast 更顺，整体更「跟手、不硬跳」。
/// 3) 该 behavior 通过 ScrollConfiguration 自动下发给所有 Scrollable（包括
///    PageView / NestedScrollView / ListView），PageView 会把它当成
///    PageScrollPhysics 的父级，分页吸附逻辑不受影响。
class BufferedScrollBehavior extends ScrollBehavior {
  const BufferedScrollBehavior();

  /// 关掉 Android 的 overscroll 高亮/拉伸指示器（其余平台本来就不画）。
  /// 只影响「视觉指示器」，不改变 bounce 物理，也不影响下拉刷新所需的 overscroll。
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  /// 按平台调校默认滚动物理，让触摸和桌面都「有惯性、不硬跳」。
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        // 苹果平台保留原生弹性 + 快速减速，手感最跟手。
        return const BouncingScrollPhysics(
          decelerationRate: ScrollDecelerationRate.fast,
          parent: RangeMaintainingScrollPhysics(),
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        // 触摸平台用 Clamping：到边界就停、不回弹，符合扁平抽象风格；
        // 触摸拖拽本身由系统提供惯性，无需额外 bounce。
        return const ClampingScrollPhysics(
          parent: RangeMaintainingScrollPhysics(),
        );
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        // 桌面端鼠标滚轮/触控板：Bouncing + 快速减速让拖拽有缓冲惯性，
        // 列表到头时轻微回弹而非生硬停住，整体更平滑一致。
        return const BouncingScrollPhysics(
          decelerationRate: ScrollDecelerationRate.fast,
          parent: RangeMaintainingScrollPhysics(),
        );
    }
  }
}

/// 星璃 · 无限音乐空间 —— 应用根组件
class StelarithMusicApp extends ConsumerStatefulWidget {
  const StelarithMusicApp({super.key});

  @override
  ConsumerState<StelarithMusicApp> createState() => _StelarithMusicAppState();
}

class _StelarithMusicAppState extends ConsumerState<StelarithMusicApp> {
  bool _audioInit = false;

  /// 根导航键：桌面端 Esc 关闭路由用（桌面没有系统返回键）。
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // 启动时初始化自动日志
    unawaited(LogService.instance.init());
    LogService.instance.i('app', '应用启动');
    _initAudio();
    // R13：启动即请求通知权限（Android 13+ 必须，否则通知栏不显示）
    unawaited(PermissionService.requestEssentialOnStartup());
  }

  /// 初始化音频基础设施：
  /// 1) 音频焦点（audio_session）—— 来电/其它应用抢声时优雅 duck 或暂停
  /// 2) 后台播放 + 锁屏/通知栏控件（audio_service）
  Future<void> _initAudio() async {
    if (_audioInit) return;
    _audioInit = true;

    final AudioService audio = ref.read(audioServiceProvider);

    // ── 1) 音频焦点 / 打断处理 ──
    try {
      final AudioSession session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // 被其它应用打断：duck 时压低音量，pause 时暂停（打断结束不自动外放）
      session.interruptionEventStream.listen((AudioInterruptionEvent e) {
        if (e.begin) {
          switch (e.type) {
            case AudioInterruptionType.duck:
              unawaited(audio.setDuck(true));
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              unawaited(audio.pauseOnly());
              break;
          }
        } else {
          if (e.type == AudioInterruptionType.duck) {
            unawaited(audio.setDuck(false));
          }
        }
      });

      // 耳机/蓝牙断开：暂停，避免外放
      session.becomingNoisyEventStream
          .listen((_) => unawaited(audio.pauseOnly()));
    } catch (e) {
      LogService.instance.e('app', '音频焦点配置失败: $e');
    }

    // ── 2) 后台播放 + 锁屏/通知栏控件 ──
    // 由「后台播放」开关控制：关闭时不注册后台媒体服务（无通知栏常驻、
    // 无前台服务，切后台可能被系统回收播放）—— 省电 / 低端设备推荐。
    if (ref.read(backgroundPlayProvider)) {
      try {
        await asvc.AudioService.init(
          config: const asvc.AudioServiceConfig(
            androidNotificationChannelId: 'com.stelarith.xingli_music.audio',
            androidNotificationChannelName: '星璃音乐',
            androidNotificationChannelDescription: '播放控制（静默通知）',
            androidNotificationIcon: 'drawable/ic_notification',
            // P0-A5 / 约定 C5：通知栏强调色统一为新品牌紫 #7C6BFF
            notificationColor: AppColors.accent,
            androidShowNotificationBadge: true,
            // R14：通知栏静默常驻 —— 播放中常驻通知（ongoing），
            // 暂停时停前台服务但保留通知（audio_service 约束：ongoing 需
            // stopForegroundOnPause=true，通知在暂停后以普通通知保留）。
            androidNotificationOngoing: true,
            androidStopForegroundOnPause: true,
          ),
          builder: () =>
              StelarithAudioHandler(ref.read(playbackControllerProvider)),
        );
      } catch (e) {
        LogService.instance.e('app', '音频服务初始化失败: $e');
      }
    } else {
      LogService.instance.i('app', '后台播放已关闭，跳过后台媒体服务注册');
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── 云端日志上报器：watch 保持存活并挂到 LogService（默认关闭）────
    ref.watch(remoteLogUploaderProvider);

    // ── cl46 全局播放统计跟踪器：watch 保持存活，自动记录听歌时长/次数 ──
    ref.watch(trackStatsTrackerProvider);

    // ── cl46 自动播放 / 自动过渡：watch 保持存活，曲毕自动切歌 ──
    ref.watch(autoPlayTrackerProvider);

    // ── R16 主题系统：浅色 / 深色 / 跟随系统 + 皮肤主色 ──────
    // 浅色主题由 kLightTheme（品牌紫）与皮肤主色叠加；
    // 深色主题由 buildDarkTheme(皮肤主色) 构建；themeMode 跟随 provider。
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final Color skinPrimary = ref.watch(themeSkinColorProvider);
    // R26skel-b3：全局 UI 大小（整体界面缩放，0.8~1.2 滑杆；替代旧
    // 「紧凑密度」的写死 0.88——uiDensity 现在只管 Dock 紧凑）。
    final double uiScale = ref.watch(uiScaleProvider);

    return ExcludeSemantics(
      // Windows 稳定性（R20 根治）：Flutter Windows 引擎 accessibility_bridge
      // 语义树更新时遇内部空指针崩溃（flutter_windows.dll+0x3A9FA，页面切换
      // 触发；3.44 引擎已移除 FLUTTER_A11Y 环境变量，只能从 Dart 层禁语义树）。
      // 语义树为空 → 桥接事件循环无节点 → 崩溃路径不存在。
      // 代价：Windows 屏幕阅读器读不到控件；Android 不受影响（条件包裹）。
      excluding: !kIsWeb && Platform.isWindows,
      // R-scroll：全局滚动行为（overscroll 关高亮 + 分平台 physics），
      // 见 BufferedScrollBehavior 的注释。
      child: ScrollConfiguration(
        behavior: const BufferedScrollBehavior(),
        child: MaterialApp(
      onGenerateTitle: (BuildContext context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      // cl07 i18n：语言 provider 驱动（中文/英文），即时生效 + 持久化。
      locale: ref.watch(localeProvider),
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // R22：全局 UI 大小 → 全局 MediaQuery 缩放（布局尺寸 + 文字 + 四边
      // 安全区一起按系数缩放，腾出有效空间；基于逻辑像素，DPI 自适应）。
      builder: (BuildContext context, Widget? child) {
        Widget base = CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () {
              _navKey.currentState?.maybePop();
            },
          },
          child: child ?? const SizedBox.shrink(),
        );
        final double k = uiScale; // 全局 UI 缩放系数（1.0 = 原尺寸）
        if (k != 1.0) {
          final MediaQueryData mq = MediaQuery.of(context);
          EdgeInsets scaleEdge(EdgeInsets e) => EdgeInsets.fromLTRB(
                e.left * k, e.top * k, e.right * k, e.bottom * k);
          // TextScaler.scale 返回 double（当前字号比例），叠加紧凑系数后
          // 用 linear 重建缩放器。
          final double baseScale = mq.textScaler.scale(1.0);
          base = MediaQuery(
            data: mq.copyWith(
              size: Size(mq.size.width * k, mq.size.height * k),
              textScaler: TextScaler.linear(baseScale * k),
              padding: scaleEdge(mq.padding),
              viewInsets: scaleEdge(mq.viewInsets),
              viewPadding: scaleEdge(mq.viewPadding),
            ),
            child: base,
          );
        }
        return base;
      },
      theme: kLightTheme.copyWith(
        colorScheme: kLightColorScheme.copyWith(
          primary: skinPrimary,
          secondary: skinPrimary,
          tertiary: skinPrimary,
          primaryContainer: skinPrimary.withValues(alpha: 0.12),
          onPrimaryContainer: skinPrimary,
          inversePrimary: skinPrimary.withValues(alpha: 0.35),
        ),
        // R16：语义色扩展同步皮肤主色，`context.appColors.accent` 才会跟着变。
        extensions: <ThemeExtension<dynamic>>[
          AppThemeColors.light.withSkin(skinPrimary, Brightness.light),
        ],
      ),
      darkTheme: buildDarkTheme(skinPrimary),
      themeMode: themeMode,
      // cl07：主题/皮肤/明暗切换平滑过渡（不再硬跳）。
      themeAnimationDuration: const Duration(milliseconds: 400),
      themeAnimationCurve: Curves.easeOutCubic,
      home: const AppShell(),
      ),
        ),
    );
  }
}
