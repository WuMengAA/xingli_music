/// ════════════════════════════════════════════════════════════════════════
/// VoiceHub 数据源 Provider（可选接入；自研 relay/P2P 电台层保留不动）
///
/// - 配置：服务器地址 + API Key + 登录 Cookie（SharedPreferences 持久化）
/// - fetchSongs(refresh:) / fetchSchedules / fetchMySongs：拉取并带分页状态
/// - submit / vote / withdraw / login：写操作，失败只记 error 不抛
///
/// 认证是**分级的**，不要一上来就要求 Cookie：
/// 点歌榜与排期走 `/api/open/*`，只要 API Key；只有投票、我的投稿、投稿额度
/// 这三个走 `/api/songs/*` 的端点才需要登录会话。因此 [VoiceHubState.loading]
/// 读列表不依赖 Cookie，UI 只在用户点投票时才提示登录。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/voicehub/voicehub_client.dart';
import '../../services/voicehub/voicehub_models.dart';

/// VoiceHub 配置。
class VoiceHubConfig {
  const VoiceHubConfig({
    this.baseUrl = 'https://voicehub.245959623.xyz',
    this.apiKey = '',
    this.cookie = '',
  });

  final String baseUrl;
  final String apiKey;

  /// VoiceHub 登录 cookie（`auth-token=<jwt>`）；投票 / 我的投稿 / 额度需要。
  /// 可由 [VoiceHubNotifier.login] 写入，也可手动粘贴。
  final String cookie;

  bool get enabled => baseUrl.trim().isNotEmpty;

  /// 是否已持有登录会话——**严格判定**：Cookie 里必须含 `auth-token`。
  ///
  /// 判定唯一来源是 [VoiceHubClient.hasSessionCookie]（不再用「cookie 非空
  /// 即已登录」的宽松写法）。宽松写法会让粘了非 auth-token cookie 的用户
  /// 显示已登录，但投票 / 我的投稿必然 401，属于「看起来能用、点了才失败」。
  bool get loggedIn => VoiceHubClient.hasSessionCookie(cookie);

  /// 填了 cookie 但里面没有 `auth-token`。
  ///
  /// 这是「用户以为登录了、其实没有」的典型状态，UI 必须明确提示而不是
  /// 静默当成未登录。
  bool get hasInvalidCookie =>
      cookie.trim().isNotEmpty && !loggedIn;

  /// 未登录时的提示文案（区分「没填」与「填了但不对」）。
  String get loginPrompt => hasInvalidCookie
      ? '未检测到登录凭据（Cookie 中缺少 auth-token），投票与我的投稿不可用'
      : '登录后才能查看自己的投稿、投票与投稿额度';

  VoiceHubConfig copyWith({String? baseUrl, String? apiKey, String? cookie}) =>
      VoiceHubConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        cookie: cookie ?? this.cookie,
      );
}

/// VoiceHub 数据状态。
class VoiceHubState {
  const VoiceHubState({
    this.config = const VoiceHubConfig(),
    this.songs = const <VoiceHubSong>[],
    this.schedules = const <VoiceHubSchedule>[],
    this.mySongs = const <VoiceHubSong>[],
    this.loading = false,
    this.loadingMore = false,
    this.myLoading = false,
    this.submitting = false,
    this.error = '',
    this.lastSync,
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.hasMore = false,
    this.submissionStatus,
  });

  final VoiceHubConfig config;
  final List<VoiceHubSong> songs;
  final List<VoiceHubSchedule> schedules;
  final List<VoiceHubSong> mySongs;
  final bool loading;
  final bool loadingMore;
  final bool myLoading;
  final bool submitting;
  final String error;
  final DateTime? lastSync;

  /// 点歌榜分页状态。
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;

  /// 投稿额度（未登录 / 拉取失败时为 null，UI 自行决定要不要展示）。
  final VoiceHubSubmissionStatus? submissionStatus;

