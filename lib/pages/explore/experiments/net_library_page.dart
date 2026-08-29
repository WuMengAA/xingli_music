import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../models/track.dart';
import '../../../models/webdav_config.dart';
import '../../../providers/audio/playback_notifier.dart';
import '../../../providers/network/webdav_providers.dart';
import '../../../services/network/webdav_client.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_views.dart';
import '../../../widgets/notification/app_notify.dart';

/// 文件大小人性化显示（B → MB/GB）。
String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 网络音乐库（T12）：WebDAV 配置管理 + 目录浏览 + 在线播放。
class NetLibraryPage extends ConsumerWidget {
  const NetLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    final List<WebDavConfig> configs = ref.watch(webdavConfigsProvider);

    return PageScaffold(
      title: '网络音乐库',
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: c.bgSurface,
              borderRadius: AppRadius.brLg,
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('WebDAV 音乐库',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary)),
                const SizedBox(height: AppSpace.sm),
                Text(
                  '连接任意支持 WebDAV 的服务器（NAS / 群晖 / Nginx webdav 等），'
                  '在线浏览并播放远程曲库；音频直接流式播放，不下载到本地。',
                  style:
                      TextStyle(fontSize: 13, color: c.textSecondary, height: 1.5),
                ),
                const SizedBox(height: AppSpace.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => _editDialog(context, ref, null),
                    style: FilledButton.styleFrom(
                        backgroundColor: c.accent, foregroundColor: c.onAccent),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('添加服务器'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          if (configs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: EmptyView(
                  title: '还没有服务器', message: '点击「添加服务器」接入你的 WebDAV 曲库'),
            )
          else
            for (final WebDavConfig cfg in configs)
              _ConfigTile(cfg: cfg, onEdit: () => _editDialog(context, ref, cfg)),
        ],
      ),
    );
  }

  Future<void> _editDialog(
    BuildContext context,
    WidgetRef ref,
    WebDavConfig? existing,
  ) async {
    final bool isNew = existing == null;
    final TextEditingController name =
        TextEditingController(text: existing?.name ?? '');
    final TextEditingController url =
        TextEditingController(text: existing?.baseUrl ?? '');
    final TextEditingController user =
        TextEditingController(text: existing?.username ?? '');
    final TextEditingController pass =
        TextEditingController(text: existing?.password ?? '');

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(isNew ? '添加 WebDAV 服务器' : '编辑服务器'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '显示名（如：书房 NAS）')),
              const SizedBox(height: AppSpace.sm),
              TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: '服务器地址（http://主机:端口/路径）')),
              const SizedBox(height: AppSpace.sm),
              TextField(
                  controller: user, decoration: const InputDecoration(labelText: '用户名（可空）')),
              const SizedBox(height: AppSpace.sm),
              TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码（可空）')),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isNew ? '添加' : '保存'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final String baseUrl = url.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (baseUrl.isEmpty) {
      if (context.mounted) appNotify(context, '请填写服务器地址');
      return;
    }
    final WebDavConfig next = isNew
        ? WebDavConfig(
            id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
            name: name.text.trim().isEmpty ? '未命名库' : name.text.trim(),
            baseUrl: baseUrl,
            username: user.text.trim(),
            password: pass.text,
          )
        : existing.copyWith(
            name: name.text.trim().isEmpty ? existing.name : name.text.trim(),
            baseUrl: baseUrl,
            username: user.text.trim(),
            password: pass.text,
          );
    final WebDavConfigsNotifier notifier =
        ref.read(webdavConfigsProvider.notifier);
    if (isNew) {
      await notifier.add(next);
    } else {
      await notifier.update(next);
    }
  }
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({required this.cfg, required this.onEdit});
  final WebDavConfig cfg;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Container(
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: AppRadius.brLg,
        ),
        child: ListTile(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _WebDavBrowserPage(config: cfg),
            ),
          ),
          leading: Icon(
            cfg.username.isEmpty ? Icons.cloud_outlined : Icons.cloud_rounded,
            color: c.accent,
          ),
          title: Text(cfg.name,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary)),
          subtitle: Text(
            cfg.baseUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.edit_outlined, size: 18, color: c.iconInactive),
                onPressed: onEdit,
              ),
              Icon(Icons.chevron_right_rounded, color: c.iconInactive),
            ],
          ),
        ),
      ),
    );
  }
}

