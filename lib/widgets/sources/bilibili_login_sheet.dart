/// 哔哩哔哩登录底部弹层（二维码优先 + 粘贴 cookie）。
///
/// 扫码登录：请求二维码 → 渲染（qr_flutter）→ 2s 轮询 poll → 成功自动
/// 抓取 SESSDATA 等加密落盘。Windows/桌面以粘贴 cookie 为主路径。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../services/audio/sources/bilibili/bilibili_api.dart';

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

enum _Tab { qr, cookie }

class _BilibiliLoginSheet extends ConsumerStatefulWidget {
  const _BilibiliLoginSheet();

  @override
  ConsumerState<_BilibiliLoginSheet> createState() => _BilibiliLoginSheetState();
}

class _BilibiliLoginSheetState extends ConsumerState<_BilibiliLoginSheet> {
  _Tab _tab = _Tab.qr;
  final TextEditingController _cookieCtrl = TextEditingController();
  String _status = '';
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cookieCtrl.dispose();
    super.dispose();
  }

  Future<void> _startQr() async {
    _pollTimer?.cancel();
    final bool ok = await ref.read(bilibiliAuthProvider.notifier).startQrLogin();
    if (!ok || !mounted) return;
    // R26skel-b5：每 5 秒自动查询扫码状态 / cookie（用户指定节奏）。
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final BiliQrStatus? st =
          await ref.read(bilibiliAuthProvider.notifier).pollQrLogin();
      if (!mounted) return;
      if (st == BiliQrStatus.authorized) {
        _pollTimer?.cancel();
        Navigator.of(context).pop(true);
      } else if (st == BiliQrStatus.expired) {
        _pollTimer?.cancel();
      }
    });
  }

  Future<void> _loginCookie() async {
    final String raw = _cookieCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _status = '请粘贴 SESSDATA=..; bili_jct=.. 整段 Cookie');
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
                      label: const Text('扫码登录'),
                      selected: _tab == _Tab.qr,
                      onSelected: (_) => setState(() => _tab = _Tab.qr),
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

                if (_tab == _Tab.qr) _QrPanel(auth: auth, onStart: _startQr)
                else _CookiePanel(
                    controller: _cookieCtrl, onLogin: _loginCookie),
                if (_status.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpace.sm),
                  Text(_status, style: context.appText.artist),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QrPanel extends ConsumerWidget {
  const _QrPanel({required this.auth, required this.onStart});

  final BilibiliAuthState auth;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? url = auth.qrUrl;
    if (url == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: auth.busy ? null : onStart,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('获取二维码'),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: QrImageView(
            data: url,
            size: 180,
            backgroundColor: const Color(0xFFFFFFFF),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          auth.qrMessage ?? '使用 B站手机 App「扫一扫」登录',
          style: context.appText.artist,
        ),
        if (auth.busy) const Padding(
          padding: EdgeInsets.only(top: 6),
          child: SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ],
    );
  }
}

class _CookiePanel extends StatelessWidget {
  const _CookiePanel({required this.controller, required this.onLogin});

  final TextEditingController controller;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'SESSDATA=xxxx; bili_jct=xxxx; DedeUserID=xxxx',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        FilledButton.icon(
          onPressed: onLogin,
          icon: const Icon(Icons.login_rounded, size: 18),
          label: const Text('登录'),
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
