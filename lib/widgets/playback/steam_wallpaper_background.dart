/// ════════════════════════════════════════════════════════════════════════
/// 主页沉浸播放器 · Steam 壁纸背景（Wallpaper Engine `web` 类型）
/// ════════════════════════════════════════════════════════════════════════
///
/// 作为主页 [Stack] 的最底层背景（当选中某个 Steam 壁纸主题时）。
/// 实现要点：
/// ① 用 [LocalWallpaperServer] 把壁纸目录暴露成 `http://127.0.0.1:<port>/`，
///    再经 [InAppWebView] 加载（规避 file:// 下 ES Module 的 CORS 限制）；
/// ② 每 ~50ms 把 App 真实音频频段（[visualizerBandsProvider]，16 段）上采样
///    到 256 浮点，调用壁纸的 `window.wallpaperAudioListener(arr)`，
///    让 WebGL 场景随当前播放的音乐反应；
/// ③ 加载完成后隐藏壁纸自带的播放器浮动面板（App 自己有控制栏），
///    并把当前曲目名/歌手推给壁纸的专辑封面特性。

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/visualizer_providers.dart';
import '../../providers/home/player_theme_provider.dart';
import '../../services/wallpaper/local_wallpaper_server.dart';

/// 壁纸效果默认值来自 [kDefaultWallpaperEffects]（定义在 player_theme_provider，
/// 与 App 内「效果」滑杆共享同一张表）。加载时用同目录 `effects.json` 覆盖。

/// 主页最底层背景：Steam 壁纸（WebGL 音频反应），静音、不交互。
class SteamWallpaperBackground extends ConsumerStatefulWidget {
  const SteamWallpaperBackground({super.key, required this.wallpaper});

  final ImportedWallpaper wallpaper;

  @override
  ConsumerState<SteamWallpaperBackground> createState() =>
      _SteamWallpaperBackgroundState();
}

