import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../models/track.dart';
import '../../../providers/audio/playback_notifier.dart';
import '../../../providers/voicehub/voicehub_provider.dart';
import '../../../services/voicehub/voicehub_client.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_views.dart';

/// VoiceHub 校园广播站点歌对接页（可选数据源；自研 relay 电台保留）。
///
/// - 配置：服务器地址 + API Key（持久化）
/// - 点歌列表（open/songs.get）与排期（open/schedules.get）展示
/// - 关键词搜索点歌
class VoiceHubPage extends ConsumerStatefulWidget {
  const VoiceHubPage({super.key});

  @override
  ConsumerState<VoiceHubPage> createState() => _VoiceHubPageState();
}

class _VoiceHubPageState extends ConsumerState<VoiceHubPage> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _searchCtrl;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _keyCtrl = TextEditingController();
    _searchCtrl = TextEditingController();
    Future<void>.microtask(() {
      if (!mounted) return;
      final VoiceHubConfig cfg = ref.read(voiceHubProvider).config;
      _urlCtrl.text = cfg.baseUrl;
      _keyCtrl.text = cfg.apiKey;
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(voiceHubProvider.notifier).configure(
          VoiceHubConfig(baseUrl: _urlCtrl.text, apiKey: _keyCtrl.text),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_urlCtrl.text.trim().isEmpty ? '已清除 VoiceHub 配置' : '已保存并同步'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _search() async {
    final String kw = _searchCtrl.text.trim();
    setState(() => _searching = true);
    final List<VoiceHubSong> r =
        await ref.read(voiceHubProvider.notifier).search(kw);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searchResults = r;
    });
  }

  List<VoiceHubSong> _searchResults = const <VoiceHubSong>[];

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final VoiceHubState s = ref.watch(voiceHubProvider);

    return PageScaffold(
      title: 'VoiceHub 点歌',
      actions: <Widget>[
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: s.config.enabled
              ? () => ref.read(voiceHubProvider.notifier).refresh()
              : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── 配置卡 ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('VoiceHub 服务器',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      hintText: 'https://voicehub.example.com',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _keyCtrl,
                    decoration: const InputDecoration(
                      hintText: 'API Key（开放接口使用）',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.cloud_sync_outlined, size: 16),
                          label: const Text('保存并同步'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '搜索点歌（标题/歌手）',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        onPressed: _search,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ── 内容区 ─────────────────────────────
          Expanded(child: _buildBody(c, s)),
        ],
      ),
    );
  }

  /// 内容区：点歌 / 排期两个 Tab（排期数据 fetchSchedules 已取，此前未展示）。
  Widget _buildBody(AppThemeColors c, VoiceHubState s) {
    if (!s.config.enabled) {
      return const EmptyView(title: '未配置 VoiceHub', message: '填入服务器地址与 API Key 后点「保存并同步」');
    }
    if (s.loading && s.songs.isEmpty && s.schedules.isEmpty) {
      return const LoadingView(label: '同步中…');
    }
    if (s.error.isNotEmpty) {
      return ErrorView(message: s.error, onRetry: () => ref.read(voiceHubProvider.notifier).refresh());
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TabBar(
            labelColor: c.accent,
            unselectedLabelColor: c.textSecondary,
            indicatorColor: c.accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: <Widget>[
              Tab(text: '点歌（${s.songs.length}）'),
              Tab(text: '排期（${s.schedules.length}）'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _songList(c, s),
                _scheduleList(c, s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 点歌列表（关键词搜索优先于同步结果）。
  Widget _songList(AppThemeColors c, VoiceHubState s) {
    final List<VoiceHubSong> songs =
        _searchResults.isNotEmpty ? _searchResults : s.songs;
    if (songs.isEmpty) {
      return const EmptyView(title: '暂无点歌', message: 'VoiceHub 歌库为空或等待排期');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: songs.length,
      itemBuilder: (BuildContext context, int i) {
        final VoiceHubSong song = songs[i];
        final int hot = song.voteCount > 0 ? song.voteCount : song.playCount;
        return ListTile(
          dense: true,
          onTap: () => _playSong(song),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: clipCover(song.coverUrl, c),
          ),
          title: Text(song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textPrimary, fontSize: 14)),
          subtitle: Text([
            song.artist,
            if (song.requester.isNotEmpty) '投稿 ${song.requester}',
          ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textSecondary, fontSize: 12)),
          trailing: hot > 0
              ? Text('🔥$hot',
                  style: TextStyle(color: c.textTertiary, fontSize: 11))
              : null,
        );
      },
    );
  }

  /// 排期列表（按播放日期展示，贴近 VoiceHub 真实卡片：封面+标题+投稿人+热度）。
  Widget _scheduleList(AppThemeColors c, VoiceHubState s) {
    final List<VoiceHubSchedule> list = s.schedules;
    if (list.isEmpty) {
      return const EmptyView(title: '暂无排期', message: 'VoiceHub 暂无播种排期');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: list.length,
      itemBuilder: (BuildContext context, int i) {
        final VoiceHubSchedule sch = list[i];
        return ListTile(
          dense: true,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.bgSurfaceSunken,
              borderRadius: BorderRadius.circular(8),
            ),
            child: clipCover(sch.coverUrl, c),
          ),
          title: Text(sch.songTitle.isEmpty ? '未命名曲目' : sch.songTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textPrimary, fontSize: 14)),
          subtitle: Text([
            sch.songArtist,
            if (sch.requester.isNotEmpty) '投稿 ${sch.requester}',
            if (sch.playDate.isNotEmpty) sch.playDate,
          ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textSecondary, fontSize: 12)),
          trailing: sch.voteCount > 0
              ? Text('🔥${sch.voteCount}',
                  style: TextStyle(color: c.textTertiary, fontSize: 11))
              : null,
        );
      },
    );
  }

  /// 播放 VoiceHub 歌曲：网易云走既有 `netease://song/<id>` 占位解析链；
  /// B站/未知平台暂不支持直接播（VoiceHub 侧 CID 解析未对齐）。
  Future<void> _playSong(VoiceHubSong song) async {
    final String platform = song.platform.toLowerCase();
    if (platform.contains('netease') && song.musicId.isNotEmpty) {
      final String msg = await ref
          .read(playbackActionsProvider)
          .playTrack(
            Track(
              title: song.title,
              artist: song.artist,
              uri: 'netease://song/${song.musicId}',
              source: TrackSource.stream,
              sourceId: 'voicehub:${song.id}',
              extras: <String, dynamic>{'coverUrl': song.coverUrl},
            ),
          );
      if (!mounted) return;
      if (msg.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('暂不支持该平台直播（${song.platform.isEmpty ? '未知' : song.platform}）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget clipCover(String? url, AppThemeColors c) {
    if (url == null || url.isEmpty) {
      return Icon(Icons.music_note, size: 18, color: c.textTertiary);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.music_note, size: 18, color: c.textTertiary),
      ),
    );
  }
}