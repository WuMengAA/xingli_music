/// 网易云登录底部弹层（I 域 · P1-6 接线 + 内嵌网页登录）。
///
/// 双路径：
/// - **应用内登录**（默认，仅 Android）：拉起原生 [CookieWebViewActivity] 内嵌
///   网易云登录页，手机 App 扫码并确认后自动抓取完整 cookie（含 httpOnly
///   MUSIC_U）→ 加密落盘。无依赖、不弹外部浏览器、不手动复制。
/// - **粘贴 Cookie**：手动粘贴 `MUSIC_U=...; __csrf=...`，[loginWithCookie]
///   校验并加密落盘（Windows / 其它平台的主要路径）。
///
/// cookie 加密落盘走既有 [SecureBox]，绝不明文进 SharedPreferences。
library;

import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/sources/netease_provider.dart';
import '../../services/audio/sources/netease/netease_api.dart';
import '../../services/audio/sources/netease/netease_webview_login.dart';

/// 打开网易云登录弹层；返回 `true` 表示登录成功。
Future<bool?> showNeteaseLoginSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.bgSurface,
    // 桌面宽屏下收窄居中（避免整条全宽的 Material 默认弹层）。
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _NeteaseLoginSheet(),
  );
}

enum _LoginTab { web, cookie }

class _NeteaseLoginSheet extends ConsumerStatefulWidget {
  const _NeteaseLoginSheet();

  @override
  ConsumerState<_NeteaseLoginSheet> createState() => _NeteaseLoginSheetState();
}

class _NeteaseLoginSheetState extends ConsumerState<_NeteaseLoginSheet> {
  _LoginTab _tab = _LoginTab.web;
  final TextEditingController _cookieCtrl = TextEditingController();
  String _status = '';

  @override
  void dispose() {
    _cookieCtrl.dispose();
    super.dispose();
  }

  /// 应用内登录：Android 拉起原生 WebView；Windows/桌面端直接调起
  /// 系统默认浏览器打开网易云登录页（R23），登录后复制 Cookie 回填。
  Future<void> _webLogin() async {
    if (!kIsWeb && Platform.isWindows) {
      bool ok = false;
      try {
        // dart:io 直接调系统浏览器（零依赖，绕开 url_launcher 的
        // androidx.browser 对 AGP ≥8.9 的要求）。
        await Process.start(
          'cmd.exe',
          <String>['/c', 'start', '', 'https://music.163.com/login'],
        );
        ok = true;
      } catch (_) {
        ok = false;
      }
      if (!mounted) return;
      setState(() {
        _status = ok
            ? '已在浏览器打开网易云登录页。登录完成后：浏览器按 F12 →'
                '「网络」→ 点任意 music.163.com 请求 → 复制请求头的 Cookie'
                ' 整段值 → 切到「粘贴 Cookie」粘贴即可。'
            : '无法打开浏览器，请改用「粘贴 Cookie」方式。';
      });
      return;
    }
    if (!webviewLoginSupported) {
      setState(() => _status = '当前平台不支持内嵌登录，请使用「粘贴 Cookie」方式');
      return;
    }
    setState(() => _status = '正在打开网易云登录页…');
    final String? cookie = await startNeteaseWebviewLogin();
    if (!mounted) return;
    if (cookie == null || cookie.isEmpty) {
      setState(() => _status = '未获取到登录状态（已取消或未完成扫码）');
      return;
    }
    final bool ok =
        await ref.read(neteaseAuthProvider.notifier).loginWithCookie(cookie);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _status = '登录校验失败，请重试');
    }
  }

  Future<void> _loginCookie() async {
    final bool ok =
        await ref.read(neteaseAuthProvider.notifier).loginWithCookie(
              _cookieCtrl.text,
            );
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _logout() async {
    await ref.read(neteaseAuthProvider.notifier).logout();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final NeteaseAuthState auth = ref.watch(neteaseAuthProvider);

    return Padding(
      // 键盘弹出时把内容顶上去，避免输入框被遮住。
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 标题行
              Row(
                children: <Widget>[
                  Icon(Icons.cloud_outlined,
                      size: AppSize.icon, color: context.appColors.accent),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text('网易云音乐', style: context.appText.subtitle),
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
                _LoggedInPanel(account: auth.account, onLogout: _logout)
              else ...<Widget>[
                // 双路径切换（与 app 全局 ChoiceChip 风格一致）
                Row(
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('应用内登录'),
                      selected: _tab == _LoginTab.web,
                      onSelected: (_) => setState(() => _tab = _LoginTab.web),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    ChoiceChip(
                      label: const Text('粘贴 Cookie'),
                      selected: _tab == _LoginTab.cookie,
                      onSelected: (_) => setState(() => _tab = _LoginTab.cookie),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                AnimatedSwitcher(
                  duration: AppMotion.tab,
                  child: _tab == _LoginTab.web
                      ? _WebLoginPanel(
                          busy: auth.busy,
                          status: _status,
                          onLogin: _webLogin,
                        )
                      : _CookiePanel(
                          controller: _cookieCtrl,
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

/// 已登录状态：账号 + 退出。
class _LoggedInPanel extends ConsumerWidget {
  const _LoggedInPanel({required this.account, required this.onLogout});

  final NeteaseAccount? account;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String nickname = account?.nickname ?? '网易云用户';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            CircleAvatar(
              radius: 18,
              backgroundColor: context.appColors.accentSoft,
              child: Icon(Icons.person_rounded,
                  size: 20, color: context.appColors.accent),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(nickname, style: context.appText.body),
                  const SizedBox(height: 2),
                  Text('已登录 · 可搜索并在线播放',
                      style: context.appText.artist),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        OutlinedButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('退出登录'),
        ),
      ],
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
          '在应用内打开网易云登录页：手机 App 扫码并确认后，'
          '登录状态会自动保存（含 httpOnly 的 MUSIC_U，仅 Android）。',
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
          label: Text(busy ? '处理中…' : '打开网易云登录页'),
        ),
        if (status.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.sm),
          Text(status, style: context.appText.artist),
        ],
      ],
    );
  }
}

/// Cookie 路径：粘贴 `MUSIC_U=...; __csrf=...` 直接登录。
class _CookiePanel extends StatelessWidget {
  const _CookiePanel({
    required this.controller,
    required this.busy,
    required this.onLogin,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: controller,
          maxLines: 3,
          keyboardType: TextInputType.multiline,
          style: context.appText.body,
          decoration: InputDecoration(
            hintText: 'MUSIC_U=xxxxxxxx; __csrf=xxxxxxxx',
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
          '如何获取：电脑浏览器登录 music.163.com，F12 → 应用/Application → Cookies，'
          '复制 MUSIC_U 与 __csrf 的值。',
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
