import 'dart:async';

import 'package:audio_service/audio_service.dart' as asvc;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'core/theme/app_theme_colors.dart';
import 'core/theme/light_theme.dart';
import 'core/theme/light_tokens.dart';
import 'providers/audio/audio_providers.dart';
import 'providers/settings/notification_providers.dart';
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
    // ── R16 主题系统：浅色 / 深色 / 跟随系统 + 皮肤主色 ──────
    // 浅色主题由 kLightTheme（品牌紫）与皮肤主色叠加；
    // 深色主题由 buildDarkTheme(皮肤主色) 构建；themeMode 跟随 provider。
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final Color skinPrimary = ref.watch(themeSkinColorProvider);

    return MaterialApp(
      title: '星璃 · 无限音乐空间',
      debugShowCheckedModeBanner: false,
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
    );
  }
}
