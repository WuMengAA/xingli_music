import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../providers/sources/netease_provider.dart';
import '../../../services/audio/sources/netease/netease_api.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_views.dart';
import '../../../widgets/sources/netease_login_sheet.dart';
import '../../../widgets/sources/netease_track_list_page.dart';

/// 网易云 · 我的歌单（用户歌单列表 → 歌单内曲目）。
///
/// 顶层展示当前登录用户的歌单摘要（封面 + 名称 + 曲目数），点击进入该
/// 歌单的曲目列表——复用 [NeteaseTrackListPage]（统一 tile / 三态 / 登录
/// 引导）。未登录时展示登录引导（弹层登录，成功后自动刷新）。
///
/// 顶层歌单列表支持分页：触底以 `limit/offset` 追加下一批并按 id 去重，
/// 另支持下拉刷新（[RefreshIndicator]）与右上角刷新按钮。
class NeteasePlaylistPage extends ConsumerStatefulWidget {
  const NeteasePlaylistPage({super.key});

  @override
  ConsumerState<NeteasePlaylistPage> createState() =>
      _NeteasePlaylistPageState();
}

/// 每批歌单条数（首屏与触底追加保持一致，便于用批次长度判断是否到底）。
const int _kPlaylistPageSize = 50;

class _NeteasePlaylistPageState extends ConsumerState<NeteasePlaylistPage> {
  final List<NeteasePlaylist> _items = <NeteasePlaylist>[];
  final Set<int> _seenIds = <int>{};
  int _offset = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _failed = false;

  /// 按 [NeteasePlaylist.id] 去重后追加，返回本批实际新增条数。
  int _appendDeduped(List<NeteasePlaylist> batch) {
    final int before = _items.length;
    for (final NeteasePlaylist p in batch) {
      if (_seenIds.add(p.id)) _items.add(p);
    }
    return _items.length - before;
  }

  /// 清空分页状态（下拉刷新 / 按钮刷新共用）。
  void _resetState() {
    _items.clear();
    _seenIds.clear();
    _offset = 0;
    _hasMore = true;
    _loadingMore = false;
    _failed = false;
  }

