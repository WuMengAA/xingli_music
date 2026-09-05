import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../models/track.dart';
import '../../../providers/audio/playback_notifier.dart';
import '../../../providers/sources/bilibili_provider.dart';
import '../../../providers/sources/netease_provider.dart';
import '../../../providers/voicehub/voicehub_provider.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_views.dart';

/// VoiceHub 校园广播站 —— 底部「校园电台」Tab。
///
/// 不是原生重写的列表页，而是**整页 WebView 嵌入真实的 VoiceHub 站点**
/// （[VoiceHubConfig.baseUrl]），并和 App 原生播放器**联动**：
///
/// - 网页 → App：页面通过 JS 桥 `window.xingli.postMessage(JSON)` 调起播放/点歌；
///   或点击 `netease://` / `bilibili://` / `xingli://` 链接，由 WebView 拦截后转交原生播放器。
/// - App → 网页：播放成功后向页面回推 `window.xingliState({...})`（页面可选监听）。
///
/// 联动协议（页面侧）：
/// ```js
/// xingli.postMessage(JSON.stringify({ action:'play', platform:'netease',
///   id:'123', title:'...', artist:'...', coverUrl:'...' }));
/// xingli.postMessage(JSON.stringify({ action:'submit', platform:'netease',
///   musicId:'123', title:'...', artist:'...', coverUrl:'...' }));
/// ```
/// 便捷封装（页面注入）：`window.xingliPlay({...})` / `window.xingliSubmit({...})`。
///
/// 平台支持：Flutter 官方 `webview_flutter` 4.14.1 仅声明 android / ios / macos
/// 实现，**Windows / Linux 无内置 WebView**。因此：
/// - 支持的平台：整页 WebView 嵌入 + 双向 JS 桥联动（如上）。
/// - 不支持的平台（Windows / Linux）：不构造 WebViewWidget（避免运行时崩溃），
///   改为「在系统浏览器打开校园电台」的 fallback 卡片。
class VoiceHubPage extends ConsumerStatefulWidget {
  const VoiceHubPage({super.key});

  @override
  ConsumerState<VoiceHubPage> createState() => _VoiceHubPageState();
}