/// WebDAV 目录浏览器（一个服务器一个实例）。
class _WebDavBrowserPage extends ConsumerStatefulWidget {
  const _WebDavBrowserPage({required this.config});
  final WebDavConfig config;

  @override
  ConsumerState<_WebDavBrowserPage> createState() => _WebDavBrowserPageState();
}

class _WebDavBrowserPageState extends ConsumerState<_WebDavBrowserPage> {
  WebDavClient? _client;
  List<WebDavEntry>? _entries;
  String _path = '';
  Object? _error;
  bool _loading = true;

  List<String> get _crumbs =>
      _path.isEmpty ? <String>[] : _path.split('/').where((String s) => s.isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _load('/');
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final WebDavClient client = _client ??
        WebDavClient(
          baseUrl: widget.config.baseUrl,
          username: widget.config.username,
          password: widget.config.password,
        );
    _client = client;
    try {
      final List<WebDavEntry> entries = await client.list(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _entries = null;
      });
    }
  }

  Future<void> _play(WebDavEntry entry) async {
    final String enc = webdavPlaceholderUri(entry.absoluteUrl(widget.config.baseUrl));
    final String msg = await ref
        .read(playbackActionsProvider)
        .playTrack(
          Track(
            title: entry.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
            artist: widget.config.name,
            uri: enc,
            source: TrackSource.stream,
            sourceId: 'webdav:${widget.config.id}',
            extras: <String, dynamic>{
              'webdav': widget.config.baseUrl,
            },
          ),
        );
    if (msg.isNotEmpty && mounted) appNotify(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return PageScaffold(
      title: widget.config.name,
      body: Column(
        children: <Widget>[
          // 面包屑导航
          _buildCrumbs(c),
          Divider(height: 1, color: c.divider),
          Expanded(child: _buildBody(c)),
        ],
      ),
    );
  }

  Widget _buildCrumbs(AppThemeColors c) {
    final List<String> crumbs = _crumbs;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        children: <Widget>[
          _crumb(c, '/', '根目录', () {
            if (_crumbs.isNotEmpty) unawaited(_load('/'));
          }),
          for (int i = 0; i < crumbs.length; i++)
            _crumb(c, '>', crumbs[i], () {
              final String up = crumbs.take(i + 1).join('/');
              unawaited(_load('/$up'));
            }),
        ],
      ),
    );
  }

  Widget _crumb(AppThemeColors c, String prefix, String label, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brSm,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: <Widget>[
              Text(prefix,
                  style: TextStyle(
                      fontSize: 13,
                      color: c.textTertiary,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.accent)),
            ],
          ),
        ),
      );

  Widget _buildBody(AppThemeColors c) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorView(
        message: '$_error',
        onRetry: () => _load(_path.isEmpty ? '/' : _path),
      );
    }
    final List<WebDavEntry> entries = _entries ?? <WebDavEntry>[];
    if (entries.isEmpty) {
      return const EmptyView(title: '此目录为空', message: '切换目录或检查服务器权限');
    }
    final List<WebDavEntry> dirs =
        entries.where((WebDavEntry e) => e.isDir).toList();
    final List<WebDavEntry> audios =
        entries.where((WebDavEntry e) => e.isAudio).toList();
    final List<WebDavEntry> others = entries
        .where((WebDavEntry e) => !e.isDir && !e.isAudio)
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        if (dirs.isNotEmpty)
          for (final WebDavEntry d in dirs)
            ListTile(
              onTap: () => _load(d.href),
              leading: Icon(Icons.folder_rounded, color: c.warning),
              title: Text(d.name,
                  style: TextStyle(fontSize: 14.5, color: c.textPrimary)),
              trailing: Icon(Icons.chevron_right_rounded, color: c.iconInactive),
            ),
        if (audios.isNotEmpty)
          for (final WebDavEntry a in audios)
            ListTile(
              onTap: () => _play(a),
              leading: Icon(Icons.music_note_rounded, color: c.accent),
              title: Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, color: c.textPrimary)),
              trailing: Text(_fmtBytes(a.sizeBytes),
                  style: TextStyle(fontSize: 12, color: c.textTertiary)),
            ),
        if (others.isNotEmpty)
          for (final WebDavEntry o in others)
            ListTile(
              dense: true,
              leading: Icon(Icons.insert_drive_file_outlined,
                  color: c.iconInactive),
              title: Text(o.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
            ),
      ],
    );
  }
}