/// 聚合搜索页（R26skel-b5：媒体源筛选 + 登录 + 免责声明）。
///
/// 把网易云 / 哔哩哔哩 / 本地曲库收进同一页：
/// - 顶部源筛选 chips：全部 / 本地 / 网易云 / 哔哩哔哩；
/// - 网易云 / B站未登录时显示登录入口，登录前弹**免责声明**；
/// - 结果行带源徽标（本地 / 网易云 / B站），点击播放；
/// - 播放地址解析失败（登录失效 / 无版权 / 网络）经 playErrorStream 提示。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/sources/netease_provider.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/sources/netease_login_sheet.dart';
import '../../widgets/sources/bilibili_login_sheet.dart';
import '../../widgets/notification/app_notify.dart';

/// 媒体源筛选。
enum _SrcFilter {
  all('全部'),
  local('本地'),
  netease('网易云'),
  bilibili('哔哩哔哩');

  const _SrcFilter(this.label);

  final String label;
}

/// 聚合搜索页。
class AggregateSearchPage extends ConsumerStatefulWidget {
  const AggregateSearchPage({super.key});

  @override
  ConsumerState<AggregateSearchPage> createState() =>
      _AggregateSearchPageState();
}

class _AggregateSearchPageState extends ConsumerState<AggregateSearchPage> {
  final TextEditingController _queryCtrl = TextEditingController();
  String _keyword = '';
  _SrcFilter _filter = _SrcFilter.all;
  StreamSubscription<String>? _playErrorSub;
  final List<String> _history = <String>[];
  bool _disclaimerShown = false;

  @override
  void initState() {
    super.initState();
    _playErrorSub =
        ref.read(audioServiceProvider).playErrorStream.listen(_onPlayError);
  }