class _VoiceHubPageState extends ConsumerState<VoiceHubPage> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _cookieCtrl;

  WebViewController? _controller;
  bool _webReady = false;
  String? _loadError;
  bool _showConfig = false;

  /// webview_flutter 4.14.1 仅官方支持 android / ios / macos，Windows/Linux 无实现。
  bool get _webSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _keyCtrl = TextEditingController();
    _cookieCtrl = TextEditingController();
    final VoiceHubConfig cfg = ref.read(voiceHubProvider).config;
    _urlCtrl.text = cfg.baseUrl;
    _keyCtrl.text = cfg.apiKey;
    _cookieCtrl.text = cfg.cookie;

    // Windows / Linux：官方 webview_flutter 无该平台实现，直接走 fallback。
    if (!_webSupported) {
      _showConfig = true;
      return;
    }

    _showConfig = !cfg.enabled;

    // 联动桥：一次性配置控制器（JS 模式 + 频道 + 导航拦截）。
    final WebViewController controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('xingli', onMessageReceived: _onXingli)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigate,
          onPageStarted: (_) => setState(() => _webReady = false),
          onPageFinished: (_) {
            setState(() => _webReady = true);
            _injectBridge();
          },
          onWebResourceError: (WebResourceError e) {
            // 仅主框架出错才提示（子资源失败不阻断网页）。
            if (e.isForMainFrame == true) {
              setState(() => _loadError = e.description);
            }
          },
        ),
      );
    _controller = controller;
    if (cfg.enabled) {
      controller.loadRequest(Uri.parse(cfg.baseUrl));
    }
  }

  /// 网页 → App：JS 桥消息（play / submit）。
  void _onXingli(JavaScriptMessage message) => _onXingliMessage(message.message);

  void _onXingliMessage(String message) {
    try {
      final Map<String, dynamic> p =
          Map<String, dynamic>.from(jsonDecode(message) as Map);
      final String action = (p['action'] ?? '').toString();
      if (action == 'play' || action == 'requestPlay') {
        _playByFields(
          platform: _str(p['platform']),
          id: _str(p['id']),
          title: _str(p['title']),
          artist: _str(p['artist']),
          coverUrl: _str(p['coverUrl']),
        );
      } else if (action == 'submit') {
        _submitByFields(
          platform: _str(p['platform']),
          musicId: _str(p['musicId']),
          title: _str(p['title']),
          artist: _str(p['artist']),
          coverUrl: _str(p['coverUrl']),
        );
      }
    } catch (_) {
      // 非 JSON / 未知消息：忽略，不中断 WebView。
    }
  }

  /// WebView 拦截 `netease://` / `bilibili://` / `xingli://` 链接 → 原生播放/点歌。
  NavigationDecision _onNavigate(NavigationRequest request) {
    final String url = request.url;
    if (url.startsWith('netease://') ||
        url.startsWith('bilibili://') ||
        url.startsWith('xingli://')) {
      _handleSchemeUrl(url);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  void _handleSchemeUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;
    if (uri.scheme == 'netease') {
      final String id = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      _playByFields(
        platform: 'netease',
        id: id,
        title: uri.queryParameters['title'] ?? '',
        artist: uri.queryParameters['artist'] ?? '',
        coverUrl: uri.queryParameters['coverUrl'] ?? '',
      );
    } else if (uri.scheme == 'bilibili') {
      final String id = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      _playByFields(
        platform: 'bilibili',
        id: id,
        title: uri.queryParameters['title'] ?? '',
        artist: uri.queryParameters['artist'] ?? '',
        coverUrl: uri.queryParameters['coverUrl'] ?? '',
      );
    } else if (uri.scheme == 'xingli') {
      if (uri.host == 'play') {
        _playByFields(
          platform: uri.queryParameters['platform'] ?? '',
          id: uri.queryParameters['id'] ?? '',
          title: uri.queryParameters['title'] ?? '',
          artist: uri.queryParameters['artist'] ?? '',
          coverUrl: uri.queryParameters['coverUrl'] ?? '',
        );
      } else if (uri.host == 'submit') {
        _submitByFields(
          platform: uri.queryParameters['platform'] ?? '',
          musicId: uri.queryParameters['id'] ?? uri.queryParameters['musicId'] ?? '',
          title: uri.queryParameters['title'] ?? '',
          artist: uri.queryParameters['artist'] ?? '',
          coverUrl: uri.queryParameters['coverUrl'] ?? '',
        );
      }
    }
  }

  /// 联动核心：把网页请求的曲目交给 App 原生播放器（网易云 / B站）。
  Future<void> _playByFields({
    required String platform,
    required String id,
    String title = '',
    String artist = '',
    String coverUrl = '',
  }) async {
    if (!mounted) return;
    final String p = platform.toLowerCase();
    if (p.contains('netease') && id.isNotEmpty) {
      if (!ref.read(neteaseAuthProvider).isLoggedIn) {
        _toast('播放网易云曲目需先登录网易云（设置 → 账号）');
        return;
      }
      final String msg = await ref.read(playbackActionsProvider).playTrack(
            Track(
              title: title,
              artist: artist,
              uri: 'netease://song/$id',
              source: TrackSource.stream,
              sourceId: 'netease',
              extras: <String, dynamic>{'coverUrl': coverUrl},
            ),
          );
      if (!mounted) return;
      if (msg.isNotEmpty) _toast(msg);
      _pushNowPlaying(title: title, artist: artist, coverUrl: coverUrl);
      return;
    }
    if (p.contains('bilibili') && id.isNotEmpty) {
      if (!ref.read(bilibiliAuthProvider).isLoggedIn) {
        _toast('播放 B站曲目需先登录哔哩哔哩（设置 → 账号）');
        return;
      }
      final String bvid = id.split(':').first;
      final String msg = await ref.read(playbackActionsProvider).playTrack(
            Track(
              title: title,
              artist: artist,
              uri: 'bilibili://video/$bvid',
              source: TrackSource.stream,
              sourceId: 'bilibili',
              extras: <String, dynamic>{'bvid': bvid, 'coverUrl': coverUrl},
            ),
          );
      if (!mounted) return;
      if (msg.isNotEmpty) _toast(msg);
      _pushNowPlaying(title: title, artist: artist, coverUrl: coverUrl);
      return;
    }
    _toast('暂不支持该平台播放（${platform.isEmpty ? '未知' : platform}）');
  }

  /// 联动核心：把网页请求的点歌提交到 VoiceHub（需登录 cookie）。
  Future<void> _submitByFields({
    required String platform,
    required String musicId,
    required String title,
    required String artist,
    required String coverUrl,
  }) async {
    if (!mounted) return;
    if (ref.read(voiceHubProvider).config.cookie.isEmpty) {
      _toast('点歌需先在配置卡填入 VoiceHub 登录 cookie');
      return;
    }
    final bool ok = await ref.read(voiceHubProvider.notifier).submitSong(
          title: title,
          artist: artist,
          coverUrl: coverUrl,
          musicPlatform: platform,
          musicId: musicId,
        );
    if (!mounted) return;
    _toast(ok ? '已提交点歌：$title' : '点歌失败：${ref.read(voiceHubProvider).error}');
  }

  /// App → 网页：回推当前播放状态（页面可选监听 `window.xingliState`）。
  Future<void> _pushNowPlaying({
    required String title,
    required String artist,
    required String coverUrl,
  }) async {
    final String payload = jsonEncode(<String, dynamic>{
      'title': title,
      'artist': artist,
      'coverUrl': coverUrl,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    // 忽略 runJavaScript 在页面未就绪时的异常。
    try {
      await _controller?.runJavaScript(
          'window.xingliState && window.xingliState($payload);');
    } catch (_) {}
  }

  /// 注入便捷封装：页面可调用 `window.xingliPlay` / `window.xingliSubmit`。
  void _injectBridge() {
    const String script = '''
(function(){
  if(window.__xingliBridgeReady) return;
  window.__xingliBridgeReady = true;
  window.xingliPlay = function(p){ try{ xingli.postMessage(JSON.stringify(Object.assign({action:'play'}, p||{})); }catch(e){} };
  window.xingliSubmit = function(p){ try{ xingli.postMessage(JSON.stringify(Object.assign({action:'submit'}, p||{})); }catch(e){} };
})();
''';
    _controller?.runJavaScript(script).catchError((_) {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _save() async {
    final String url = _urlCtrl.text.trim();
    await ref.read(voiceHubProvider.notifier).configure(
          VoiceHubConfig(
            baseUrl: url,
            apiKey: _keyCtrl.text.trim(),
            cookie: _cookieCtrl.text,
          ),
        );
    if (!mounted) return;
    _toast(url.isEmpty ? '已清除 VoiceHub 配置' : '已保存并打开网页');
    if (url.isNotEmpty) {
      // 保存后切到网页视图并加载新地址。
      setState(() {
        _showConfig = false;
        _webReady = false;
        _loadError = null;
      });
      _controller?.loadRequest(Uri.parse(url));
    }
  }

  String _str(Object? v) => v == null ? '' : v.toString();

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _cookieCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final VoiceHubState s = ref.watch(voiceHubProvider);

    return PageScaffold(
      title: '校园电台',
      actions: <Widget>[
        if (_webSupported && !_showConfig && s.config.enabled)
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _webReady = false);
              _controller?.reload();
            },
          ),
        if (_webSupported)
          IconButton(
            tooltip: _showConfig ? '返回网页' : '编辑地址',
            icon: Icon(_showConfig ? Icons.language : Icons.settings_outlined),
            onPressed: () => setState(() => _showConfig = !_showConfig),
          ),
      ],
      body: !_webSupported
          ? _buildWebFallback(c)
          : (_showConfig || !s.config.enabled
              ? _buildConfigCard(c)
              : _buildWebView(c)),
    );
  }

  /// 配置卡：决定"嵌哪个网址"。保留，因 WebView 必须知道 baseUrl。
  Widget _buildConfigCard(AppThemeColors c) {
    final bool enabled = ref.watch(voiceHubProvider).config.enabled;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('VoiceHub 服务器（嵌入的整个网页地址）',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary)),
              const SizedBox(height: 6),
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  hintText: 'https://voicehub.245959623.xyz',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _keyCtrl,
                decoration: const InputDecoration(
                  hintText: 'API Key（开放接口使用）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _cookieCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: '登录 cookie（点歌提交用，浏览器登录后复制）',
                  isDense: true,
                  prefixIcon: Icon(Icons.lock_outline, size: 16),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.cloud_sync_outlined, size: 16),
                      label: const Text('保存并打开网页'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          enabled
              ? '已启用：点击右上「返回网页」查看嵌入的 VoiceHub 站点。'
              : '填入服务器地址后点「保存并打开网页」，即可整页嵌入校园电台。',
          style: TextStyle(color: c.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  /// 整页 WebView 嵌入 + 双向联动桥（仅 android / ios / macos 调用）。
  Widget _buildWebView(AppThemeColors c) {
    return Stack(
      children: <Widget>[
        WebViewWidget(controller: _controller!),
        if (!_webReady && _loadError == null)
          const Positioned.fill(
            child: LoadingView(label: '加载校园电台网页中…'),
          ),
        if (_loadError != null)
          Positioned.fill(
            child: ErrorView(
              message: _loadError!,
              onRetry: () {
                setState(() => _loadError = null);
                _controller?.reload();
              },
            ),
          ),
      ],
    );
  }

  /// Windows / Linux fallback：官方 webview_flutter 无该平台实现，
  /// 改为在系统浏览器打开校园电台站点（无法与原生播放器联动）。
  Widget _buildWebFallback(AppThemeColors c) {
    final String url = ref.watch(voiceHubProvider).config.baseUrl;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('校园电台（系统浏览器打开）',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary)),
              const SizedBox(height: 8),
              Text(
                '当前 Windows / Linux 客户端暂无内置网页视图（Flutter 官方 '
                'webview_flutter 未提供该平台实现）。点击下方按钮在系统浏览器打开'
                '校园电台站点。整页嵌入与播放联动已在 Android / iOS 端上线。',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              if (url.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _openExternal(url),
                  icon: const Icon(Icons.open_in_browser_outlined, size: 16),
                  label: const Text('在系统浏览器打开校园电台'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openExternal(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      _toast('地址无效：$url');
      return;
    }
    // 用系统默认程序打开（Windows/Linux 无内置 WebView，fallback 走系统浏览器）。
    // 不引入 url_launcher：其 android 实现会拉 androidx.browser 1.9.0，要求 AGP
    // 8.9.1+，与本项目固定 AGP 8.7.3 冲突，导致 Android 构建失败。
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', <String>['/c', 'start', '', uri.toString()]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', <String>[uri.toString()]);
      } else if (Platform.isMacOS) {
        await Process.run('open', <String>[uri.toString()]);
      } else {
        _toast('当前平台暂不支持直接打开浏览器');
        return;
      }
    } catch (e) {
      _toast('打开失败：$e');
    }
  }
}
