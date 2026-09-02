/// ════════════════════════════════════════════════════════════════════════
/// 选曲弹层（共享组件）：本地曲库 / 在线（网易云 + 哔哩哔哩）双标签搜索。
///
/// - 本地：复用 [musicLibraryProvider]（含「听过的歌自动入曲库」）。
/// - 在线：未登录时提示先登录；已登录则并行搜两源，给真正的选曲渠道。
/// - 顶部「取消」可明确退出选曲（同时底部抽屉仍可下拉关闭）。
///
/// 复用点：点歌提交（order_queue_page）+ DJ 自选播放（station_room_page，R33）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/sources/netease_provider.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../providers/radio/dj_audio_source_provider.dart';

class TrackPicker extends ConsumerStatefulWidget {
  /// [initialSource]：打开时默认选中的音源（电台页 DJ 自选传入 DJ 偏好；
  /// 听众点歌用默认本地，保持原行为）。
  const TrackPicker({super.key, this.initialSource = DjAudioSource.local});

  final DjAudioSource initialSource;

  @override
  ConsumerState<TrackPicker> createState() => _TrackPickerState();
}

class _TrackPickerState extends ConsumerState<TrackPicker> {
  final TextEditingController _q = TextEditingController();
  late bool _online = widget.initialSource != DjAudioSource.local;

  /// 在线时只展示偏好的平台（网易云 / 哔哩哔哩）；本地偏好则两平台都出。
  String? get _preferPlatform {
    switch (widget.initialSource) {
      case DjAudioSource.netease:
        return 'netease';
      case DjAudioSource.bilibili:
        return 'bilibili';
      case DjAudioSource.local:
        return null;
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      height: 520,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: false, label: Text('本地')),
                  ButtonSegment<bool>(value: true, label: Text('在线')),
                ],
                selected: <bool>{_online},
                onSelectionChanged: (Set<bool> s) =>
                    setState(() => _online = s.first),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _q,
            autofocus: true,
            decoration: InputDecoration(
              hintText: _online ? '搜索网易云 / 哔哩哔哩' : '搜索曲名 / 歌手',
              hintStyle: TextStyle(color: c.textSecondary),
              prefixIcon: Icon(Icons.search, color: c.textSecondary),
              filled: true,
              fillColor: c.bgPage,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            style: TextStyle(color: c.textPrimary),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Expanded(child: _online ? _buildOnline(c) : _buildLocal(c)),
        ],
      ),
    );
  }

  Widget _buildLocal(AppThemeColors c) {
    final AsyncValue<List<Track>> lib = ref.watch(musicLibraryProvider);
    return lib.when(
      data: (List<Track> tracks) {
        final String k = _q.text.trim().toLowerCase();
        final List<Track> filtered = k.isEmpty
            ? tracks
            : tracks
                .where((Track t) =>
                    (t.title.toLowerCase().contains(k)) ||
                    (t.artist.toLowerCase().contains(k)))
                .toList();
        if (filtered.isEmpty) {
          return Center(
              child: Text('无匹配', style: TextStyle(color: c.textSecondary)));
        }
        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (_, int i) {
            final Track t = filtered[i];
            return ListTile(
              title: Text(t.title, style: TextStyle(color: c.textPrimary)),
              subtitle: Text(t.artist,
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
              onTap: () => Navigator.of(context).pop(t),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => Center(
          child: Text('读取曲库失败', style: TextStyle(color: c.danger))),
    );
  }

  Widget _buildOnline(AppThemeColors c) {
    final String kw = _q.text.trim();
    if (kw.isEmpty) {
      return Center(
          child: Text('输入关键词搜索在线曲库',
              style: TextStyle(color: c.textSecondary)));
    }
    final bool ne = ref.watch(neteaseAuthProvider).isLoggedIn;
    final bool bi = ref.watch(bilibiliAuthProvider).isLoggedIn;
    if (!ne && !bi) {
      return Center(
          child: Text('点歌需先登录网易云 / 哔哩哔哩',
              style: TextStyle(color: c.textSecondary)));
    }
    final AsyncValue<List<Track>> neRes = ne
        ? ref.watch(neteaseSearchProvider(kw))
        : const AsyncValue<List<Track>>.data(<Track>[]);
    final AsyncValue<List<Track>> biRes = bi
        ? ref.watch(bilibiliSearchProvider(kw))
        : const AsyncValue<List<Track>>.data(<Track>[]);
    final List<Track> neHits = neRes.valueOrNull ?? const <Track>[];
    final List<Track> biHits = biRes.valueOrNull ?? const <Track>[];
    if (neHits.isEmpty && biHits.isEmpty) {
      final bool loading = neRes.isLoading || biRes.isLoading;
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
          child: Text('在线无匹配', style: TextStyle(color: c.textSecondary)));
    }
    final List<Track> all = <Track>[...neHits, ...biHits];
    final String? pref = _preferPlatform;
    final List<Track> shown = pref == null
        ? all
        : all.where((Track t) => t.sourceId == pref).toList();
    if (shown.isEmpty) {
      final bool loading = neRes.isLoading || biRes.isLoading;
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
          child: Text('${pref == 'netease' ? '网易云' : 'B站'} 无匹配',
              style: TextStyle(color: c.textSecondary)));
    }
    return ListView.builder(
      itemCount: shown.length,
      itemBuilder: (_, int i) {
        final Track t = shown[i];
        final String src = t.sourceId == 'netease'
            ? '网易云'
            : t.sourceId == 'bilibili'
                ? 'B站'
                : '本地';
        return ListTile(
          title: Text(t.title, style: TextStyle(color: c.textPrimary)),
          subtitle: Text('$src · ${t.artist}',
              style: TextStyle(color: c.textSecondary, fontSize: 12)),
          onTap: () => Navigator.of(context).pop(t),
        );
      },
    );
  }
}