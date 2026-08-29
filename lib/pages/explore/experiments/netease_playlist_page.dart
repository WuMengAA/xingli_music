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
class NeteasePlaylistPage extends ConsumerWidget {
  const NeteasePlaylistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool loggedIn = ref.watch(neteaseAuthProvider).isLoggedIn;
    final AsyncValue<List<NeteasePlaylist>> playlists =
        ref.watch(neteasePlaylistsProvider);

    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '网易云歌单',
          actions: <Widget>[
            if (loggedIn)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.invalidate(neteasePlaylistsProvider),
                tooltip: '刷新',
              ),
          ],
          body: !loggedIn
              ? _LoginHint(
                  onLoggedIn: () {
                    ref.invalidate(neteasePlaylistsProvider);
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
                    if (list.isEmpty) {
                      return const EmptyView(
                        title: '暂无歌单',
                        message: '去网易云 App 收藏或创建歌单后再来',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpace.sm),
                      itemBuilder: (BuildContext context, int i) {
                        final NeteasePlaylist p = list[i];
                        return _PlaylistTile(
                          playlist: p,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => NeteaseTrackListPage(
                                title: p.name,
                                firstProvider: neteasePlaylistTracksProvider(
                                    p.id),
                                emptyTitle: '歌单为空',
                                emptyMessage: '这个歌单还没有收录曲目',
                                loginHintTitle: '查看歌单需要登录网易云',
                                loginHintMessage: '登录后即可播放歌单内曲目',
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
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
            FilledButton.tonal(
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
