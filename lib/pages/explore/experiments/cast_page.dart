import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../models/track.dart';
import '../../../providers/audio/audio_providers.dart';
import '../../../providers/cast/cast_providers.dart';
import '../../../widgets/common/page_scaffold.dart';

/// 投屏（T11 最小版）：局域网 HTTP 流媒体服务。
///
/// 开启后同网段设备用浏览器 / VLC / 电视盒子打开本机地址即可播放
/// 正在播放的曲目（本地文件 Range 切片直读，网络源代理转发）。
class CastPage extends ConsumerWidget {
  const CastPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CastUiState state = ref.watch(castServerProvider);
    final Track? current = ref.watch(currentTrackProvider).valueOrNull;
    final AppThemeColors c = context.appColors;

    return PageScaffold(
      title: '投屏',
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: <Widget>[
          _IntroCard(c: c, state: state),
          const SizedBox(height: AppSpace.md),
          _buildToggle(c: c, state: state, ref: ref),
          if (state.running) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            _IpCard(c: c, state: state),
            const SizedBox(height: AppSpace.md),
            _CurrentCard(c: c, current: current, state: state),
            const SizedBox(height: AppSpace.md),
            _NoticeCard(c: c),
          ],
        ],
      ),
    );
  }

  Widget _buildToggle({
    required AppThemeColors c,
    required CastUiState state,
    required WidgetRef ref,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            state.running ? Icons.cast_connected_rounded : Icons.cast_rounded,
            color: state.running ? c.accent : c.iconInactive,
            size: 22,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('投屏服务',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  state.running ? '已启动 · 端口 ${state.port}' : '未启动',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: state.running,
            activeThumbColor: c.onAccent,
            activeTrackColor: c.accent,
            onChanged: (_) => ref.read(castServerProvider.notifier).toggle(),
          ),
        ],
      ),
    );
  }
}

// ── 说明卡 ─────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.c, required this.state});
  final AppThemeColors c;
  final CastUiState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('把正在播放的歌曲，投到同一个 Wi-Fi 下的设备',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary)),
          const SizedBox(height: AppSpace.sm),
          Text(
            '开启服务后，用手机 / 平板 / 电视盒子上的浏览器、VLC 或任一播放器，'
            '打开下方地址即可播放。本地文件直读不重编码，网络曲目原样转发。',
            style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ── 本机地址卡 ─────────────────────────────────────────────────────

class _IpCard extends StatelessWidget {
  const _IpCard({required this.c, required this.state});
  final AppThemeColors c;
  final CastUiState state;

  @override
  Widget build(BuildContext context) {
    final List<String> ips = state.ips;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('本机地址',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary)),
          const SizedBox(height: AppSpace.sm),
          if (ips.isEmpty)
            Text('未找到局域网地址，请确认已连接 Wi-Fi',
                style: TextStyle(fontSize: 13, color: c.textTertiary))
          else
            for (final String ip in ips)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _AddressRow(c: c, text: 'http://$ip:${state.port}'),
              ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.c, required this.text});
  final AppThemeColors c;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: SelectableText(text,
              style: TextStyle(fontSize: 14, color: c.accent)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.copy_rounded, size: 18, color: c.iconInactive),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('地址已复制，发到目标设备打开即可'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

// ── 当前曲目卡 ─────────────────────────────────────────────────────

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({
    required this.c,
    required this.state,
    required this.current,
  });
  final AppThemeColors c;
  final CastUiState state;
  final Track? current;

  @override
  Widget build(BuildContext context) {
    final Track? t = current;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('当前曲目',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary)),
          const SizedBox(height: AppSpace.sm),
          if (t == null || t.uri.isEmpty)
            Text('暂无正在播放的歌曲，请先播放一首再投屏',
                style: TextStyle(fontSize: 13, color: c.textTertiary))
          else ...<Widget>[
            Text(
              t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: c.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(t.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const SizedBox(height: AppSpace.sm),
            for (final String url in state.entryUrls(t.uri))
              _UrlRow(c: c, url: url, note: url.contains('/track') ? '直链（VLC / 播放器）' : '网页（浏览器打开）'),
          ],
        ],
      ),
    );
  }
}

class _UrlRow extends StatelessWidget {
  const _UrlRow({required this.c, required this.url, required this.note});
  final AppThemeColors c;
  final String url;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(note,
                    style: TextStyle(fontSize: 11, color: c.textTertiary)),
                const SizedBox(height: 2),
                Text(url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.accent)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy_rounded, size: 18, color: c.iconInactive),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('播放链接已复制'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// ── 注意事项 ───────────────────────────────────────────────────────

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.c});
  final AppThemeColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.bgSurfaceSunken,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('注意事项',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary)),
          const SizedBox(height: AppSpace.sm),
          Text(
            '· 手机与电脑需处于同一 Wi-Fi / 热点\n'
            '· Windows 若无法访问，请在防火墙放行本程序\n'
            '· 关闭页面或切歌后，链接地址无需更新（自动跟随当前曲目）\n'
            '· AirPlay / Chromecast / DLNA 系统投屏后续版本接入',
            style: TextStyle(fontSize: 12.5, color: c.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }
}