  @override
  void dispose() {
    _playErrorSub?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onPlayError(String message) {
    if (!mounted) return;
    appNotify(context, message);
  }

  void _submit(String raw) {
    final String kw = raw.trim();
    if (kw.isNotEmpty && !_history.contains(kw)) {
      _history.insert(0, kw);
      if (_history.length > 8) _history.removeLast();
    }
    setState(() => _keyword = kw);
  }

  /// 登录前免责声明（仅首次弹一次）。
  Future<bool> _ensureDisclaimer() async {
    if (_disclaimerShown) return true;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: const Text('免责声明'),
        content: const Text(
          '网易云 / 哔哩哔哩均为第三方音乐源，仅供个人学习与研究使用。\n\n'
          '内容版权归原平台及权利人所有；请勿用于商业用途或二次分发。\n\n'
          '登录即表示您已知悉并同意以上条款。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('不同意'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _disclaimerShown = true;
    return ok == true;
  }

  Future<void> _openNeteaseLogin() async {
    if (!await _ensureDisclaimer()) return;
    final bool? ok = await showNeteaseLoginSheet(context);
    if (ok == true && mounted) appNotify(context, '已登录网易云');
  }

  Future<void> _openBilibiliLogin() async {
    if (!await _ensureDisclaimer()) return;
    final bool? ok = await showBilibiliLoginSheet(context);
    if (ok == true && mounted) appNotify(context, '已登录哔哩哔哩');
  }

  Future<void> _logoutNetease() async {
    await ref.read(neteaseAuthProvider.notifier).logout();
    if (mounted) setState(() {});
  }

  Future<void> _logoutBilibili() async {
    await ref.read(bilibiliAuthProvider.notifier).logout();
    if (mounted) setState(() {});
  }

  Future<void> _play(Track t) async {
    final String msg = await ref.read(playbackActionsProvider).playTrack(t);
    if (msg.isNotEmpty && mounted) appNotify(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: '聚合搜索',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSearchField(),
          const SizedBox(height: AppSpace.sm),
          _buildSourceFilter(),
          const SizedBox(height: AppSpace.sm),
          _buildLoginStrip(),
          if (_keyword.isEmpty && _history.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            _buildHistory(),
          ],
          const SizedBox(height: AppSpace.md),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  /// 源筛选 chips：全部 / 本地 / 网易云 / 哔哩哔哩。
  Widget _buildSourceFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final _SrcFilter f in _SrcFilter.values) ...<Widget>[
            ChoiceChip(
              label: Text(f.label, style: context.appText.caption),
              selected: _filter == f,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _filter = f),
            ),
            if (f != _SrcFilter.values.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  /// 登录状态条（网易云 / B站，未登录显示登录按钮）。
  Widget _buildLoginStrip() {
    final bool ne = ref.watch(neteaseAuthProvider).isLoggedIn;
    final bool bi = ref.watch(bilibiliAuthProvider).isLoggedIn;
    final bool need = _filter == _SrcFilter.netease && !ne ||
        _filter == _SrcFilter.bilibili && !bi ||
        _filter == _SrcFilter.all && (!ne || !bi);
    if (!need) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        if (!ne)
          ActionChip(
            avatar: Icon(Icons.music_note_rounded,
                size: 14, color: context.appColors.accent),
            label: Text('登录网易云', style: context.appText.caption),
            visualDensity: VisualDensity.compact,
            onPressed: _openNeteaseLogin,
          ),
        if (!bi)
          ActionChip(
            avatar: Icon(Icons.video_library_outlined,
                size: 14, color: context.appColors.accent),
            label: Text('登录哔哩哔哩', style: context.appText.caption),
            visualDensity: VisualDensity.compact,
            onPressed: _openBilibiliLogin,
          ),
      ],
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('搜索历史', style: context.appText.artist),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: _history.map((String h) {
            return ActionChip(
              label: Text(h, style: context.appText.caption),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                _queryCtrl.text = h;
                _submit(h);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _queryCtrl,
      onSubmitted: _submit,
      textInputAction: TextInputAction.search,
      enableSuggestions: false,
      autocorrect: false,
      style: context.appText.body,
      decoration: InputDecoration(
        hintText: '搜索本地 / 网易云 / 哔哩哔哩（歌手 / 歌名）',
        hintStyle: context.appText.artist,
        prefixIcon: Icon(Icons.search_rounded,
            size: AppSize.iconSm, color: context.appColors.iconInactive),
        suffixIcon: _keyword.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close_rounded,
                    size: AppSize.iconSm, color: context.appColors.iconInactive),
                onPressed: () {
                  _queryCtrl.clear();
                  _submit('');
                },
              ),
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
    );
  }

  Widget _buildContent() {
    if (_keyword.isEmpty) {
      return _HintPanel(
        icon: Icons.search_rounded,
        message: '输入关键词，搜索本地 / 网易云 / 哔哩哔哩并在线播放',
      );
    }
    return switch (_filter) {
      _SrcFilter.local => _buildLocal(),
      _SrcFilter.netease => _buildNetease(),
      _SrcFilter.bilibili => _buildBilibili(),
      _SrcFilter.all => _buildAll(),
    };
  }

  /// 本地：从曲库聚合中按标题/歌手过滤。
  Widget _buildLocal() {
    final AsyncValue<List<Track>> lib = ref.watch(musicLibraryProvider);
    return lib.when(
      data: (List<Track> tracks) {
        final String kw = _keyword.toLowerCase();
        final List<Track> hits = tracks
            .where((Track t) =>
                t.title.toLowerCase().contains(kw) ||
                t.artist.toLowerCase().contains(kw))
            .toList();
        if (hits.isEmpty) {
          return const _HintPanel(
              icon: Icons.music_off_rounded, message: '本地没有匹配的曲目');
        }
        return _TrackList(tracks: hits, onTap: _play);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace st) => const _HintPanel(
          icon: Icons.error_outline_rounded, message: '本地曲库加载失败'),
    );
  }

  Widget _buildNetease() {
    final bool ne = ref.watch(neteaseAuthProvider).isLoggedIn;
    if (!ne) {
      return _HintPanel(
        icon: Icons.lock_outline_rounded,
        message: '未登录网易云，登录后可搜索曲库',
        actionLabel: '登录',
        onAction: _openNeteaseLogin,
      );
    }
    final AsyncValue<List<Track>> result =
        ref.watch(neteaseSearchProvider(_keyword));
    return result.when(
      data: (List<Track> tracks) => tracks.isEmpty
          ? const _HintPanel(
              icon: Icons.music_off_rounded, message: '网易云没有找到相关歌曲')
          : _TrackList(tracks: tracks, onTap: _play, sourceTag: '网易云 · 音乐源'),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace st) {
        final bool authFail = neteaseIsAuthFailure(e);
        return _HintPanel(
          icon: Icons.error_outline_rounded,
          message: neteaseErrorText(e),
          actionLabel: authFail ? '去登录' : '重试',
          onAction: authFail
              ? _openNeteaseLogin
              : () => ref.invalidate(neteaseSearchProvider(_keyword)),
        );
      },
    );
  }

  Widget _buildBilibili() {
    final bool bi = ref.watch(bilibiliAuthProvider).isLoggedIn;
    if (!bi) {
      return _HintPanel(
        icon: Icons.lock_outline_rounded,
        message: '未登录哔哩哔哩，登录后可搜索视频源',
        actionLabel: '登录',
        onAction: _openBilibiliLogin,
      );
    }
    final AsyncValue<List<Track>> result =
        ref.watch(bilibiliSearchProvider(_keyword));
    return result.when(
      data: (List<Track> tracks) => tracks.isEmpty
          ? const _HintPanel(
              icon: Icons.music_off_rounded, message: 'B站没有找到相关视频')
          : _TrackList(tracks: tracks, onTap: _play, sourceTag: 'B站 · 视频源'),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace st) {
        final String msg = bilibiliErrorText(e);
        return _HintPanel(
          icon: Icons.error_outline_rounded,
          message: msg,
          actionLabel: '重试',
          onAction: () => ref.invalidate(bilibiliSearchProvider(_keyword)),
        );
      },
    );
  }

  /// 全部：本地 + 网易云（已登录）+ B站（已登录）合并展示。
  Widget _buildAll() {
    final bool ne = ref.watch(neteaseAuthProvider).isLoggedIn;
    final bool bi = ref.watch(bilibiliAuthProvider).isLoggedIn;
    final AsyncValue<List<Track>> lib = ref.watch(musicLibraryProvider);
    final String kw = _keyword.toLowerCase();
    final List<Track> localHits = lib.valueOrNull
            ?.where((Track t) =>
                t.title.toLowerCase().contains(kw) ||
                t.artist.toLowerCase().contains(kw))
            .toList() ??
        const <Track>[];
    // 远程源并行搜索（未登录的源跳过）。
    final Future<List<Track>> neF = ne
        ? ref.watch(neteaseSearchProvider(_keyword).future).catchError((_) => const <Track>[])
        : Future.value(const <Track>[]);
    final Future<List<Track>> biF = bi
        ? ref.watch(bilibiliSearchProvider(_keyword).future).catchError((_) => const <Track>[])
        : Future.value(const <Track>[]);

    return FutureBuilder<List<List<Track>>>(
      future: Future.wait(<Future<List<Track>>>[neF, biF]),
      builder: (BuildContext context, AsyncSnapshot<List<List<Track>>> snap) {
        final List<Track> neHits =
            snap.data != null && snap.data!.isNotEmpty ? snap.data![0] : const <Track>[];
        final List<Track> biHits =
            snap.data != null && snap.data!.length > 1 ? snap.data![1] : const <Track>[];
        final List<Track> all = <Track>[
          for (final Track t in localHits) t,
          for (final Track t in neHits) t,
          for (final Track t in biHits) t,
        ];
        if (all.isEmpty) {
          return const _HintPanel(
              icon: Icons.search_off_rounded, message: '没有匹配的结果');
        }
        return _TrackList(
          tracks: all,
          onTap: _play,
          // 行内按 sourceId 打「源 · 类型」徽标：网易云=音乐源，B站=视频源。
          tagOf: (Track t) => switch (t.sourceId) {
            'netease' => '网易云 · 音乐源',
            'bilibili' => 'B站 · 视频源',
            'local' => '本地 · 音乐源',
            _ => null,
          },
        );
      },
    );
  }
}

/// 居中提示面板（可带操作按钮）。
class _HintPanel extends StatelessWidget {
  const _HintPanel({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: context.appColors.iconInactive),
            const SizedBox(height: AppSpace.md),
            Text(
              message,
              style: context.appText.bodyMuted,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpace.md),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 结果列表（带源徽标）。
class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.tracks,
    required this.onTap,
    this.sourceTag,
    this.tagOf,
  });

  final List<Track> tracks;
  final ValueChanged<Track> onTap;

  /// 统一源标签（单源列表用）。
  final String? sourceTag;

  /// 按曲目给标签（聚合列表用）。
  final String? Function(Track)? tagOf;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.xs),
      itemBuilder: (BuildContext _, int i) {
        final Track t = tracks[i];
        final String? tag =
            tagOf != null ? tagOf!(t) : sourceTag;
        return _TrackTile(track: t, tag: tag, onTap: () => onTap(t));
      },
    );
  }
}

