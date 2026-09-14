import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/track.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/sources/netease_provider.dart';
import '../../services/audio/sources/netease/netease_source.dart';
import '../common/page_scaffold.dart';
import '../common/state_views.dart';
import '../notification/app_notify.dart';
import 'netease_auth_hint.dart';

/// 网易云曲目列表页（共享薄壳）。
///
/// 统一承载「每日推荐 / 私人漫游」这类「登录后才有的网易云曲目流」：
/// 统一 tile（封面 + 标题 + 歌手 + VIP 角标 + 推荐理由）、统一三态
/// （加载 / 空 / 错误）、统一未登录引导、统一登录失效引导，以及可选的
/// 无限流自动加载（[infinite] 为真时，滚动到底自动追加 [NeteaseSource.roam]）。
///
/// 这样 daily / roam 两个页面只保留「参数 + 文案」差异，不再各自复制
/// tile / 引导 / 状态逻辑（约 300 行重复）。
class NeteaseTrackListPage extends ConsumerStatefulWidget {
  const NeteaseTrackListPage({
    super.key,
    required this.title,
    required this.firstProvider,
    this.infinite = false,
    this.loadMore,
    this.showReason = false,
    this.emptyTitle = '暂无可推荐曲目',
    this.emptyMessage = '稍后回来，网易云会为你更新',
    this.loginHintTitle,
    this.loginHintMessage,
  });

  /// 页面标题（如「每日推荐」「漫游」）。
  final String title;

  /// 首批数据 provider（`AutoDisposeFutureProvider<List<Track>>`）。
  final AutoDisposeFutureProvider<List<Track>> firstProvider;

  /// 是否无限流（漫游 = true；滚动到底自动追加）。
  final bool infinite;

  /// 自定义「加载下一批」回调（收到上一批累计条数作为 offset）。
  ///
  /// 为空时沿用 [NeteaseSource.roam]（私人漫游无限流）；非空时用于歌单等
  /// 有明确分页语义的来源（配合 [infinite] 打开触底加载）。
  final Future<List<Track>> Function(int offset)? loadMore;

  /// 是否展示推荐理由行（每日推荐 = true）。
  final bool showReason;

  final String emptyTitle;
  final String emptyMessage;
  final String? loginHintTitle;
  final String? loginHintMessage;

  @override
  ConsumerState<NeteaseTrackListPage> createState() =>
      _NeteaseTrackListPageState();
}

class _NeteaseTrackListPageState extends ConsumerState<NeteaseTrackListPage> {
  final List<Track> _loaded = <Track>[];
  final Set<String> _seenUris = <String>{};
  bool _loadingMore = false;
  bool _failed = false;
  bool _hasMore = true;
  int _nextOffset = 0;