  VoiceHubState copyWith({
    VoiceHubConfig? config,
    List<VoiceHubSong>? songs,
    List<VoiceHubSchedule>? schedules,
    List<VoiceHubSong>? mySongs,
    bool? loading,
    bool? loadingMore,
    bool? myLoading,
    bool? submitting,
    String? error,
    DateTime? lastSync,
    int? page,
    int? pageSize,
    int? total,
    bool? hasMore,
    VoiceHubSubmissionStatus? submissionStatus,
    bool clearSubmissionStatus = false,
  }) =>
      VoiceHubState(
        config: config ?? this.config,
        songs: songs ?? this.songs,
        schedules: schedules ?? this.schedules,
        mySongs: mySongs ?? this.mySongs,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        myLoading: myLoading ?? this.myLoading,
        submitting: submitting ?? this.submitting,
        error: error ?? this.error,
        lastSync: lastSync ?? this.lastSync,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
        total: total ?? this.total,
        hasMore: hasMore ?? this.hasMore,
        submissionStatus: clearSubmissionStatus
            ? null
            : (submissionStatus ?? this.submissionStatus),
      );
}

class VoiceHubNotifier extends StateNotifier<VoiceHubState> {
  VoiceHubNotifier() : super(const VoiceHubState());

  static const String _kBaseUrl = 'voicehub.baseUrl';
  static const String _kApiKey = 'voicehub.apiKey';
  static const String _kCookie = 'voicehub.cookie';

  /// 每页条数（后端 open 接口上限 100）。
  static const int defaultPageSize = 20;

