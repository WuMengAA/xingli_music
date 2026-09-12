/// ════════════════════════════════════════════════════════════════════════
/// VoiceHub 原生页（校园广播站点歌）· 底部「校园电台」Tab
///
/// 三个 Tab：排期 / 点歌榜 / 我的投稿。数据全部走 [voiceHubProvider] →
/// [VoiceHubClient]，不再套 WebView。
///
/// 认证分级（与客户端一致）：排期与点歌榜只要 API Key；「我的投稿」和投票
/// 需要 VoiceHub 登录会话（Cookie）。未登录时对应区域给登录入口，而不是整页
/// 报错——避免「没登录就什么都看不到」。
///
/// 完整网页版仍然有用（管理后台、联合投稿邀请等），保留在
/// `pages/explore/experiments/voicehub_page.dart`，由本页右上角入口跳转。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/voicehub/voicehub_provider.dart';
import '../../services/voicehub/voicehub_models.dart';
import '../../services/voicehub/voicehub_play.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/notification/app_notify.dart';
import '../explore/experiments/voicehub_page.dart';

/// VoiceHub 原生页。
class VoiceHubHubPage extends ConsumerStatefulWidget {
  const VoiceHubHubPage({super.key});

  @override
  ConsumerState<VoiceHubHubPage> createState() => _VoiceHubHubPageState();
}

