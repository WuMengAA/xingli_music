/// 日志上报设置弹层（云端日志 · tools/log_server/server.js 配套）。
///
/// - 启用开关 + 服务器地址（实时保存）；
/// - 测试连接：用临时上传器发一条测试日志（不依赖全局开关）；
/// - 立即上报：flush 当前缓冲。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/log_upload_providers.dart';
import '../../services/log_discovery.dart';
import '../../services/remote_log_uploader.dart';

/// 打开日志上报设置弹层。
Future<void> showLogUploadSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.bgSurface,
    // 桌面宽屏下收窄居中（避免整条全宽的 Material 默认弹层）。
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _LogUploadSheet(),
  );
}

class _LogUploadSheet extends ConsumerStatefulWidget {
  const _LogUploadSheet();

  @override
  ConsumerState<_LogUploadSheet> createState() => _LogUploadSheetState();
}

class _LogUploadSheetState extends ConsumerState<_LogUploadSheet> {
  late final TextEditingController _urlCtrl;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _urlCtrl =
        TextEditingController(text: ref.read(logUploadEndpointProvider));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  /// 自动发现局域网内的日志服务器（手机与电脑同一 Wi-Fi）。
  Future<void> _discover() async {
    setState(() => _status = '正在搜索同一 Wi-Fi 下的日志服务器…');
    final String? url = await discoverLogServer();
    if (!mounted) return;
    if (url == null) {
      setState(() => _status = '未找到日志服务器：请确认电脑已启动服务端、手机与电脑同一 Wi-Fi、且防火墙放行 UDP 8766');
      return;
    }
    _urlCtrl.text = url;
    ref.read(logUploadEndpointProvider.notifier).state = url;
    setState(() => _status = '已找到：$url（点「启用上报」即开始自动上传）');
  }

  /// 测试连接：临时上传器直接发一条（不依赖全局开关）。
  Future<void> _test() async {
    final String url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _status = '请先填写服务器地址');
      return;
    }
    setState(() => _status = '测试中…');
    final RemoteLogUploader probe =
        RemoteLogUploader(endpoint: url, enabled: true);
    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    probe.push(
      RemoteLogEntry(
        ts: '${now.year}-${two(now.month)}-${two(now.day)} '
            '${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
        level: 'INFO',
        tag: 'log-upload',
        msg: '连接测试（来自星璃 App）',
      ),
    );
    final int n = await probe.flush();
    probe.dispose();
    if (!mounted) return;
    setState(() =>
        _status = n > 0 ? '连接成功：已上报 $n 条测试日志' : '连接失败：请检查地址 / 网络 / 服务端');
  }

  /// 立即上报当前缓冲。
  Future<void> _flushNow() async {
    final bool active = ref.read(remoteLogUploaderProvider).isActive;
    if (!active) {
      setState(() => _status = '上报未启用（需打开开关并填写地址）');
      return;
    }
    final int n = await ref.read(remoteLogUploaderProvider).flush();
    if (!mounted) return;
    setState(() => _status = n > 0 ? '已上报 $n 条' : '当前无待上报日志');
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = ref.watch(logUploadEnabledProvider);
    final String endpoint = ref.watch(logUploadEndpointProvider);

    return Padding(
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
                  Icon(Icons.cloud_upload_outlined,
                      size: AppSize.icon, color: context.appColors.accent),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text('日志上报', style: context.appText.subtitle),
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
              Text(
                '把本机已脱敏的日志批量发到你自建的日志服务（配套 tools/log_server）。'
                '默认关闭；手机与电脑在同一 Wi-Fi 时点「自动搜索」免填地址。',
                style: context.appText.artist,
              ),
              const SizedBox(height: AppSpace.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('启用上报', style: context.appText.body),
                subtitle: Text('仅启用时才会发送日志', style: context.appText.artist),
                value: enabled,
                onChanged: (bool v) {
                  ref.read(logUploadEnabledProvider.notifier).state = v;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('详细日志（DEBUG）', style: context.appText.body),
                subtitle: Text(
                  '记录状态机/播放器/音量等细粒度日志，便于定位问题',
                  style: context.appText.artist,
                ),
                value: ref.watch(logDebugEnabledProvider),
                onChanged: (bool v) {
                  ref.read(logDebugEnabledProvider.notifier).state = v;
                },
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                style: context.appText.body,
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'http://logs.example.com',
                  hintStyle: context.appText.artist,
                  helperText: '不带 /api/logs 后缀',
                  helperStyle: context.appText.caption,
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
                onChanged: (String v) {
                  ref.read(logUploadEndpointProvider.notifier).state = v;
                },
              ),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _discover,
                    icon: const Icon(Icons.wifi_find_rounded, size: 18),
                    label: const Text('自动搜索'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _test,
                    icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: const Text('测试连接'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _flushNow,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('立即上报'),
                  ),
                ],
              ),
              if (_status.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpace.sm),
                Text(_status, style: context.appText.artist),
              ],
              const SizedBox(height: AppSpace.sm),
              Text(
                endpoint.isEmpty ? '当前未配置服务器地址' : '当前地址：$endpoint',
                style: context.appText.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