class _SteamWallpaperBackgroundState
    extends ConsumerState<SteamWallpaperBackground> {
  LocalWallpaperServer? _server;
  InAppWebViewController? _ctrl;
  List<double> _bands = List<double>.filled(16, 0.0);
  Timer? _bridge;

  @override
  void initState() {
    super.initState();
    _bands = ref.read(visualizerBandsProvider).valueOrNull ??
        List<double>.filled(16, 0.0);
    // 实时跟随 App 音频频段
    ref.listen<AsyncValue<List<double>>>(
      visualizerBandsProvider,
      (_, AsyncValue<List<double>> next) {
        if (next.hasValue) _bands = next.value!;
      },
    );
    // 曲目变化推送专辑信息
    ref.listen<Track?>(
      nowPlayingProvider,
      (_, Track? t) {
        if (mounted) _pushTrack(t);
      },
    );
    // 壁纸「效果配置」实时表：滑杆改动即时注入，无需重载页面
    ref.listen<Map<String, dynamic>>(
      wallpaperEffectsProvider,
      (_, Map<String, dynamic> next) {
        if (mounted) _applyEffects(next);
      },
    );
    _start();
  }

  Future<void> _start() async {
    if (!widget.wallpaper.exists) return;
    _server = widget.wallpaper.bundled
        ? LocalWallpaperServer.asset(widget.wallpaper.assetBase!)
        : LocalWallpaperServer.folder(widget.wallpaper.folderPath!);
    await _server!.start();
    if (!mounted) {
      _server!.dispose();
      return;
    }
    _bridge = Timer.periodic(const Duration(milliseconds: 50), _pushAudio);
    // 端口已确定，触发重建以挂载 WebView
    if (mounted) setState(() {});
  }

  /// 每帧把当前频段喂给壁纸的音频监听入口。
  void _pushAudio(Timer _) {
    final InAppWebViewController? c = _ctrl;
    if (c == null) return;
    final List<double> arr = _upsample(_bands, 256);
    final String js =
        'window.wallpaperAudioListener && window.wallpaperAudioListener'
        '(${jsonEncode(arr)})';
    c.evaluateJavascript(source: js).catchError((_) {});
  }

  /// 加载效果配置：内置默认值，叠加同目录 `effects.json`（打包资源走
  /// rootBundle，本机目录走文件）的覆盖；始终强制隐藏壁纸自带播放器面板。
  Future<Map<String, dynamic>> _loadEffects() async {
    final Map<String, dynamic> merged =
        <String, dynamic>{...kDefaultWallpaperEffects};
    try {
      String? raw;
      if (widget.wallpaper.bundled) {
        final ByteData data =
            await rootBundle.load('${widget.wallpaper.assetBase}/effects.json');
        raw = String.fromCharCodes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } else {
        final File f = File('${widget.wallpaper.folderPath}/effects.json');
        if (f.existsSync()) raw = f.readAsStringSync();
      }
      if (raw != null && raw.trim().isNotEmpty) {
        final Map<String, dynamic> override =
            jsonDecode(raw) as Map<String, dynamic>;
        merged.addAll(override);
      }
    } catch (_) {
      // 配置缺失/损坏则用默认值，不影响壁纸加载
    }
    merged['showPlayerController'] = false;
    return merged;
  }

  /// 把当前曲目信息推给壁纸的 Media Integration（标题/歌手/播放态）。
  void _pushTrack(Track? t) {
    final InAppWebViewController? c = _ctrl;
    if (c == null) return;
    final String title = (t?.title ?? '').replaceAll("'", r"\'");
    final String artist = (t?.artist ?? '').replaceAll("'", r"\'");
    final String js = "window.__mediaState && (window.__mediaState.title='$title',"
        "window.__mediaState.artist='$artist',"
        "window.__mediaState.isPlaying=true,"
        "window.__notifyMediaChange && window.__notifyMediaChange())";
    c.evaluateJavascript(source: js).catchError((_) {});
  }

  /// 把效果配置实时注入壁纸（Wallpaper Engine `applyUserProperties`）。
  /// 滑杆改动、主题切换加载完成时都会调用；页面无需重载。
  Future<void> _applyEffects(Map<String, dynamic> effects) async {
    final InAppWebViewController? c = _ctrl;
    if (c == null) return;
    await c
        .evaluateJavascript(
          source: 'window.wallpaperPropertyListener && '
              'window.wallpaperPropertyListener'
              '.applyUserProperties(${jsonEncode(effects)})',
        )
        .catchError((_) {});
  }

  /// 把 [src]（长度 m）线性上采样到长度 [n]（保留低重高衰的形态）。
  static List<double> _upsample(List<double> src, int n) {
    if (src.isEmpty) return List<double>.filled(n, 0.0);
    final List<double> out = List<double>.filled(n, 0.0);
    final int m = src.length;
    if (m == 1) {
      for (int i = 0; i < n; i++) out[i] = src[0];
      return out;
    }
    for (int i = 0; i < n; i++) {
      final double x = i * (m - 1) / (n - 1);
      final int lo = x.floor();
      final int hi = (lo + 1).clamp(0, m - 1);
      final double f = x - lo;
      out[i] = src[lo] * (1 - f) + src[hi] * f;
    }
    return out;
  }

  @override
  void dispose() {
    _bridge?.cancel();
    _server?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_server == null || _server!.port == null) {
      // 服务未就绪或目录失效：先占位，启动后由 setState 重建挂载 WebView
      return const SizedBox.shrink();
    }
    final String url = 'http://127.0.0.1:${_server!.port}/';
    return InAppWebView(
      key: ValueKey<String>(url),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        // 允许静音自动播放（壁纸本就静音，仅做视觉）
        mediaPlaybackRequiresUserGesture: false,
        transparentBackground: true,
      ),
      onWebViewCreated: (InAppWebViewController c) => _ctrl = c,
      onLoadStop: (InAppWebViewController c, Uri? uri) async {
        _ctrl = c;
        // 加载效果配置（effects.json 覆盖默认值，并强制隐藏壁纸自带播放器），
        // 同步到全局效果表（让 App 内滑杆显示当前壁纸的真实初始值），再注入。
        final Map<String, dynamic> effects = await _loadEffects();
        ref.read(wallpaperEffectsProvider.notifier).state = effects;
        await _applyEffects(effects);
        _pushTrack(ref.read(nowPlayingProvider));
      },
    );
  }
}