class _VoiceHubHubPageState extends ConsumerState<VoiceHubHubPage> {
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// 首帧后拉一次全量数据。
  ///
  /// provider 构造时已用 microtask 触发 `load()`（读 SharedPreferences），
  /// 这里再调一次是幂等的（只是重读配置），目的是确保配置就绪后再发请求。
  Future<void> _bootstrap() async {
    if (_booted) return;
    _booted = true;
    final VoiceHubNotifier n = ref.read(voiceHubProvider.notifier);
    await n.load();
    if (!mounted) return;
    await n.refresh();
    if (!mounted) return;
    // 已登录时顺带拉「我的投稿」；未登录时 provider 内部会静默跳过。
    await n.fetchMySongs();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final VoiceHubState s = ref.watch(voiceHubProvider);

    return PageScaffold(
      title: '校园电台',
      actions: <Widget>[
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => _reload(),
        ),
        IconButton(
          tooltip: '投稿',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => _showSubmitSheet(),
        ),
        IconButton(
          tooltip: '完整网页版',
          icon: const Icon(Icons.language_rounded),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const VoiceHubPage(),
            ),
          ),
        ),
      ],
      body: DefaultTabController(
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TabBar(
              labelColor: c.accent,
              unselectedLabelColor: c.textSecondary,
              indicatorColor: c.accent,
              tabs: const <Widget>[
                Tab(text: '排期'),
                Tab(text: '点歌榜'),
                Tab(text: '我的投稿'),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            if (s.error.isNotEmpty) _ErrorBanner(message: s.error),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _buildScheduleTab(s),
                  _buildRankTab(s),
                  _buildMineTab(s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 排期 ────────────────────────────────────────────────────────────────

  Widget _buildScheduleTab(VoiceHubState s) {
    if (s.loading && s.schedules.isEmpty) {
      return const LoadingView(label: '加载排期中…');
    }
    if (s.schedules.isEmpty) {
      return EmptyView(
        title: '暂无排期',
        message: '广播站还没有发布排期，稍后再来看看。',
        actionLabel: '刷新',
        onAction: _reload,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.md, 0, AppSpace.md, AppSpace.lg),
      itemCount: s.schedules.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (BuildContext context, int i) =>
          _ScheduleTile(schedule: s.schedules[i], onPlay: _playSchedule),
    );
  }

  // ── 点歌榜 ──────────────────────────────────────────────────────────────

  Widget _buildRankTab(VoiceHubState s) {
    if (s.loading && s.songs.isEmpty) {
      return const LoadingView(label: '加载点歌榜中…');
    }
    if (s.songs.isEmpty && !s.loading) {
      return EmptyView(
        title: '还没有人点歌',
        message: '成为第一个投稿的人吧。',
        actionLabel: '投稿',
        onAction: () => _showSubmitSheet(),
      );
    }
    final int extra = s.hasMore ? 1 : 0;
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(voiceHubProvider.notifier).fetchSongs(refresh: true),
      // 滑到底自动加载下一页（分页状态在 provider 里，这里只发信号）。
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification n) {
          if (n.metrics.extentAfter < 200 && s.hasMore && !s.loadingMore) {
            ref.read(voiceHubProvider.notifier).fetchSongs();
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.md, 0, AppSpace.md, AppSpace.lg),
          itemCount: s.songs.length + extra,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
          itemBuilder: (BuildContext context, int i) {
            if (i >= s.songs.length) return _LoadMoreTile(loading: s.loadingMore);
            return _SongTile(
              song: s.songs[i],
              onPlay: _playSong,
              onVote: _vote,
            );
          },
        ),
      ),
    );
  }

  // ── 我的投稿 ────────────────────────────────────────────────────────────

  Widget _buildMineTab(VoiceHubState s) {
    if (!s.config.loggedIn) {
      // 区分「没填 cookie」与「填了但缺 auth-token」：后者要明说，别静默。
      return EmptyView(
        title: s.config.hasInvalidCookie ? '登录凭据无效' : '未登录 VoiceHub',
        message: s.config.loginPrompt,
        actionLabel: '登录',
        onAction: () => _showLoginSheet(),
      );
    }
    if (s.myLoading && s.mySongs.isEmpty) {
      return const LoadingView(label: '加载我的投稿中…');
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(voiceHubProvider.notifier).fetchMySongs(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, 0, AppSpace.md, AppSpace.lg),
        children: <Widget>[
          if (s.submissionStatus != null &&
              s.submissionStatus!.summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _StatusCard(status: s.submissionStatus!),
            ),
          if (s.mySongs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xl),
              child: EmptyView(
                title: '还没有投稿',
                message: '在「点歌榜」右上角 + 提交一首歌吧。',
                actionLabel: '投稿',
                onAction: () => _showSubmitSheet(),
              ),
            )
          else
            for (final VoiceHubSong song in s.mySongs) ...<Widget>[
              _SongTile(
                song: song,
                onPlay: _playSong,
                onVote: _vote,
                trailing: IconButton(
                  tooltip: '撤回投稿',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _withdraw(song),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
        ],
      ),
    );
  }

  // ── 行为 ────────────────────────────────────────────────────────────────

  Future<void> _reload() async {
    final VoiceHubNotifier n = ref.read(voiceHubProvider.notifier);
    await n.refresh();
    await n.fetchMySongs();
  }

  Future<void> _playSong(VoiceHubSong song) async {
    final String msg = await VoiceHubPlay.playSong(
      ref,
      platform: song.musicPlatform,
      musicId: song.musicId,
      title: song.title,
      artist: song.artist,
      coverUrl: song.cover,
      playUrl: song.playUrl,
      durationSeconds: song.durationSeconds,
    );
    if (!mounted || msg.isEmpty) return;
    appNotify(context, msg);
  }

  Future<void> _playSchedule(VoiceHubSchedule schedule) async {
    final String msg = await VoiceHubPlay.playSchedule(ref, schedule);
    if (!mounted || msg.isEmpty) return;
    appNotify(context, msg);
  }

  Future<void> _vote(VoiceHubSong song) async {
    final VoiceHubConfig cfg = ref.read(voiceHubProvider).config;
    if (!cfg.loggedIn) {
      // cookie 填了但缺 auth-token 时先说清楚原因，再给登录入口。
      if (cfg.hasInvalidCookie) appNotify(context, cfg.loginPrompt);
      await _showLoginSheet();
      return;
    }
    final bool ok =
        await ref.read(voiceHubProvider.notifier).vote(song, unvote: song.voted);
    if (!mounted || ok) return;
    appNotify(context, ref.read(voiceHubProvider).error);
  }

  Future<void> _withdraw(VoiceHubSong song) async {
    final bool ok =
        await ref.read(voiceHubProvider.notifier).withdraw(song.id);
    if (!mounted) return;
    appNotify(context, ok ? '已撤回投稿' : ref.read(voiceHubProvider).error);
  }

  /// 投稿弹层：只收后端 `ALLOWED_FIELDS` 里的字段，不做多余输入。
  Future<void> _showSubmitSheet() async {
    final _SubmitDraft? draft = await showModalBottomSheet<_SubmitDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => const _SubmitSheet(),
    );
    if (draft == null || !mounted) return;
    // B 站分 P：服务端会把 musicId 按 ':' 截断重建，cid/page 必须走独立字段。
    final VoiceHubBilibiliId bili = VoiceHubBilibiliId.parse(draft.musicId);
    final int id = await ref.read(voiceHubProvider.notifier).submit(
          title: draft.title,
          artist: draft.artist,
          musicPlatform: draft.platform,
          musicId: bili.isEmpty ? draft.musicId : bili.bvid,
          bilibiliCid: bili.cid.isEmpty ? null : bili.cid,
          bilibiliPage: bili.page.isEmpty ? null : bili.page,
          playUrl: draft.playUrl,
          submissionNote: draft.note,
          submissionNotePublic: draft.notePublic,
        );
    if (!mounted) return;
    appNotify(
      context,
      id > 0 ? '投稿成功（#$id）' : ref.read(voiceHubProvider).error,
    );
  }

  /// 登录弹层：用户名 + 密码 → 存 `auth-token` Cookie。
  Future<void> _showLoginSheet() async {
    final _LoginDraft? draft = await showModalBottomSheet<_LoginDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => const _LoginSheet(),
    );
    if (draft == null || !mounted) return;
    final bool ok = await ref
        .read(voiceHubProvider.notifier)
        .login(draft.username, draft.password);
    if (!mounted) return;
    if (!ok) {
      appNotify(context, ref.read(voiceHubProvider).error);
      return;
    }
    await ref.read(voiceHubProvider.notifier).fetchMySongs();
  }
}

