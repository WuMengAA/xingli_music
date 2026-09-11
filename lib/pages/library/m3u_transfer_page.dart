/// M3U8 播放列表导入 / 导出（完善功能：播放列表导入导出）。
///
/// - 导入：选 .m3u/.m3u8 → 解析 → 立即播放（作播放队列）/ 存入歌单；
/// - 导出：把当前播放列表（队列或当前曲目）写成 .m3u8 文件。
library;

import 'dart:convert';
import 'dart:io' show File, Directory;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../widgets/design/glass_controls.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../services/playlist/m3u_parser.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/notification/app_notify.dart';

class M3uTransferPage extends ConsumerStatefulWidget {
  const M3uTransferPage({super.key});

  @override
  ConsumerState<M3uTransferPage> createState() => _M3uTransferPageState();
}

class _M3uTransferPageState extends ConsumerState<M3uTransferPage> {
  List<M3uEntry>? _entries;
  String? _pickedName;
  String? _error;
  bool _loading = false;
  bool _busy = false;

  Future<void> _pickImport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['m3u', 'm3u8'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final PlatformFile f = result.files.single;
      String? content;
      if (f.bytes != null && f.bytes!.isNotEmpty) {
        content = utf8.decode(f.bytes!, allowMalformed: true);
      } else if (f.path != null) {
        content = await File(f.path!).readAsString();
      }
      final List<M3uEntry> entries =
          content == null ? const <M3uEntry>[] : parseM3u(content);
      if (entries.isEmpty) {
        setState(() {
          _entries = null;
          _error = '未解析到曲目（文件为空或格式不支持）';
          _loading = false;
        });
        return;
      }
      setState(() {
        _entries = entries;
        _pickedName = p.basenameWithoutExtension(f.name);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '读取失败：$e';
      });
    }
  }

  Future<void> _playNow() async {
    if (_entries == null) return;
    final List<Track> tracks = tracksFromM3u(_entries!);
    if (tracks.isEmpty) return;
    final String msg =
        await ref.read(playbackActionsProvider).playTrack(tracks.first, queue: tracks);
    if (msg.isNotEmpty && mounted) {
      appNotify(context, msg);
    } else if (mounted) {
      appNotify(context, '已开始播放 ${tracks.length} 首', title: 'M3U8');
    }
  }

  Future<void> _saveToPlaylist() async {
    if (_entries == null) return;
    setState(() => _busy = true);
    try {
      final List<Track> tracks = tracksFromM3u(_entries!);
      final String name =
          _pickedName?.isNotEmpty == true ? _pickedName! : 'M3U 导入';
      final int id = await ref.read(trackStatsDbProvider).createPlaylist(name);
      for (final Track t in tracks) {
        await ref.read(trackStatsDbProvider).addToPlaylist(
              id,
              trackKeyOf(t.title, t.artist, t.sourceId),
              t.title,
              t.artist,
              t.sourceId,
            );
      }
      ref.invalidate(playlistsProvider);
      if (mounted) {
        appNotify(context, '已存入歌单「$name」（$name 共 ${tracks.length} 首）',
            title: 'M3U8');
      }
    } catch (e) {
      if (mounted) appNotify(context, '存入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportQueue() async {
    final List<Track>? queue = ref.read(playbackQueueProvider);
    final Track? now = ref.read(nowPlayingProvider);
    final List<Track> toExport = (queue != null && queue.isNotEmpty)
        ? queue
        : (now != null ? <Track>[now] : const <Track>[]);
    if (toExport.isEmpty) {
      if (mounted) appNotify(context, '当前没有可导出的播放列表');
      return;
    }
    setState(() => _busy = true);
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final String path = p.join(dir.path, 'xingli_playlist.m3u8');
      await File(path).writeAsString(serializeM3u(toExport));
      if (mounted) {
        appNotify(context, '已导出 ${toExport.length} 首到 $path', title: 'M3U8');
      }
    } catch (e) {
      if (mounted) appNotify(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final List<M3uEntry>? entries = _entries;
    return PageScaffold(
      title: 'M3U8 播放列表',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _section(
            c,
            '导入',
            '选择 .m3u / .m3u8 文件，解析出曲目后可立即播放或存入歌单。',
            <Widget>[
              XGlassButton(
                onPressed: _loading ? null : _pickImport,
                child: _loading ? const Text('解析中…') : const Text('选择 M3U8 文件'),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(fontSize: 13, color: c.danger)),
              ],
              if (entries != null) ...<Widget>[
                const SizedBox(height: 8),
                Text('共 ${entries.length} 首',
                    style: TextStyle(fontSize: 12, color: c.textTertiary)),
                const SizedBox(height: 8),
                XGlassButton(
                    onPressed: _busy ? null : _playNow, child: const Text('立即播放')),
                const SizedBox(height: 8),
                XGlassButton(
                    onPressed: _busy ? null : _saveToPlaylist,
                    child: const Text('存入歌单')),
                const SizedBox(height: 8),
                for (final M3uEntry e in entries) _entryRow(c, e),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _section(
            c,
            '导出',
            '把当前播放列表（播放队列或当前曲目）导出为 .m3u8 文件。',
            <Widget>[
              XGlassButton(
                  onPressed: _busy ? null : _exportQueue,
                  child: const Text('导出当前播放列表')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(AppThemeColors c, String title, String desc, List<Widget> children) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.bgSurface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary)),
            const SizedBox(height: 8),
            Text(desc,
                style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.5)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _entryRow(AppThemeColors c, M3uEntry e) {
    final String name = e.title ?? _basename(e.uri);
    final String label =
        '${e.artist?.isNotEmpty == true ? '${e.artist} - ' : ''}$name';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: c.textSecondary),
      ),
    );
  }

  String _basename(String uri) {
    final int slash = uri.lastIndexOf('/');
    String name = slash >= 0 ? uri.substring(slash + 1) : uri;
    final int dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name;
  }
}
