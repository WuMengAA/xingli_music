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

  /// 是否展示推荐理由行（每日推荐 = true）。
  final bool showReason;

  final String emptyTitle;
  final String emptyMessage;
  final String? loginHintTitle;
  final String? loginHintMessage;

  @override
  ConsumerState<NeteaseTrackListPage> createState() => _NeteaseTrackListPageState();
}

class _NeteaseTrackListPageState extends ConsumerState<NeteaseTrackListPage> {
  final List<Track> _loaded = <Track>[];
  bool _loadingMore = false;
  bool _failed = false;

  Future<void> _loadMore() async {
    if (_loadingMore || !widget.infinite) return;
    setState(() {
      _loadingMore = true;
      _failed = false;
    });
    try {
      final NeteaseSource src = ref.read(neteaseSourceProvider);
      final List<Track> batch = await src.roam();
      if (mounted) setState(() => _loaded.addAll(batch));
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _resetAndRefresh() {
    setState(() {
      _loaded.clear();
      _loadingMore = false;
      _failed = false;
    });
    ref.invalidate(widget.firstProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Track>> first = ref.watch(widget.firstProvider);
    final bool loggedIn = ref.watch(neteaseAuthProvider).isLoggedIn;

    first.whenData((List<Track> list) {
      if (_loaded.isEmpty && list.isNotEmpty) {
        _loaded.addAll(list);
      }
    });

    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: widget.title,
          actions: <Widget>[
            if (loggedIn && _loaded.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _resetAndRefresh,
                tooltip: '刷新',
              ),
          ],
          body: !loggedIn
              ? _LoginHint(
                  title: widget.loginHintTitle ?? '${widget.title}需要登录网易云',
                  message: widget.loginHintMessage ?? '登录后即可查看 $widget.title 内容',
                )
              : first.when(
                  data: (_) {
                    if (_loaded.isEmpty) {
                      return EmptyView(
                        title: widget.emptyTitle,
                        message: widget.emptyMessage,
                      );
                    }
                    if (!widget.infinite) {
                      return ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _loaded.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (BuildContext context, int i) =>
                            _TrackTile(
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
                            n.metrics.pixels >=
                                n.metrics.maxScrollExtent - 240) {
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
                              return TextButton(
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
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
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
                  },
                  loading: () => const LoadingView(),
                  error: (Object e, StackTrace st) => neteaseIsAuthFailure(e)
                      ? NeteaseAuthExpiredHint(onRefreshed: (_) => _resetAndRefresh())
                      : ErrorView(
                          message: neteaseErrorText(e),
                          onRetry: () => ref.invalidate(widget.firstProvider),
                        ),
                ),
        ),
      ),
    );
  }

  Future<void> _playTrack(Track t) async {
    final String msg = await ref.read(playbackActionsProvider).playTrack(t);
    if (msg.isNotEmpty && context.mounted) {
      appNotify(context, msg);
    }
  }
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
                  ? Icon(Icons.music_note_rounded, size: 22, color: c.iconInactive)
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
                              horizontal: 5, vertical: 1),
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
                  if (showReason && reason != null && reason.isNotEmpty) ...<Widget>[
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