/// 顶部错误横幅（列表照常展示，错误只是附加提示）。
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: c.dangerSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 16, color: c.danger),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMuted.copyWith(color: c.danger),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 投稿额度卡。
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final VoiceHubSubmissionStatus status;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Text(
        status.summary,
        style: AppTextStyles.bodyMuted.copyWith(color: c.textSecondary),
      ),
    );
  }
}

/// 封面缩略图（加载失败回退音符图标）。
class _Cover extends StatelessWidget {
  const _Cover({this.url});

  static const double _size = 48;

  final String? url;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final String? u = url;
    if (u == null || u.isEmpty) {
      return _fallback(c);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        u,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        cacheWidth: 96,
        errorBuilder: (_, __, ___) => _fallback(c),
      ),
    );
  }

  Widget _fallback(AppThemeColors c) => Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: c.bgPlaceholder,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.music_note_rounded,
            size: 24, color: c.textTertiary),
      );
}

/// 点歌卡片。
class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.onPlay,
    required this.onVote,
    this.trailing,
  });

  final VoiceHubSong song;
  final ValueChanged<VoiceHubSong> onPlay;
  final ValueChanged<VoiceHubSong> onVote;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardTextInset),
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: <Widget>[
          _Cover(url: song.cover),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  song.title,
                  style: AppTextStyles.subtitle.copyWith(color: c.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  song.artist,
                  style:
                      AppTextStyles.bodyMuted.copyWith(color: c.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (song.requestedAt.isNotEmpty || song.requester.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Text(
                      <String>[
                        if (song.requester.isNotEmpty) song.requester,
                        if (song.requestedAt.isNotEmpty) song.requestedAt,
                      ].join(' · '),
                      style: AppTextStyles.bodyMuted
                          .copyWith(color: c.textTertiary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          // 投票：已排期/已播放的歌后端直接拒绝，置灰并给出 tooltip。
          IconButton(
            tooltip: song.votable
                ? (song.voted ? '取消投票' : '投票')
                : (song.played ? '已播放，不能投票' : '已排期，不能投票'),
            icon: Icon(
              song.voted
                  ? Icons.thumb_up_rounded
                  : Icons.thumb_up_outlined,
              size: 18,
              color: song.votable ? c.accent : c.textTertiary,
            ),
            onPressed: song.votable ? () => onVote(song) : null,
          ),
          Text(
            '${song.voteCount}',
            style: AppTextStyles.bodyMuted.copyWith(color: c.textSecondary),
          ),
          IconButton(
            tooltip: '播放',
            icon: Icon(Icons.play_arrow_rounded, color: c.textPrimary),
            onPressed: () => onPlay(song),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 排期卡片。
class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({required this.schedule, required this.onPlay});

  final VoiceHubSchedule schedule;
  final ValueChanged<VoiceHubSchedule> onPlay;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardTextInset),
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: <Widget>[
          _Cover(url: schedule.songCover),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  schedule.songTitle,
                  style: AppTextStyles.subtitle.copyWith(color: c.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  schedule.songArtist,
                  style:
                      AppTextStyles.bodyMuted.copyWith(color: c.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  <String>[
                    schedule.dateLabel,
                    if (schedule.timeLabel.isNotEmpty) schedule.timeLabel,
                    if (schedule.requester.isNotEmpty) schedule.requester,
                  ].join(' · '),
                  style: AppTextStyles.bodyMuted
                      .copyWith(color: c.textTertiary, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '播放',
            icon: Icon(Icons.play_arrow_rounded, color: c.textPrimary),
            onPressed: () => onPlay(schedule),
          ),
        ],
      ),
    );
  }
}

/// 「加载更多」行（滑到底自动触发下一页）。
class _LoadMoreTile extends StatelessWidget {
  const _LoadMoreTile({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      child: Center(
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: context.appColors.accent),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// 投稿表单草稿。
class _SubmitDraft {
  const _SubmitDraft({
    required this.title,
    required this.artist,
    this.platform = '',
    this.musicId = '',
    this.playUrl = '',
    this.note = '',
    this.notePublic = false,
  });

  final String title;
  final String artist;
  final String platform;
  final String musicId;
  final String playUrl;
  final String note;
  final bool notePublic;
}

/// 投稿弹层。
class _SubmitSheet extends StatefulWidget {
  const _SubmitSheet();

  @override
  State<_SubmitSheet> createState() => _SubmitSheetState();
}

class _SubmitSheetState extends State<_SubmitSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _artist = TextEditingController();
  final TextEditingController _musicId = TextEditingController();
  final TextEditingController _playUrl = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _platform = 'netease';
  bool _notePublic = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _musicId.dispose();
    _playUrl.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '投稿点歌',
            style: AppTextStyles.subtitle.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '歌曲名',
              isDense: true,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _artist,
            decoration: const InputDecoration(
              labelText: '艺术家',
              isDense: true,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          DropdownButtonFormField<String>(
            initialValue: _platform,
            decoration: const InputDecoration(
              labelText: '平台',
              isDense: true,
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(value: 'netease', child: Text('网易云')),
              DropdownMenuItem<String>(value: 'bilibili', child: Text('哔哩哔哩')),
              DropdownMenuItem<String>(value: '', child: Text('仅直链')),
            ],
            onChanged: (String? v) => setState(() => _platform = v ?? ''),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _musicId,
            decoration: const InputDecoration(
              labelText: '平台内 ID（网易云歌曲 id / B 站 BV 号）',
              isDense: true,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _playUrl,
            decoration: const InputDecoration(
              labelText: '直链播放地址（可选）',
              isDense: true,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _note,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: '留言（可选）',
              isDense: true,
            ),
          ),
          CheckboxListTile(
            value: _notePublic,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              '公开留言',
              style: AppTextStyles.bodyMuted.copyWith(color: c.textSecondary),
            ),
            onChanged: (bool? v) =>
                setState(() => _notePublic = v ?? false),
          ),
          const SizedBox(height: AppSpace.sm),
          FilledButton(
            onPressed: _submit,
            child: const Text('提交'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final String title = _title.text.trim();
    final String artist = _artist.text.trim();
    if (title.isEmpty || artist.isEmpty) {
      appNotify(context, '歌曲名与艺术家不能为空');
      return;
    }
    Navigator.of(context).pop(
      _SubmitDraft(
        title: title,
        artist: artist,
        platform: _platform,
        musicId: _musicId.text.trim(),
        playUrl: _playUrl.text.trim(),
        note: _note.text.trim(),
        notePublic: _notePublic,
      ),
    );
  }
}

/// 登录表单草稿。
class _LoginDraft {
  const _LoginDraft({required this.username, required this.password});

  final String username;
  final String password;
}

/// 登录弹层。
class _LoginSheet extends StatefulWidget {
  const _LoginSheet();

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pwd = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _user.dispose();
    _pwd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '登录 VoiceHub',
            style: AppTextStyles.subtitle
                .copyWith(color: context.appColors.textPrimary),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              labelText: '用户名',
              isDense: true,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _pwd,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '密码',
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton(
            onPressed: () {
              final String u = _user.text.trim();
              final String p = _pwd.text;
              if (u.isEmpty || p.isEmpty) {
                appNotify(context, '用户名与密码不能为空');
                return;
              }
              Navigator.of(context).pop(_LoginDraft(username: u, password: p));
            },
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }
}
