import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/track.dart';
import '../../services/audio/audio_meta_probe.dart';

/// 曲目信息面板（底部卡片）：标题 / 艺术家 / 专辑 / 来源 / 编码 / 采样率 /
/// 位深 / 码率 / 时长 / CUE 区间。本地文件懒探测 PCM 属性（零依赖）。
///
/// 遵循全局约定：isScrollControlled + SingleChildScrollView + 高度上限 0.92。
Future<void> showTrackInfoSheet(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.appColors.bgSurface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _TrackInfoSheet(track: track),
  );
}

class _TrackInfoSheet extends StatefulWidget {
  const _TrackInfoSheet({required this.track});

  final Track track;

  @override
  State<_TrackInfoSheet> createState() => _TrackInfoSheetState();
}

class _TrackInfoSheetState extends State<_TrackInfoSheet> {
  AudioMeta? _meta;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final Track t = widget.track;
    if (t.isRemote) return;
    final String uri = t.uri.startsWith('file://')
        ? Uri.parse(t.uri).toFilePath()
        : t.uri;
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final AudioMeta? m = await probeAudioFile(uri, duration: t.duration);
      if (mounted) setState(() => _meta = m);
    } catch (_) {
      // 探测失败：面板仍展示其它已知字段
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Track t = widget.track;
    final AppThemeColors c = context.appColors;
    final AudioMeta? m = _meta;
    final String codec = m?.codec ?? (t.isRemote ? '流媒体' : _codecFallback(t.uri));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (BuildContext ctx, ScrollController sc) => SingleChildScrollView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(t.title,
                style: context.appText.title
                    .copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(t.artist.isEmpty ? '未知艺术家' : t.artist,
                style: context.appText.bodyMuted),
            const SizedBox(height: 16),
            _Row('格式', codec),
            if (_loading)
              _Row('采样率 / 位深 / 码率', '探测中…', muted: true)
            else ...<Widget>[
              _Row('采样率', _hz(m?.sampleRate)),
              _Row('位深', _bits(m?.bitDepth)),
              _Row('码率', _br(m?.bitrate, codec)),
            ],
            _Row('时长', _fmt(t.duration)),
            _Row('专辑', t.album?.isNotEmpty == true ? t.album! : '—'),
            _Row('来源', t.sourceId.isEmpty ? '—' : t.sourceId),
            if (t.cueStartMs != null || t.cueEndMs != null)
              _Row('CUE 区间',
                  '${_fmt(Duration(milliseconds: t.cueStartMs ?? 0))} → '
                  '${t.cueEndMs == null ? '整轨尾' : _fmt(Duration(milliseconds: t.cueEndMs!))}'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _Row(String label, String value, {bool muted = false}) {
    final AppThemeColors c = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(label,
                style: context.appText.caption
                    .copyWith(color: c.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: (muted ? context.appText.caption : context.appText.body)
                  .copyWith(color: muted ? c.textSecondary : c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  String _codecFallback(String uri) {
    final String l = uri.toLowerCase();
    if (l.endsWith('.flac')) return 'FLAC';
    if (l.endsWith('.wav')) return 'WAV';
    if (l.endsWith('.mp3')) return 'MP3';
    if (l.endsWith('.m4a') || l.endsWith('.aac')) return 'AAC/M4A';
    if (l.endsWith('.ogg')) return 'OGG';
    if (l.endsWith('.opus')) return 'Opus';
    return '未知';
  }

  String _hz(int? v) => v == null ? '—' : '$v Hz';
  String _bits(int? v) => v == null ? '—' : '$v-bit';
  String _br(int? v, String codec) {
    if (v != null) return '$v kbps';
    if (codec == 'FLAC') return '无损';
    return '—';
  }

  String _fmt(Duration? d) {
    if (d == null) return '—';
    final int h = d.inHours;
    final int m = d.inMinutes % 60;
    final int s = d.inSeconds % 60;
    final String mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final String ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}
