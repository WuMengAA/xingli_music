import 'dart:convert';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../models/track.dart';
import '../../../providers/audio/playback_notifier.dart';
import '../../../services/cue/cue_parser.dart';
import '../../../widgets/common/info_row.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_views.dart';
import '../../../widgets/notification/app_notify.dart';

/// CUE 分轨（T12）：选择 .cue 整轨文件，解析出分轨列表并逐轨播放。
///
/// 音频文件与 .cue 需在同一目录（FILE 行为相对路径）；点击分轨时
/// 播放整轨文件并 seek 到 INDEX 01 起点（AudioService 侧支持）。
class CueSheetPage extends ConsumerStatefulWidget {
  const CueSheetPage({super.key});

  @override
  ConsumerState<CueSheetPage> createState() => _CueSheetPageState();
}

class _CueSheetPageState extends ConsumerState<CueSheetPage> {
  CueSheet? _sheet;
  String? _cueDir;
  String? _error;
  bool _loading = false;

  Future<void> _pick() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['cue'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final PlatformFile f = result.files.single;

      // 读内容：优先 bytes（移动端），否则按路径读（桌面端）。
      String? content;
      if (f.bytes != null && f.bytes!.isNotEmpty) {
        content = utf8.decode(f.bytes!, allowMalformed: true);
      } else if (f.path != null) {
        final List<int> raw = await File(f.path!).readAsBytes().timeout(
              const Duration(seconds: 10),
            );
        content = utf8.decode(raw, allowMalformed: true);
      }

      final CueSheet? sheet = content == null ? null : parseCue(content);
      if (sheet == null) {
        setState(() {
          _sheet = null;
          _error = '无法解析该 CUE 文件（缺失 TRACK 或文件为空）';
          _loading = false;
        });
        return;
      }
      setState(() {
        _sheet = sheet;
        // 音频基目录 = cue 文件所在目录（FILE 相对路径基于此解析）。
        _cueDir = f.path == null ? null : p.dirname(f.path!);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '读取 CUE 文件失败：$e';
      });
    }
  }

  String? _fileFor(CueTrack t) {
    final String? rel = t.file;
    final String? dir = _cueDir;
    if (rel == null || dir == null) return null;
    if (rel.startsWith('/') || rel.contains(':')) return rel;
    return p.join(dir, rel);
  }

  String _fmt(Duration? d) {
    if (d == null) return '未知';
    final int m = d.inMinutes;
    final int s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Track _trackFor(CueTrack t, String filePath) => Track(
        title: t.title.isEmpty ? '音轨 ${t.number}' : t.title,
        artist: t.performer.isEmpty ? '未知艺术家' : t.performer,
        uri: filePath,
        source: TrackSource.local,
        sourceId: 'cue',
        duration: t.end == null
            ? null
            : t.end! - (t.start ?? Duration.zero),
        cueStartMs: t.startMs > 0 ? t.startMs : null,
        cueEndMs: t.endMs,
      );

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final CueSheet? sheet = _sheet;

    return PageScaffold(
      title: 'CUE 分轨',
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
                Text('解析整轨 CUE · 逐轨播放',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary)),
                const SizedBox(height: AppSpace.sm),
                Text(
                  '选择与音频文件同目录的 .cue 文件，应用会解析出分轨列表；'
                  '点击任一音轨即从该轨起点播放（自动 seek，无需切割文件）。',
                  style:
                      TextStyle(fontSize: 13, color: c.textSecondary, height: 1.5),
                ),
                const SizedBox(height: AppSpace.sm),
                FilledButton.icon(
                  onPressed: _loading ? null : _pick,
                  style: FilledButton.styleFrom(
                      backgroundColor: c.accent, foregroundColor: c.onAccent),
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_open_rounded, size: 18),
                  label: Text(sheet == null ? '选择 CUE 文件' : '重新选择'),
                ),
              ],
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            Text(_error!, style: TextStyle(fontSize: 13, color: c.danger)),
          ],
          if (sheet != null) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            if (sheet.albumTitle.isNotEmpty || sheet.albumPerformer.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                    color: c.bgCard, borderRadius: AppRadius.brLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (sheet.albumTitle.isNotEmpty)
                      Text(sheet.albumTitle,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary)),
                    if (sheet.albumPerformer.isNotEmpty)
                      Text(sheet.albumPerformer,
                          style: TextStyle(fontSize: 13, color: c.textSecondary)),
                    if (sheet.files.isNotEmpty)
                      for (final String fl in sheet.files)
                        Text('文件：$fl',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 12, color: c.textTertiary)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpace.xs),
            Text('共 ${sheet.tracks.length} 个音轨 · 点击播放',
                style: TextStyle(fontSize: 12, color: c.textTertiary)),
            const SizedBox(height: AppSpace.xs),
            for (final CueTrack t in sheet.tracks)
              _buildTrackRow(c: c, t: t),
          ] else if (!_loading && _sheet == null && _error == null)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyView(
                  title: '尚未选择 CUE 文件', message: '选择后会在这里显示分轨列表'),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackRow({required AppThemeColors c, required CueTrack t}) {
    final String filePath = _fileFor(t) ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: InfoRow(
        track: _trackFor(t, filePath),
        trailing: Text(
          '${t.number.toString().padLeft(2, '0')} · '
          '${_fmt(t.start)} → ${_fmt(t.end)}',
          style: TextStyle(fontSize: 12, color: c.textSecondary),
        ),
        onTap: () async {
          if (filePath.isEmpty) {
            appNotify(context, '找不到对应的音频文件，请确认 .cue 与音频同目录');
            return;
          }
          final String msg = await ref
              .read(playbackActionsProvider)
              .playTrack(_trackFor(t, filePath));
          if (msg.isNotEmpty && mounted) appNotify(context, msg);
        },
      ),
    );
  }
}