import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../providers/voicehub/voicehub_provider.dart';
import '../../../services/voicehub/voicehub_models.dart';
import '../../../services/voicehub/voicehub_play.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_views.dart';

/// VoiceHub 校园广播站 —— 底部「校园电台」Tab。
///
/// 整页 WebView 嵌入真实的 VoiceHub 站点（[VoiceHubConfig.baseUrl]，默认
/// https://voicehub.245959623.xyz）。站点自身带登录界面与完整交互，App 只负责
/// 把整页页面显示出来，并可选地与原生播放器联动：
///
/// - 网页 → App：页面通过 JS 桥 `window.xingli.postMessage(JSON)` 调起播放/点歌。
///   为兼容站点已有的桥，我们在文档加载时注入 shim，把 `window.xingli.postMessage`
///   转发到 inappwebview 的 `callHandler('xingli')`。
/// - 链接拦截：`netease://` / `bilibili://` / `xingli://` 由 WebView 拦截后转交原生播放器。
///
/// 平台：flutter_inappwebview 单包覆盖 Android / iOS / macOS / Windows / Linux，
/// 全部走整页嵌入。Windows 需要系统已安装 Microsoft Edge WebView2 运行时
/// （Win11 自带；Win10 首次运行会自动拉取，或到微软官网安装）。
class VoiceHubPage extends ConsumerStatefulWidget {
  const VoiceHubPage({super.key});

  @override
  ConsumerState<VoiceHubPage> createState() => _VoiceHubPageState();
}

