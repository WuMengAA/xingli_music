/// 哔哩哔哩登录底部弹层（内嵌网页登录 + 粘贴 cookie；2026-08-17 与网易云对齐）。
///
/// 双路径：
/// - **网页登录**（默认）：Android 拉起原生 [CookieWebViewActivity]
///   （bilibili 类型）内嵌 B站官方桌面登录页，登录后原生层自动抓取完整 cookie
///   （含 httpOnly SESSDATA）→ 加密落盘。无依赖、**不弹外部浏览器**、不手动复制。
/// - **粘贴 Cookie**：手动粘贴 `SESSDATA=...; bili_jct=...; DedeUserID=...`，
///   [loginWithCookie] 校验并加密落盘（Windows / 其它平台的主要路径）。
///
/// cookie 加密落盘走既有 [SecureBox]，绝不明文进 SharedPreferences。
library;

import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../services/audio/sources/bilibili/bilibili_webview_login.dart';

/// 打开 B站登录弹层；返回 `true` 表示登录成功。
Future<bool?> showBilibiliLoginSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.bgSurface,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _BilibiliLoginSheet(),
  );
}

enum _Tab { web, cookie }

class _BilibiliLoginSheet extends ConsumerStatefulWidget {
  const _BilibiliLoginSheet();

  @override
  ConsumerState<_BilibiliLoginSheet> createState() => _BilibiliLoginSheetState();
}

class _BilibiliLoginSheetState extends ConsumerState<_BilibiliLoginSheet> {
  _Tab _tab = _Tab.web;
  // 与网易云对齐（2026-08-17）：Cookie 分开填——SESSDATA 与 bili_jct 两个
  // 输入框，自动拼头；整段粘贴亦兼容。
  final TextEditingController _sessdataCtrl = TextEditingController();
  final TextEditingController _biliJctCtrl = TextEditingController();
  String _status = '';

  @override
  void dispose() {
    _sessdataCtrl.dispose();
    _biliJctCtrl.dispose();
    super.dispose();
  }

  /// 应用内登录：Android 拉起原生 WebView（bilibili 类型）；Windows/桌面端
  /// 直接调起系统默认浏览器打开 B站桌面登录页，登录后复制 Cookie 回填。
  Future<void> _webLogin() async {
    if (!kIsWeb && Platform.isWindows) {
      bool ok = false;
      try {
        // dart:io 直接调系统浏览器（零依赖，绕开 url_launcher 的
        // androidx.browser 对 AGP ≥8.9 的要求）。
        await Process.start(
          'cmd.exe',
          <String>['/c', 'start', '', 'https://passport.bilibili.com/login'],
        );
        ok = true;
      } catch (_) {
        ok = false;
      }
      if (!mounted) return;
      setState(() {
        _status = ok
            ? '已在浏览器打开 B站登录页。登录完成后：浏览器按 F12 →'
                '「网络」→ 点任意 bilibili.com 请求 → 复制请求头的 Cookie'
                ' 整段值（含 SESSDATA）→ 切到「粘贴 Cookie」粘贴即可。'
            : '无法打开浏览器，请改用「粘贴 Cookie」方式。';
      });
      return;
    }
    if (!webviewLoginSupported) {
      setState(() => _status = '当前平台不支持内嵌登录，请使用「粘贴 Cookie」方式');
      return;
    }
    setState(() => _status = '正在打开 B站登录页…');
    final String? cookie = await startBilibiliWebviewLogin();
    if (!mounted) return;
    if (cookie == null || cookie.isEmpty) {
      setState(() => _status = '未获取到登录状态（已取消或未完成登录）');
      return;
    }
    final bool ok =
        await ref.read(bilibiliAuthProvider.notifier).loginWithCookie(cookie);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _status = '登录校验失败，请重试');
    }
  }

  Future<void> _loginCookie() async {
    // 与网易云对齐：SESSDATA / bili_jct 分开填，自动拼成标准 Cookie 头；
    // 若用户仍用整段粘贴则原样兼容（字段含 '=' 即视为整段）。
    String raw = _sessdataCtrl.text.trim();
    if (raw.isNotEmpty && !raw.contains('=')) {
      raw = 'SESSDATA=$raw';
    }
    final String jct = _biliJctCtrl.text.trim();
    if (jct.isNotEmpty) {
      final String jctPart = jct.contains('=') ? jct : 'bili_jct=$jct';
      raw = raw.isEmpty ? jctPart : '$raw; $jctPart';
    }
    if (raw.isEmpty) {
      setState(() => _status = '请填写 SESSDATA（必填），或整段粘贴 Cookie');
      return;
    }
    final bool ok =
        await ref.read(bilibiliAuthProvider.notifier).loginWithCookie(raw);
    if (ok && mounted) {
      Navigator.of(context).pop(true);
    } else if (mounted) {
      setState(() => _status = '登录校验失败，请检查 Cookie 是否完整');
    }
  }

  Future<void> _logout() async {
    await ref.read(bilibiliAuthProvider.notifier).logout();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final BilibiliAuthState auth = ref.watch(bilibiliAuthProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.video_library_outlined,
                      size: AppSize.icon, color: context.appColors.accent),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text('哔哩哔哩视频源', style: context.appText.subtitle),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: AppSize.iconSm,
                        color: context.appColors.iconInactive),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),

              if (auth.isLoggedIn)
                _LoggedInPanel(nickname: auth.nickname, onLogout: _logout)
              else ...<Widget>[
                Row(
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('网页登录'),
                      selected: _tab == _Tab.web,
                      onSelected: (_) => setState(() => _tab = _Tab.web),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    ChoiceChip(
                      label: const Text('粘贴 Cookie'),
                      selected: _tab == _Tab.cookie,
                      onSelected: (_) => setState(() => _tab = _Tab.cookie),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                AnimatedSwitcher(
                  duration: AppMotion.tab,
                  child: _tab == _Tab.web
                      ? _WebLoginPanel(
                          busy: auth.busy,
                          status: _status,
                          onLogin: _webLogin,
                        )
                      : _CookiePanel(
                          sessdataCtrl: _sessdataCtrl,
                          biliJctCtrl: _biliJctCtrl,
                          busy: auth.busy,
                          onLogin: _loginCookie,
                        ),
                ),
                if (auth.error != null) ...<Widget>[
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    auth.error!,
                    style: context.appText.artist
                        .copyWith(color: context.appColors.danger),
                  ),
                ],
                if (_status.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpace.sm),
                  Text(_status, style: context.appText.artist),
                ],
                const SizedBox(height: AppSpace.sm),
                Text(
                  '登录凭证仅加密保存在本机（SecureBox），绝不上传。',
                  style: context.appText.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 应用内登录路径：拉起原生 WebView（仅 Android）。
class _WebLoginPanel extends StatelessWidget {
  const _WebLoginPanel({
    required this.busy,
    required this.status,
    required this.onLogin,
  });

  final bool busy;
  final String status;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '在应用内打开 B站桌面登录页：网页自带标准二维码（B站 App 可正常'
          '扫码）或输账号登录，登录状态会自动保存（含 httpOnly 的 SESSDATA，'
          '仅 Android）。',
          style: context.appText.artist,
        ),
        const SizedBox(height: AppSpace.md),
        FilledButton.icon(
          onPressed: busy ? null : onLogin,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.language_rounded, size: 18),
          label: Text(busy ? '处理中…' : '打开 B站登录页'),
        ),
        if (status.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.sm),
          Text(status, style: context.appText.artist),
        ],
      ],
    );
  }
}

