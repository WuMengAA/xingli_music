import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart' as asvc;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'services/audio/audio_handler.dart';
import 'services/audio/audio_service.dart';
import 'services/log_service.dart';
import 'services/permission_service.dart';

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
      child: MaterialApp(
      title: '星璃 · 无限音乐空间',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
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
      home: const AppShell(),
      ),
    );
  }
}
