import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../models/track.dart';
import '../../../providers/audio/audio_providers.dart';
import '../../../services/musicbrainz/scraper.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_views.dart';
import '../../../widgets/notification/app_notify.dart';

/// 刮削器（T12）：MusicBrainz 官方录音元数据查询。
///
/// 输入标题（+ 艺术家）→ 查询官方录音库 → 展示命中（专辑 / 时长 / 封面），
/// 可将元数据复制出，用于给整轨/错名文件补全标签。
class ScraperPage extends ConsumerStatefulWidget {
  const ScraperPage({super.key});

  @override
  ConsumerState<ScraperPage> createState() => _ScraperPageState();
}

class _ScraperPageState extends ConsumerState<ScraperPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _artist = TextEditingController();
  final MusicBrainzScraper _scraper = MusicBrainzScraper();
  List<ScrapeHit>? _hits;
  Object? _error;
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  void _fillFromCurrent() {
    final Track? t = ref.read(currentTrackProvider).valueOrNull;
    if (t == null) {
      appNotify(context, '当前没有正在播放的歌曲');
      return;
    }
    // 本地扫描源才有完整标题/歌手；网络源直接取标题。
    _title.text = t.title;
    _artist.text = t.artist;
  }

  Future<void> _search() async {
    final String title = _title.text.trim();
    if (title.isEmpty) {
      appNotify(context, '请填写歌曲标题');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final List<ScrapeHit> hits = await _scraper.search(
        title: title,
        artist: _artist.text.trim().isEmpty ? null : _artist.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _copy(ScrapeHit h) async {
    final String text = [
      '标题：${h.title}',
      '艺术家：${h.artist}',
      if (h.album != null) '专辑：${h.album}',
      if (h.durationMs != null) '时长：${_fmtMs(h.durationMs!)}',
      if (h.recordingId != null) 'MBID：${h.recordingId}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      appNotify(context, '元数据已复制，可粘贴到标签工具使用');
    }
  }

  String _fmtMs(int ms) {
    final int m = ms ~/ 60000;
    final int s = (ms % 60000) ~/ 1000;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return PageScaffold(
      title: '刮削器',
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
                Text('查询 MusicBrainz 官方曲库元数据',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary)),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: _title,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                      labelText: '歌曲标题', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpace.xs),
                TextField(
                  controller: _artist,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                      labelText: '艺术家（可选）', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _fillFromCurrent,
                      icon: const Icon(Icons.music_note_rounded, size: 16),
                      label: const Text('从当前曲目填充'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _loading ? null : _search,
                      style: FilledButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: c.onAccent),
                      icon: _loading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search_rounded, size: 18),
                      label: const Text('查询'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  '数据来源 MusicBrainz/Cover Art Archive（公开元数据库）。'
                  '每个搜索间隔约 1.3 秒，请勿连续点击。',
                  style: TextStyle(fontSize: 11.5, color: c.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          if (_error != null)
            ErrorView(
              message: '$_error',
              onRetry: _search,
            ),
          if (_loading) const LoadingView(),
          if (!_loading && !_searched)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: EmptyView(title: '输入标题开始刮削', message: '查询结果将在这里展示'),
            ),
          if (!_loading && _searched && _error == null) ...<Widget>[
            if ((_hits ?? const <ScrapeHit>[]).isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: EmptyView(title: '没有匹配结果', message: '换一个关键词或加上艺术家再试'),
              )
            else
              for (final ScrapeHit h in _hits!)
                _HitCard(c: c, hit: h, onCopy: () => _copy(h)),
          ],
        ],
      ),
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({required this.c, required this.hit, required this.onCopy});
  final AppThemeColors c;
  final ScrapeHit hit;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Container(
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: AppRadius.brLg,
        ),
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: AppRadius.brSm,
              child: SizedBox(
                width: 48,
                height: 48,
                child: CoverImage(coverUrl: hit.coverUrl, c: c),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary)),
                  Text(hit.artist.isEmpty ? '未知艺术家' : hit.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.textSecondary)),
                  if (hit.album != null)
                    Text('专辑：${hit.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12, color: c.textTertiary)),
                  if (hit.durationMs != null)
                    Text(
                      '时长：${_fmt(hit.durationMs!)}',
                      style: TextStyle(fontSize: 12, color: c.textTertiary),
                    ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '复制元数据',
              icon: Icon(Icons.copy_rounded, size: 18, color: c.iconInactive),
              onPressed: onCopy,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int ms) {
    final int m = ms ~/ 60000;
    final int s = (ms % 60000) ~/ 1000;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// 51 边框占位封面：有图显示缩略图，无图/加载失败显示音符占位。
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.coverUrl, required this.c});
  final String? coverUrl;
  final AppThemeColors c;

  @override
  Widget build(BuildContext context) {
    final String? url = coverUrl;
    if (url == null) return _placeholder();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
      loadingBuilder: (BuildContext ctx, Widget child, ImageChunkEvent? p) =>
          p == null ? child : _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: c.bgPlaceholder,
        alignment: Alignment.center,
        child: Icon(Icons.music_note_rounded, size: 22, color: c.iconInactive),
      );
}