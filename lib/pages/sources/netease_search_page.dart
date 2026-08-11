/// 网易云搜索页（I 域 · P1-6 接线）。
///
/// - 未登录：引导去登录（弹 [showNeteaseLoginSheet]）；
/// - 已登录：`neteaseSearchProvider` 搜索网易云曲库，点击结果走
///   `playbackActionsProvider.playTrack` 播放（占位符由播放链路懒解析为 CDN 地址）；
/// - 播放地址解析失败（登录失效 / 无版权 / 会员 / 网络）经
///   `AudioService.playErrorStream` 弹 SnackBar 提示。
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
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/sources/netease_login_sheet.dart';

/// 网易云搜索页。
class NeteaseSearchPage extends ConsumerStatefulWidget {
  const NeteaseSearchPage({super.key});

  @override
  ConsumerState<NeteaseSearchPage> createState() => _NeteaseSearchPageState();
}

class _NeteaseSearchPageState extends ConsumerState<NeteaseSearchPage> {
  final TextEditingController _queryCtrl = TextEditingController();
  String _keyword = '';
  StreamSubscription<String>? _playErrorSub;

  @override
  void initState() {
    super.initState();
    // 播放地址解析失败（如登录失效）→ SnackBar 提示。
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _submit(String raw) {
    final String kw = raw.trim();
    setState(() => _keyword = kw);
  }

  Future<void> _openLogin() async {
    final bool? ok = await showNeteaseLoginSheet(context);
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已登录网易云，可以开始搜索')),
      );
    }
  }

  Future<void> _play(Track t) async {
    final String msg = await ref.read(playbackActionsProvider).playTrack(t);
    if (msg.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final NeteaseAuthState auth = ref.watch(neteaseAuthProvider);

    return PageScaffold(
      title: '网易云搜索',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSearchField(),
          const SizedBox(height: AppSpace.md),
          Expanded(child: _buildContent(auth)),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _queryCtrl,
      onSubmitted: _submit,
      textInputAction: TextInputAction.search,
      // R23j：关闭系统拼写检查/输入建议，避免桌面端文字下方出现
      // 黄色双横线（拼写建议标记）干扰显示。
      enableSuggestions: false,
      autocorrect: false,
      style: context.appText.body,
      decoration: InputDecoration(
        hintText: '搜索网易云曲库（歌手 / 歌名）',
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

  Widget _buildContent(NeteaseAuthState auth) {
    if (!auth.isLoggedIn) {
      return _HintPanel(
        icon: Icons.lock_outline_rounded,
        message: '登录后才能搜索网易云曲库',
        actionLabel: '去登录',
        onAction: _openLogin,
      );
    }
    if (_keyword.isEmpty) {
      return const _HintPanel(
        icon: Icons.search_rounded,
        message: '输入关键词，搜索网易云曲库并在线播放',
      );
    }
    final AsyncValue<List<Track>> result =
        ref.watch(neteaseSearchProvider(_keyword));
    return result.when(
      data: (List<Track> tracks) {
        if (tracks.isEmpty) {
          return const _HintPanel(
            icon: Icons.music_off_rounded,
            message: '没有找到相关歌曲',
          );
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: tracks.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpace.xs),
          itemBuilder: (BuildContext _, int i) {
            final Track t = tracks[i];
            return _TrackTile(track: t, onTap: () => _play(t));
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace st) => _HintPanel(
        icon: Icons.error_outline_rounded,
        message: '搜索失败：$e',
        actionLabel: '重试',
        onAction: () => ref.invalidate(neteaseSearchProvider(_keyword)),
      ),
    );
  }
}

/// 居中提示面板（可带一个操作按钮）。
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

/// 单条搜索结果。
class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? album = track.album;
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
                    Text(
                      album == null
                          ? track.artist
                          : '${track.artist} · $album',
                      style: context.appText.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
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