  void _refresh() {
    setState(_resetState);
    ref.invalidate(neteasePlaylistsProvider);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _failed = false;
    });
    try {
      final List<NeteasePlaylist> batch = await ref
          .read(neteaseSourceProvider)
          .playlists(limit: _kPlaylistPageSize, offset: _offset);
      if (!mounted) return;
      setState(() {
        // offset 用原始批次长度推进；去重后新增 0 条 → 认定已到底。
        _offset += batch.length;
        if (_appendDeduped(batch) == 0) _hasMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool loggedIn = ref.watch(neteaseAuthProvider).isLoggedIn;
    final AsyncValue<List<NeteasePlaylist>> playlists =
        ref.watch(neteasePlaylistsProvider);

    // 首屏 / 刷新后把 provider 数据填充到 _items（仅在为空时）；provider 数据
    // 整体变化（换账号）时替换。用 ref.listen 在 build 之外响应，避免
    // 「build 期间改状态」反模式。
    ref.listen<AsyncValue<List<NeteasePlaylist>>>(neteasePlaylistsProvider, (
      _,
      AsyncValue<List<NeteasePlaylist>> next,
    ) {
      next.whenData((List<NeteasePlaylist> list) {
        if (!mounted) return;
        if (_items.isEmpty) {
          setState(() {
            _seenIds.clear();
            _appendDeduped(list);
            _offset = list.length;
            _hasMore = list.length >= _kPlaylistPageSize;
          });
        } else if (!_firstBatchEquals(_items, list)) {
          setState(() {
            _items.clear();
            _seenIds.clear();
            _appendDeduped(list);
            _offset = list.length;
            _hasMore = true;
          });
        }
      });
    });

    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '网易云歌单',
          actions: <Widget>[
            if (loggedIn)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _refresh,
                tooltip: '刷新',
              ),
          ],
          body: !loggedIn
              ? _LoginHint(
                  onLoggedIn: () {
                    _refresh();
                    ref.invalidate(neteaseAuthProvider);
                  },
                )
              : playlists.when(
                  loading: () => const LoadingView(),
                  error: (Object e, StackTrace st) => ErrorView(
                    message: neteaseErrorText(e),
                    onRetry: () => ref.invalidate(neteasePlaylistsProvider),
                  ),
                  data: (List<NeteasePlaylist> list) {
                    // provider 数据已就绪但 ref.listen 尚未填充时（例如页面复用时
                    // 数据已缓存），直接用 provider 批次渲染，避免一帧空态闪烁。
                    final List<NeteasePlaylist> view =
                        _items.isNotEmpty ? _items : list;
                    if (view.isEmpty) {
                      return const EmptyView(
                        title: '暂无歌单',
                        message: '去网易云 App 收藏或创建歌单后再来',
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        _refresh();
                        try {
                          // 等首屏批次真正回来再收起下拉指示器。
                          await ref.read(neteasePlaylistsProvider.future);
                        } catch (_) {
                          // 失败态由 provider 的 error 分支呈现。
                        }
                      },
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (ScrollNotification n) {
                          if (n is ScrollUpdateNotification &&
                              n.metrics.pixels >=
                                  n.metrics.maxScrollExtent - 240) {
                            _loadMore();
                          }
                          return false;
                        },
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: view.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpace.sm),
                          itemBuilder: (BuildContext context, int i) {
                            if (i == view.length) {
                              if (_failed) {
                                return Center(
                                  child: FilledButton(
                                    onPressed: _loadMore,
                                    child: const Text('加载失败，点击重试'),
                                  ),
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
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              if (!_hasMore) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
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
                            final NeteasePlaylist p = view[i];
                            return _PlaylistTile(
                              playlist: p,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => NeteaseTrackListPage(
                                    title: p.name,
                                    firstProvider:
                                        neteasePlaylistTracksProvider(p.id),
                                    infinite: true,
                                    loadMore: (int offset) => ref
                                        .read(neteaseSourceProvider)
                                        .playlistTracks(
                                          p.id,
                                          limit: 100,
                                          offset: offset,
                                        ),
                                    emptyTitle: '歌单为空',
                                    emptyMessage: '这个歌单还没有收录曲目',
                                    loginHintTitle: '查看歌单需要登录网易云',
                                    loginHintMessage: '登录后即可播放歌单内曲目',
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// 比较已加载列表的首批是否与 [first] 一致（按 id，仅比前缀）。
///
/// 首个歌单批次未变时保留触底追加项，批次整体变化（换账号）时才替换。
bool _firstBatchEquals(List<NeteasePlaylist> loaded, List<NeteasePlaylist> first) {
  if (loaded.length < first.length) return false;
  for (int i = 0; i < first.length; i++) {
    if (loaded[i].id != first[i].id) return false;
  }
  return true;
}

/// 歌单行：封面（圆角方块）+ 名称 + 曲目数 + 箭头。
class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist, required this.onTap});

  final NeteasePlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: playlist.coverUrl == null
                      ? Container(
                          width: 48,
                          height: 48,
                          color: c.bgPlaceholder,
                          child: Icon(Icons.queue_music_rounded,
                              size: 24, color: c.iconInactive),
                        )
                      : Image.network(
                          playlist.coverUrl!,
                          width: 48,
                          height: 48,
                          cacheWidth: 256,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 48,
                            height: 48,
                            color: c.bgPlaceholder,
                            child: Icon(Icons.queue_music_rounded,
                                size: 24, color: c.iconInactive),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(playlist.name, style: context.appText.trackName),
                      const SizedBox(height: 2),
                      Text(
                        '${playlist.trackCount} 首'
                        '${playlist.creator != null && playlist.creator!.isNotEmpty ? ' · ${playlist.creator}' : ''}',
                        style: context.appText.artist,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: AppSize.iconSm, color: c.iconInactive),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 未登录引导（锁图标 + 说明 + 去登录按钮，弹层登录成功后回调刷新）。
class _LoginHint extends ConsumerWidget {
  const _LoginHint({required this.onLoggedIn});

  final VoidCallback onLoggedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.lock_outline_rounded, size: 40, color: c.iconInactive),
            const SizedBox(height: 16),
            Text('登录后查看你的网易云歌单', style: context.appText.subtitle),
            const SizedBox(height: 6),
            Text(
              '登录后即可查看并播放你收藏与创建的歌单',
              style: context.appText.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () async {
                await showNeteaseLoginSheet(context);
                if (!context.mounted) return;
                onLoggedIn();
              },
              child: const Text('去登录'),
            ),
          ],
        ),
      ),
    );
  }
}