  /// 把一批曲目按 [Track.uri] 去重后追加到 [_loaded]。
  ///
  /// 返回本批**实际新增**的条数（可能为 0，表示已到底 / 全是重复）。
  int _appendDeduped(List<Track> batch) {
    final int before = _loaded.length;
    for (final Track t in batch) {
      if (_seenUris.add(t.uri)) _loaded.add(t);
    }
    return _loaded.length - before;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    if (!widget.infinite && widget.loadMore == null) return;
    setState(() {
      _loadingMore = true;
      _failed = false;
    });
    try {
      final Future<List<Track>> Function(int)? loader = widget.loadMore;
      final List<Track> batch;
      if (loader != null) {
        batch = await loader(_nextOffset);
      } else {
        final NeteaseSource src = ref.read(neteaseSourceProvider);
        batch = await src.roam();
      }
      if (!mounted) return;
      setState(() {
        // offset 用**原始**批次长度推进（即便有重复行也保持与服务端一致）。
        _nextOffset += batch.length;
        // 去重后新增 0 条 → 认定已到底，避免反复请求同一 offset 死循环。
        if (_appendDeduped(batch) == 0) _hasMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _resetAndRefresh() {
    setState(() {
      _loaded.clear();
      _seenUris.clear();
      _loadingMore = false;
      _failed = false;
      _hasMore = true;
      _nextOffset = 0;
    });
    ref.invalidate(widget.firstProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Track>> first = ref.watch(widget.firstProvider);
    final bool loggedIn = ref.watch(neteaseAuthProvider).isLoggedIn;

    // 自动刷新（#bug-fix）：首屏把 provider 数据填充到 _loaded（仅在空时）；
    // 之后 provider 数据变化（重新登录 / 切换账号 / 服务端更新推荐流）时，
    // 若首屏批次与已加载内容不一致则整体替换，列表不再陈旧。
    // 用 ref.listen 在 build 阶段之外响应变化，避免「build 期间改状态」反模式。
    ref.listen<AsyncValue<List<Track>>>(widget.firstProvider, (
      _,
      AsyncValue<List<Track>> next,
    ) {
      next.whenData((List<Track> list) {
        if (!mounted) return;
        if (_loaded.isEmpty) {
          setState(() {
            _seenUris.clear();
            _appendDeduped(list);
            // 首批条数即下一页的起跑 offset（否则首次触底会重取首批 → 全是重复）。
            _nextOffset = list.length;
          });
        } else if (!_firstBatchEquals(_loaded, list)) {
          setState(() {
            _loaded.clear();
            _seenUris.clear();
            _appendDeduped(list);
            _nextOffset = list.length;
            _hasMore = true;
          });
        }
      });
    });

    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: widget.title,
          actions: <Widget>[
            if (loggedIn && _loaded.isNotEmpty)
              IconButton(
                onPressed: _resetAndRefresh,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '刷新',
              ),
          ],
          body: !loggedIn
              ? _LoginHint(
                  title: widget.loginHintTitle ?? '${widget.title}需要登录网易云',
                  message:
                      widget.loginHintMessage ?? '登录后即可查看 $widget.title 内容',
                )
              : first.when(
                  skipLoadingOnRefresh: true,
                  data: (_) => _buildTrackListBody(),
                  loading: () => _loaded.isNotEmpty
                      ? _buildTrackListBody()
                      : const LoadingView(),
                  error: (Object e, StackTrace st) {
                    // 普通错误 + 已有缓存：保留列表 + 顶部错误条，不全屏替换
                    // （登录失效属强信号，仍走整页登录引导，不清缓存也无需保留）。
                    if (_loaded.isNotEmpty && !neteaseIsAuthFailure(e)) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SourceErrorBar(
                            sourceLabel: '网易云',
                            message: neteaseErrorText(e),
                            onRetry: () => ref.invalidate(widget.firstProvider),
                          ),
                          Expanded(child: _buildTrackListBody()),
                        ],
                      );
                    }
                    return neteaseIsAuthFailure(e)
                        ? NeteaseAuthExpiredHint(
                            onRefreshed: (_) => _resetAndRefresh(),
                          )
                        : ErrorView(
                            message: neteaseErrorText(e),
                            onRetry: () => ref.invalidate(widget.firstProvider),
                          );
                  },
                ),
        ),
      ),
    );
  }

  /// 渲染曲目列表（含空态 / 无限流 / 触底加载三态）。
  ///
  /// `first.when` 的 data / loading（有缓存时）/ error（有缓存时）三分支共用，
  /// 避免刷新期间卸载列表。列表内容始终来自 `_loaded`（首次批次由 `ref.listen`
  /// 填充、触底追加由 `_loadMore` 累积），与搜索页「整列表作队列」同构。
  Widget _buildTrackListBody() {
    if (_loaded.isEmpty) {
      return EmptyView(
        title: widget.emptyTitle,
        message: widget.emptyMessage,
      );
    }
    if (!widget.infinite && widget.loadMore == null) {
      return ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: _loaded.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (BuildContext context, int i) => _TrackTile(
          track: _loaded[i],
          showReason: widget.showReason,
          onTap: () => _playTrack(_loaded[i]),
        ),
      );
    }
    // 无限流：滚动到底自动加载更多（去掉手动按钮，操作更简）。
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification n) {
        if (n is ScrollUpdateNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
          _loadMore();
        }
        return false;
      },
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: _loaded.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (BuildContext context, int i) {
          if (i == _loaded.length) {
            if (_failed) {
              return FilledButton(
                onPressed: _loadMore,
                child: const Text('加载失败，点击重试'),
              );
            }
            if (_loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            if (!_hasMore) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '已经到底了',
                    style: context.appText.caption,
                  ),
                ),
              );
            }
            return const SizedBox(height: 28);
          }
          return _TrackTile(
            track: _loaded[i],
            showReason: widget.showReason,
            onTap: () => _playTrack(_loaded[i]),
          );
        },
      ),
    );
  }

  Future<void> _playTrack(Track t) async {
    // 缺陷3：把当前整个列表作为播放队列传入，使自动续播在列表内循环
    // （与聚合搜索页 `_play(t, all)` 语义一致）。此前只传单曲，从歌单点第 5 首
    // 播完即停。
    final String msg = await ref
        .read(playbackActionsProvider)
        .playTrack(t, queue: _loaded);
    if (!mounted || msg.isEmpty) return;
    appNotify(context, msg);
  }
}

/// 比较已加载列表的「首屏批次」是否与 [first] 一致（按 uri）。
///
/// 仅比前 [first.length] 项，忽略无限漫游模式追加的后续批次——首屏批次未变
/// 时保留漫游追加项，首屏批次变化（换账号 / 服务端更新）时才整体替换。
bool _firstBatchEquals(List<Track> loaded, List<Track> first) {
  if (loaded.length < first.length) return false;
  for (int i = 0; i < first.length; i++) {
    if (loaded[i].uri != first[i].uri) return false;
  }
  return true;
}

/// 统一曲目行：封面 + 标题 + 歌手 + 可选推荐理由 + VIP 角标。
class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.showReason,
    required this.onTap,
  });

  final Track track;
  final bool showReason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final String? reason = track.extras?['reason'] as String?;
    final int fee = (track.extras?['fee'] as int?) ?? 0;
    final bool vip = fee == 1 || fee == 4;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: c.bgPlaceholder,
                borderRadius: BorderRadius.circular(12),
                image: track.coverUrl != null
                    ? DecorationImage(
                        image: NetworkImage(track.coverUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: track.coverUrl == null
                  ? Icon(
                      Icons.music_note_rounded,
                      size: 22,
                      color: c.iconInactive,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          track.title,
                          style: context.appText.trackName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (vip) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'VIP',
                            style: context.appText.caption.copyWith(
                              color: c.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    style: context.appText.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showReason &&
                      reason != null &&
                      reason.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      reason,
                      style: context.appText.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 未登录引导态（统一版式）。
class _LoginHint extends StatelessWidget {
  const _LoginHint({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.lock_outline_rounded, size: 40, color: c.iconInactive),
            const SizedBox(height: 16),
            Text(title, style: context.appText.subtitle),
            const SizedBox(height: 6),
            Text(
              message,
              style: context.appText.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
