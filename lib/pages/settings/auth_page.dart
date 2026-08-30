import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track_stats.dart';
import '../../providers/auth/user_provider.dart';
import '../../providers/content/content_providers.dart';
import '../../providers/security/cert_policy_provider.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../services/auth/auth_service.dart';
import '../../services/security/http_client_factory.dart';

/// 账号页（cl10：用户系统）。
///
/// 游客可正常使用；登录/注册后 token 经 [SecureBox] 持久化，偏好与收藏可跨设备同步。
class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final TextEditingController _u = TextEditingController();
  final TextEditingController _p = TextEditingController();
  bool _loading = false;
  bool _syncing = false;
  String? _error;
  String? _syncMsg;

  Future<void> _submit(bool register) async {
    final String username = _u.text.trim();
    final String password = _p.text;
    if (username.length < 3) {
      setState(() => _error = '用户名至少 3 字符');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '密码至少 6 位');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final String base = ref.read(contentBaseUrlProvider);
    final bool lenient = ref.watch(certPolicyProvider) == CertPolicy.lenient;
    final client = makeHttpClient(lenient: lenient);
    final AuthResult res = register
        ? await registerUser(base, username, password, client: client)
        : await loginUser(base, username, password, client: client);
    client.close();
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.ok && res.token != null && res.user != null) {
      await ref.read(authProvider.notifier).setSession(res.token!, res.user!);
      if (mounted) Navigator.of(context).pop();
    } else {
      setState(() => _error = res.error ?? '请求失败');
    }
  }

  /// 把本地收藏上传到 relay（登录用户），返回是否成功。
  Future<void> _syncToCloud() async {
    final AuthState a = ref.read(authProvider);
    final String? token = a.token;
    final String? username = a.user?.username;
    if (token == null || username == null) return;
    setState(() {
      _syncing = true;
      _syncMsg = null;
    });
    try {
      final List<FavoriteEntry> favs =
          await ref.read(favoritesProvider.future);
      final List<dynamic> payload = favs
          .map((FavoriteEntry e) => <String, dynamic>{
                'title': e.title,
                'artist': e.artist,
                'sourceId': e.sourceId,
                'trackKey': e.trackKey,
              })
          .toList(growable: false);
      final String base = ref.read(contentBaseUrlProvider);
      final bool lenient = ref.watch(certPolicyProvider) == CertPolicy.lenient;
      final client = makeHttpClient(lenient: lenient);
      final AuthResult res =
          await updateUserFavorites(base, token, payload, client: client);
      client.close();
      if (!mounted) return;
      setState(() => _syncing = false);
      if (res.ok) {
        _syncMsg = '已同步 ${payload.length} 条收藏到云端';
      } else {
        _syncMsg = res.error ?? '同步失败';
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncMsg = '同步失败';
      });
    }
  }

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authProvider);
    final bool lenient = ref.watch(certPolicyProvider) == CertPolicy.lenient;
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('账号')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ListTile(
            leading: Icon(lenient ? Icons.lock_open : Icons.lock_outline),
            title: Text(lenient ? '连接安全：宽松' : '连接安全：严格'),
          ),
          const Divider(),
          if (auth.isAuthed) ...<Widget>[
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: const Text('当前账号'),
              subtitle: Text(auth.user?.username ?? ''),
            ),
            if (_syncing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              FilledButton.tonalIcon(
                onPressed: _syncToCloud,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('同步收藏到云端'),
              ),
              if (_syncMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_syncMsg!,
                      style: TextStyle(
                          fontSize: 12, color: theme.colorScheme.outline)),
                ),
            ],
            FilledButton(
              onPressed: () => ref.read(authProvider.notifier).logout(),
              child: const Text('退出登录'),
            ),
          ] else ...<Widget>[
            TextField(
              controller: _u,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _p,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...<Widget>[
              FilledButton(
                onPressed: () => _submit(false),
                child: const Text('登录'),
              ),
              TextButton(
                onPressed: () => _submit(true),
                child: const Text('注册新账号'),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