/// 单条搜索结果。
class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, this.tag, required this.onTap});

  final Track track;
  final String? tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appColors.bgCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: _CoverBox(url: track.coverUrl),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      track.title,
                      style: context.appText.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            track.artist,
                            style: context.appText.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (track.duration != null) ...<Widget>[
                          const SizedBox(width: 6),
                          Text(
                            _fmt(track.duration!),
                            style: context.appText.artist
                                ?.copyWith(color: context.appColors.iconInactive),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (tag != null) ...<Widget>[
                const SizedBox(width: AppSpace.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.appColors.accentSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(tag!,
                      style: context.appText.artist
                          ?.copyWith(color: context.appColors.accent)),
                ),
              ],
              const SizedBox(width: AppSpace.sm),
              Icon(Icons.play_circle_outline_rounded,
                  size: AppSize.icon, color: context.appColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// 时长 `mm:ss`（超过 1h 显示 `h:mm:ss`）。
String _fmt(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes.remainder(60);
  final int s = d.inSeconds.remainder(60);
  final String ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// 封面：网络图失败 / 缺失时回落为音符占位。
class _CoverBox extends StatelessWidget {
  const _CoverBox({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final String? u = url;
    if (u == null || u.isEmpty) return const _CoverFallback();
    return Image.network(
      u,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _CoverFallback(),
      loadingBuilder: (BuildContext context, Widget child,
              ImageChunkEvent? progress) =>
          progress == null ? child : const _CoverFallback(),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.appColors.accentSoft,
      child: Icon(Icons.music_note_rounded,
          size: 20, color: context.appColors.accent),
    );
  }
}