  /// 首 watch 自动加载配置（与天气/日历/ClassIsland 一致的约定）。
  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    // 未配置（首次启动 / 之前清空）时默认指向真实站点，打开即用。
    final String savedBase = prefs.getString(_kBaseUrl) ?? '';
    final String baseUrl =
        savedBase.trim().isEmpty ? 'https://voicehub.245959623.xyz' : savedBase;
    state = state.copyWith(
      config: VoiceHubConfig(
        baseUrl: baseUrl,
        apiKey: prefs.getString(_kApiKey) ?? '',
        cookie: prefs.getString(_kCookie) ?? '',
      ),
    );
  }

  /// 保存配置并立即拉取一版数据。
  Future<void> configure(VoiceHubConfig cfg) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, cfg.baseUrl.trim());
    await prefs.setString(_kApiKey, cfg.apiKey.trim());
    await prefs.setString(_kCookie, cfg.cookie.trim());
    state = state.copyWith(
      config: cfg.copyWith(
        baseUrl: cfg.baseUrl.trim(),
        apiKey: cfg.apiKey.trim(),
        cookie: cfg.cookie.trim(),
      ),
    );
    if (cfg.enabled) await refresh();
  }

  VoiceHubClient? get _client {
    final VoiceHubConfig c = state.config;
    if (!c.enabled) return null;
    return VoiceHubClient(
      baseUrl: c.baseUrl,
      apiKey: c.apiKey,
      cookie: c.cookie,
    );
  }

  /// 拉取点歌 + 排期（任一端点失败仅记 error，不抛）。
  Future<void> refresh() async {
    await Future.wait(<Future<void>>[
      fetchSongs(refresh: true),
      fetchSchedules(),
    ]);
    // 已登录时顺带刷新投稿额度（失败不影响列表展示）。
    if (state.config.loggedIn) await fetchSubmissionStatus();
  }

  /// 分页拉取点歌榜。
  ///
  /// [refresh] 为 true 时回到第一页并覆盖列表；否则追加下一页。
  /// 无更多数据时直接返回，不重复发请求。
  Future<void> fetchSongs({bool refresh = false, String search = ''}) async {
    final VoiceHubClient? client = _client;
    if (client == null) return;
    if (!refresh && !state.hasMore) return;
    if (state.loadingMore || (refresh && state.loading)) return;

    final int nextPage = refresh ? 1 : state.page + 1;
    state = state.copyWith(
      loading: refresh,
      loadingMore: !refresh,
      error: '',
    );
    try {
      final VoiceHubSongPage result = await client.fetchSongs(
        search: search,
        page: nextPage,
        limit: state.pageSize,
      );
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        songs: refresh
            ? result.songs
            : <VoiceHubSong>[...state.songs, ...result.songs],
        page: nextPage,
        total: result.pagination.total,
        hasMore: result.pagination.hasMore(nextPage, state.pageSize),
        lastSync: DateTime.now(),
      );
    } on VoiceHubException catch (e) {
      state = state.copyWith(loading: false, loadingMore: false, error: e.message);
    } catch (e) {
      state = state.copyWith(
          loading: false, loadingMore: false, error: '拉取点歌失败：$e');
    }
  }

  /// 拉取排期列表。
  Future<void> fetchSchedules({String semester = ''}) async {
    final VoiceHubClient? client = _client;
    if (client == null) return;
    try {
      final VoiceHubSchedulePage result =
          await client.fetchSchedules(semester: semester, limit: 50);
      state = state.copyWith(schedules: result.schedules);
    } on VoiceHubException catch (e) {
      state = state.copyWith(error: e.message);
    } catch (e) {
      state = state.copyWith(error: '拉取排期失败：$e');
    }
  }

  /// 拉取「我的投稿」（`/api/songs?scope=mine`，需 Cookie）。
  ///
  /// 未登录时清空列表并记一条友好提示，不发必然 401 的请求。
  Future<void> fetchMySongs() async {
    final VoiceHubClient? client = _client;
    if (client == null) return;
    if (!state.config.loggedIn) {
      // 未登录是常态而非错误：静默清空，不往 error 里塞提示（UI 自己判断）。
      state = state.copyWith(
        mySongs: const <VoiceHubSong>[],
        myLoading: false,
      );
      return;
    }
    state = state.copyWith(myLoading: true, error: '');
    try {
      final List<VoiceHubSong> mine = await client.fetchMySongs();
      state = state.copyWith(myLoading: false, mySongs: mine);
    } on VoiceHubException catch (e) {
      state = state.copyWith(myLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(myLoading: false, error: '拉取我的投稿失败：$e');
    }
  }

  /// 拉取投稿额度（需 Cookie）。
  Future<void> fetchSubmissionStatus() async {
    final VoiceHubClient? client = _client;
    if (client == null || !state.config.loggedIn) return;
    try {
      final VoiceHubSubmissionStatus s = await client.fetchSubmissionStatus();
      state = state.copyWith(submissionStatus: s);
    } catch (_) {
      // 额度只是锦上添花，失败不打扰用户。
    }
  }

  /// 搜索点歌（返回结果；失败返回空并记 error）。
  Future<List<VoiceHubSong>> search(String keyword) async {
    final VoiceHubClient? client = _client;
    if (client == null) return const <VoiceHubSong>[];
    try {
      final VoiceHubSongPage result =
          await client.fetchSongs(search: keyword, limit: 20);
      return result.songs;
    } on VoiceHubException catch (e) {
      state = state.copyWith(error: e.message);
      return const <VoiceHubSong>[];
    } catch (e) {
      state = state.copyWith(error: '搜索失败：$e');
      return const <VoiceHubSong>[];
    }
  }

  /// 用户名密码登录 → 存 `auth-token` Cookie。
  ///
  /// 登录成功后不自动刷新全量数据（此时会话刚建立，额度/我的投稿由调用方
  /// 按需触发），仅清除错误态。
  Future<bool> login(String username, String password) async {
    final VoiceHubClient? client = _client;
    if (client == null) {
      state = state.copyWith(error: '未配置 VoiceHub 服务器');
      return false;
    }
    try {
      final String cookie = await client.login(username, password);
      if (cookie.isEmpty) {
        state = state.copyWith(error: '登录失败：服务端未返回会话 Cookie');
        return false;
      }
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCookie, cookie);
      state = state.copyWith(
        config: state.config.copyWith(cookie: cookie),
        error: '',
      );
      return true;
    } on VoiceHubException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(error: '登录失败：$e');
      return false;
    }
  }

  /// 退出登录：清 Cookie 与依赖登录态的数据。
  Future<void> logout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCookie);
    state = state.copyWith(
      config: state.config.copyWith(cookie: ''),
      mySongs: const <VoiceHubSong>[],
      clearSubmissionStatus: true,
    );
  }

  /// 点歌提交（`/api/open/songs/request`，只需 API Key，不要求 Cookie）。
  ///
  /// 只转发后端白名单内的字段；B 站分 P 用 [bilibiliCid] / [bilibiliPage]
  /// 独立字段（不要拼进 [musicId]，服务端会截断）；[collaborators] 是数值
  /// 用户 id 列表。时长不下发（open 端点白名单不含 durationSeconds）。
  Future<int> submit({
    required String title,
    required String artist,
    String? cover,
    String? musicPlatform,
    String? musicId,
    String? bilibiliCid,
    String? bilibiliPage,
    String? playUrl,
    String? submissionNote,
    bool submissionNotePublic = false,
    int? preferredPlayTimeId,
    String? cardCode,
    List<int>? collaborators,
  }) async {
    final VoiceHubClient? client = _client;
    if (client == null) {
      state = state.copyWith(error: '未配置 VoiceHub 服务器');
      return 0;
    }
    state = state.copyWith(submitting: true, error: '');
    try {
      final int id = await client.submitSong(
        title: title,
        artist: artist,
        cover: cover,
        musicPlatform: musicPlatform,
        musicId: musicId,
        bilibiliCid: bilibiliCid,
        bilibiliPage: bilibiliPage,
        playUrl: playUrl,
        submissionNote: submissionNote,
        submissionNotePublic: submissionNotePublic,
        preferredPlayTimeId: preferredPlayTimeId,
        cardCode: cardCode,
        collaborators: collaborators,
      );
      state = state.copyWith(submitting: false);
      await fetchSongs(refresh: true);
      return id;
    } on VoiceHubException catch (e) {
      state = state.copyWith(submitting: false, error: e.message);
      return 0;
    } catch (e) {
      state = state.copyWith(submitting: false, error: '点歌失败：$e');
      return 0;
    }
  }

  /// 投票 / 取消投票（`/api/songs/vote`，需 Cookie）。
  ///
  /// 先乐观更新本地计数（+1/-1 并翻转 voted），再以服务端回算值校正；
  /// 失败回滚并记 error。
  Future<bool> vote(VoiceHubSong song, {bool unvote = false}) async {
    final VoiceHubClient? client = _client;
    if (client == null) {
      state = state.copyWith(error: '未配置 VoiceHub 服务器');
      return false;
    }
    if (!state.config.loggedIn) {
      state = state.copyWith(error: '投票需先登录 VoiceHub');
      return false;
    }
    final int before = song.voteCount;
    final bool votedBefore = song.voted;
    _patchSong(
      song.id,
      song.copyWithVote(
        voteCount: unvote ? before - 1 : before + 1,
        voted: !unvote,
      ),
    );
    try {
      final int? exact = await client.vote(song.id, unvote: unvote);
      _patchSong(
        song.id,
        song.copyWithVote(
          voteCount: exact ?? (unvote ? before - 1 : before + 1),
          voted: !unvote,
        ),
      );
      return true;
    } on VoiceHubException catch (e) {
      _patchSong(
        song.id,
        song.copyWithVote(voteCount: before, voted: votedBefore),
      );
      state = state.copyWith(error: e.message);
      return false;
    } catch (e) {
      _patchSong(
        song.id,
        song.copyWithVote(voteCount: before, voted: votedBefore),
      );
      state = state.copyWith(error: unvote ? '取消投票失败：$e' : '投票失败：$e');
      return false;
    }
  }

  /// 撤回投稿（`/api/songs/withdraw`，需 Cookie）。
  Future<bool> withdraw(int songId) async {
    final VoiceHubClient? client = _client;
    if (client == null) {
      state = state.copyWith(error: '未配置 VoiceHub 服务器');
      return false;
    }
    if (!state.config.loggedIn) {
      state = state.copyWith(error: '撤回投稿需先登录 VoiceHub');
      return false;
    }
    try {
      await client.withdraw(songId);
      await Future.wait(<Future<void>>[
        fetchMySongs(),
        fetchSongs(refresh: true),
      ]);
      return true;
    } on VoiceHubException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(error: '撤回失败：$e');
      return false;
    }
  }

  /// 就地替换列表里的某首歌（保持对象标识顺序不变）。
  void _patchSong(int id, VoiceHubSong updated) {
    state = state.copyWith(
      songs: <VoiceHubSong>[
        for (final VoiceHubSong s in state.songs)
          s.id == id ? updated : s,
      ],
      mySongs: <VoiceHubSong>[
        for (final VoiceHubSong s in state.mySongs)
          s.id == id ? updated : s,
      ],
    );
  }
}

/// VoiceHub provider（首 watch 自动 load 配置）。
final voiceHubProvider =
    StateNotifierProvider<VoiceHubNotifier, VoiceHubState>((ref) {
  final VoiceHubNotifier n = VoiceHubNotifier();
  Future<void>.microtask(n.load);
  return n;
});
