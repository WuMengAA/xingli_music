import 'dart:async';

import 'package:audio_service/audio_service.dart' as asvc;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'core/theme/light_theme.dart';
import 'core/theme/light_tokens.dart';
import 'providers/audio/audio_providers.dart';
import 'services/audio/audio_handler.dart';
import 'services/audio/audio_service.dart';
import 'services/log_service.dart';

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
    try {
      await asvc.AudioService.init(
        config: const asvc.AudioServiceConfig(
          androidNotificationChannelId: 'com.stelarith.xingli_music.audio',
          androidNotificationChannelName: '星璃音乐',
          androidNotificationIcon: 'drawable/ic_notification',
          // P0-A5 / 约定 C5：通知栏强调色统一为新品牌紫 #7C6BFF
          notificationColor: AppColors.accent,
          androidShowNotificationBadge: true,
          androidStopForegroundOnPause: true,
        ),
        builder: () =>
            StelarithAudioHandler(ref.read(playbackControllerProvider)),
      );
    } catch (e) {
      LogService.instance.e('app', '音频服务初始化失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── 主题脱离 Provider（P0-A2 / 约定 C3）──────────────────────────
    // 旧实现：theme = buildAppTheme(ref.watch(effectivePrimaryProvider))，
    //         调色盘一动就重建整棵树，且色值不可预期。
    // 新实现：顶层不可变 kLightTheme 一次性构建，themeMode 固定 light；
    //         用户主色只在 CanvasPage「暗色孤岛」内局部覆盖。
    //         darkTheme 同值兜底，防止系统深色设置意外击穿浅色体系。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kLightOverlayStyle,
      child: MaterialApp(
        title: '星璃 · 无限音乐空间',
        debugShowCheckedModeBanner: false,
        theme: kLightTheme,
        darkTheme: kLightTheme,
        themeMode: ThemeMode.light,
        home: const AppShell(),
      ),
    );
  }
}