/// Cookie 路径：SESSDATA / bili_jct 分开填（自动拼 Cookie 头），整段粘贴兼容。
/// 与网易云 [_CookiePanel] 对齐（2026-08-17）。
class _CookiePanel extends StatelessWidget {
  const _CookiePanel({
    required this.sessdataCtrl,
    required this.biliJctCtrl,
    required this.busy,
    required this.onLogin,
  });

  final TextEditingController sessdataCtrl;
  final TextEditingController biliJctCtrl;
  final bool busy;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: sessdataCtrl,
          style: context.appText.body,
          decoration: InputDecoration(
            labelText: 'SESSDATA（必填）',
            hintText: '粘贴 SESSDATA 的值',
            hintStyle: context.appText.artist,
            filled: true,
            fillColor: context.appColors.bgCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: context.appColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: context.appColors.border),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: biliJctCtrl,
          style: context.appText.body,
          decoration: InputDecoration(
            labelText: 'bili_jct（可选）',
            hintText: '粘贴 bili_jct 的值',
            hintStyle: context.appText.artist,
            filled: true,
            fillColor: context.appColors.bgCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: context.appColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: context.appColors.border),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          '如何获取：电脑浏览器登录 bilibili.com，F12 → 应用/Application →'
          ' Cookies，复制 SESSDATA 的值填入（bili_jct 为 CSRF 令牌，可选；'
          '也可整段粘贴「SESSDATA=…; bili_jct=…; DedeUserID=…」自动识别）。',
          style: context.appText.caption,
        ),
        const SizedBox(height: AppSpace.md),
        FilledButton(
          onPressed: busy ? null : onLogin,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
        ),
      ],
    );
  }
}

class _LoggedInPanel extends StatelessWidget {
  const _LoggedInPanel({required this.nickname, required this.onLogout});

  final String? nickname;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(Icons.check_circle_rounded,
            size: AppSize.iconSm, color: context.appColors.accent),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            '已登录${nickname != null && nickname!.isNotEmpty ? '：$nickname' : ''}',
            style: context.appText.body,
          ),
        ),
        TextButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded, size: 16),
          label: const Text('登出'),
        ),
      ],
    );
  }
}
