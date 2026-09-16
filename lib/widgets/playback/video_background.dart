/// ════════════════════════════════════════════════════════════════════════
/// 主页沉浸播放器 · Bilibili 视频背景（最底层）
/// ════════════════════════════════════════════════════════════════════════
///
/// 作为主页 [Stack] 的第一个子节点，位于 [ImmersiveBackground] 之下；
/// 因 [ImmersiveBackground] 使用 `videoThrough: true` 半透明，本层视频会
/// 透出，再叠加模糊形成沉浸式氛围背景。
///
/// 设计约束（来自需求）：
/// ① 用 [flutter_inappwebview]（而非 webview_flutter，后者不支持 Windows）；
/// ② 纯背景：永远静音、不交互、隐藏 B 站全部控件 / 弹幕 / header；
/// ③ 模糊强度由 provider 控制；关闭开关时直接返回空。

library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/home/home_video_provider.dart';

/// 主页最底层背景：Bilibili 视频背景（静音自动播放 + 可调模糊）。
class VideoBackground extends ConsumerWidget {
  const VideoBackground({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool enabled = ref.watch(homeVideoEnabledProvider);
    if (!enabled) return const SizedBox.shrink();

    final double blur = ref.watch(homeVideoBlurProvider);
    final String bvid = ref.watch(homeVideoBvProvider);

    // 用 player.bilibili.com 的轻量播放器页（比 www 主站更干净、易静音隐藏 UI）。
    final String url =
        'https://player.bilibili.com/player.html?bvid=$bvid&autoplay=1'
        '&mute=1&high_quality=1&danmaku=0&showinfo=0';

    // key 用 URL：BV 变化时强制重建 WebView 以重新加载。
    final InAppWebView webView = InAppWebView(
      key: ValueKey<String>(url),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        // 关掉「需用户手势才能播放」，允许静音自动播放。
        mediaPlaybackRequiresUserGesture: false,
        // 透明背景，让下层 / 模糊后的观感更统一。
        transparentBackground: true,
      ),
      onLoadStop: (InAppWebViewController controller, Uri? uri) async {
        await _muteAndHideUi(controller);
      },
    );

    // blur <= 0：不做模糊，直接展示原画面（仍静音）。
    if (blur <= 0) return webView;

    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: webView,
    );
  }

  /// 页面加载完成后：强制静音并播放，注入 CSS 隐藏 B 站全部 UI。
  Future<void> _muteAndHideUi(InAppWebViewController controller) async {
    const String script = r'''
      (function () {
        try {
          var v = document.querySelector('video');
          if (v) {
            v.muted = true;
            v.volume = 0;
            v.setAttribute('muted', '');
            var p = v.play();
            if (p && p.catch) { p.catch(function () {}); }
          }
          var s = document.createElement('style');
          s.textContent = [
            'html, body { background: transparent !important; margin: 0; padding: 0; overflow: hidden; }',
            '.bilibili-player { background: transparent !important; }',
            '.bilibili-player-video-control-wrap { display: none !important; }',
            '.bilibili-player-video-top-wrap { display: none !important; }',
            '.bilibili-player-video-bottom-wrap { display: none !important; }',
            '.bilibili-player-controller { display: none !important; }',
            '.bilibili-player-video-danmaku { display: none !important; }',
            '.bilibili-player-video-danmaku-wrap { display: none !important; }',
            '.bilibili-player-video-sendbar { display: none !important; }',
            '.bilibili-player-video-top { display: none !important; }',
            '.bilibili-player-video-btn { display: none !important; }',
            '.bilibili-player-video-state { display: none !important; }',
            '.bilibili-player-video-toast-wrap { display: none !important; }',
            '.bilibili-player-ending-panel { display: none !important; }',
            '.bilibili-player-pgc-ending-wrap { display: none !important; }'
          ].join('\n');
          (document.head || document.documentElement).appendChild(s);
        } catch (e) {}
      })();
    ''';
    try {
      await controller.evaluateJavascript(source: script);
    } catch (_) {
      // 背景容错：注入失败也不影响上层 UI。
    }
  }
}