class _VoiceHubPageState extends ConsumerState<VoiceHubPage> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _cookieCtrl;

  InAppWebViewController? _controller;
  bool _webReady = false;
  String? _loadError;
  bool _showConfig = false;

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
    // 默认即嵌入站点（config.baseUrl 默认指向 voicehub.245959623.xyz）。
    _showConfig = !cfg.enabled;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _cookieCtrl.dispose();
    super.dispose();
  }

  /// 注入 shim：把站点已有的 `window.xingli.postMessage` 桥转发到 inappwebview。
  static const String _shimScript = '''
(function(){
  if(window.__xingliShimReady) return;
  window.__xingliShimReady = true;
  window.xingli = {
    postMessage: function(m){ try{ window.flutter_inappwebview.callHandler('xingli', m); }catch(e){} }
  };
  window.xingliPlay = function(p){ try{ window.xingli.postMessage(JSON.stringify(Object.assign({action:'play'}, p||{}))); }catch(e){} };
  window.xingliSubmit = function(p){ try{ window.xingli.postMessage(JSON.stringify(Object.assign({action:'submit'}, p||{}))); }catch(e){} };
})();
''';

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
        transparentBackground: true,
      );

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final VoiceHubState s = ref.watch(voiceHubProvider);

    return PageScaffold(
      title: '校园电台',
      actions: <Widget>[
        if (!_showConfig && s.config.enabled)
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _webReady = false);
              _controller?.reload();
            },
          ),
        IconButton(
          tooltip: _showConfig ? '返回网页' : '编辑地址',
          icon: Icon(_showConfig ? Icons.language : Icons.settings_outlined),
          onPressed: () => setState(() => _showConfig = !_showConfig),
        ),
        IconButton(
          tooltip: '在系统浏览器打开',
          icon: const Icon(Icons.open_in_browser_outlined),
          onPressed: () => _openExternal(s.config.baseUrl),
        ),
      ],
      body: (_showConfig || !s.config.enabled)
          ? _buildConfigCard(c)
          : _buildWebView(c),
    );
  }

  /// 配置卡：决定"嵌哪个网址"（默认已指向站点，正常不会看到本卡）。
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
                  hintText: 'API Key（开放接口使用，可留空）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _cookieCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  // 必须点明 auth-token：会话判定只认它（见
                  // VoiceHubClient.hasSessionCookie），粘别的 cookie 不算登录。
                  hintText:
                      '登录 cookie（需含 auth-token，登录后从浏览器复制）',
                  helperText: '形如 auth-token=eyJ…；缺少 auth-token 视为未登录',
                  helperMaxLines: 2,
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

  /// 整页 WebView 嵌入 + 双向联动桥（全平台：Android / iOS / macOS / Windows / Linux）。
  Widget _buildWebView(AppThemeColors c) {
    final String url = ref.watch(voiceHubProvider).config.baseUrl;
    return Stack(
      children: <Widget>[
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialSettings: _settings,
          onWebViewCreated: (InAppWebViewController controller) {
            _controller = controller;
            // 文档加载前注入 shim，把站点已有的 `window.xingli.postMessage` 桥转发过来。
            controller.addUserScript(userScript: UserScript(
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              source: _shimScript,
            ));
            // 网页 → App：站点 `window.xingli.postMessage(JSON)` 经 shim 转发到这里。
            controller.addJavaScriptHandler(
              handlerName: 'xingli',
              callback: (List<dynamic> args) {
                final String msg = args.isNotEmpty ? args.first.toString() : '';
                _onXingliMessage(msg);
              },
            );
          },
          onLoadStart: (_, __) => setState(() => _webReady = false),
          onLoadStop: (_, __) => setState(() => _webReady = true),
          onReceivedError:
              (_, WebResourceRequest req, WebResourceError error) {
            // 仅主框架出错才提示（子资源失败不阻断网页）。
            if (req.isForMainFrame == true) {
              setState(() => _loadError = error.description);
            }
          },
          shouldOverrideUrlLoading:
              (InAppWebViewController controller, NavigationAction navAction) async {
            final String url = navAction.request.url?.toString() ?? '';
            if (url.startsWith('netease://') ||
                url.startsWith('bilibili://') ||
                url.startsWith('xingli://')) {
              _handleSchemeUrl(url);
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
        ),
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

  /// 网页 → App：JS 桥消息（play / submit）。
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
  ///
  /// 判定逻辑抽到 [VoiceHubPlay.playSong]，与原生页共用一份（避免两处走偏）。
  Future<void> _playByFields({
    required String platform,
    required String id,
    String title = '',
    String artist = '',
    String coverUrl = '',
  }) async {
    if (!mounted) return;
    final String msg = await VoiceHubPlay.playSong(
      ref,
      platform: platform,
      musicId: id,
      title: title,
      artist: artist,
      coverUrl: coverUrl.isEmpty ? null : coverUrl,
    );
    if (!mounted) return;
    if (msg.isNotEmpty) {
      _toast(msg);
      return;
    }
    _pushNowPlaying(title: title, artist: artist, coverUrl: coverUrl);
  }

  /// 联动核心：把网页请求的点歌提交到 VoiceHub。
  ///
  /// `/api/open/songs/request` 用 API Key 归属的用户身份落库，**不需要 Cookie**，
  /// 因此不再像旧版那样先卡登录态。
  Future<void> _submitByFields({
    required String platform,
    required String musicId,
    required String title,
    required String artist,
    required String coverUrl,
  }) async {
    if (!mounted) return;
    if (title.isEmpty || artist.isEmpty) {
      _toast('缺少歌曲名或艺术家，无法投稿');
      return;
    }
    // B 站分 P：服务端会把 musicId 按 ':' 截断重建，cid/page 必须走独立字段。
    final VoiceHubBilibiliId bili = VoiceHubBilibiliId.parse(musicId);
    final int id = await ref.read(voiceHubProvider.notifier).submit(
          title: title,
          artist: artist,
          cover: coverUrl,
          musicPlatform: platform,
          musicId: bili.isEmpty ? musicId : bili.bvid,
          bilibiliCid: bili.cid.isEmpty ? null : bili.cid,
          bilibiliPage: bili.page.isEmpty ? null : bili.page,
        );
    if (!mounted) return;
    _toast(id > 0
        ? '已提交点歌：$title'
        : '点歌失败：${ref.read(voiceHubProvider).error}');
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
    try {
      await _controller?.evaluateJavascript(
          source: 'window.xingliState && window.xingliState($payload);');
    } catch (_) {}
  }

  Future<void> _save() async {
    final String url = _urlCtrl.text.trim();
    final VoiceHubConfig cfg = VoiceHubConfig(
      baseUrl: url,
      apiKey: _keyCtrl.text.trim(),
      cookie: _cookieCtrl.text,
    );
    await ref.read(voiceHubProvider.notifier).configure(cfg);
    if (!mounted) return;
    // 配置已落盘，这里只决定怎么说、以及要不要继续加载网页。
    // 无效 cookie 不阻止保存（用户可能只想先存 baseUrl / apiKey），
    // 但必须同时说清「已保存」和「缺 auth-token」，否则用户以为没存。
    if (cfg.hasInvalidCookie) {
      _toast('已保存；${cfg.loginPrompt}');
    } else {
      _toast(url.isEmpty ? '已清除 VoiceHub 配置' : '已保存并打开网页');
    }
    if (url.isNotEmpty) {
      // 保存后切到网页视图并加载新地址（网页版不依赖 auth-token，照常加载）。
      setState(() {
        _showConfig = false;
        _webReady = false;
        _loadError = null;
      });
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }
  }

  String _str(Object? v) => v == null ? '' : v.toString();

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openExternal(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      _toast('地址无效：$url');
      return;
    }
    // 用系统默认程序打开作为兜底（不引入 url_launcher：其 android 实现会拉
    // androidx.browser 1.9.0，要求 AGP 8.9.1+，与本项目固定 AGP 8.7.3 冲突）。
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
