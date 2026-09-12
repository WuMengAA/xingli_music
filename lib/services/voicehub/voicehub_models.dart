/// ════════════════════════════════════════════════════════════════════════
/// VoiceHub 数据模型（校园广播站点歌系统 · Nuxt 4 全栈）
///
/// 契约来源（本机参考实现 `D:\Stelarith\Stelarith-Music\_voicehub_ref`）：
///   - `server/api/open/songs.get.ts`      → `{success, data:{songs, pagination}}`
///   - `server/api/open/schedules.get.ts`  → `{success, data:{schedules, pagination}}`
///   - `server/api/songs/index.get.ts`     → `{success, data:{songs, total}}`
///   - `server/api/open/songs/request.post.ts`（字段白名单）
///   - `server/services/songRequestService.ts`（zod `songRequestBodySchema`）
///
/// 解析原则：**宽容**。`data` 既可能是 Map（`{songs, pagination}`）也可能被
/// 后端微调成数组；封面字段历史上叫过 `coverUrl`，现在叫 `cover`；分页可能
/// 缺失。因此所有读取都走 [VoiceHubJson.pickList] / [VoiceHubJson.pickMap] /
/// [VoiceHubJson.str] 等空安全取值器，任一层缺失都退化成空值而不是抛异常。
/// ════════════════════════════════════════════════════════════════════════
library;

/// VoiceHub JSON 宽容取值工具。
///
/// 后端不同端点（open / 私有 / 历史版本）返回形状不完全一致，统一在这里兜底，
/// 避免每处 `as Map<String, dynamic>` 强转在微调后直接抛 CastError。
abstract final class VoiceHubJson {
  /// 把任意值转成 Map；非 Map 返回空表。
  static Map<String, dynamic> map(Object? v) =>
      v is Map<String, dynamic> ? v : const <String, dynamic>{};

  /// 把任意值转成 List；非 List 返回空表。
  static List<dynamic> list(Object? v) =>
      v is List<dynamic> ? v : const <dynamic>[];

  /// 字符串：非字符串按 `toString()`（null → ''）。
  static String str(Object? v) => v == null ? '' : v.toString();

  /// 可空字符串：空串与 null 都归一成 null。
  static String? strOrNull(Object? v) {
    if (v == null) return null;
    final String s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// 整数：支持 num / 数字字符串，失败回退 [fallback]。
  static int intOf(Object? v, {int fallback = 0}) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  /// 可空整数：无法解析时返回 null（用于「后端没给时长」与「时长为 0」区分）。
  static int? intOrNull(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// 布尔：支持 bool / 'true' / 1。
  static bool boolOf(Object? v, {bool fallback = false}) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final String s = v.toLowerCase().trim();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return fallback;
  }

  /// 从响应体里取出列表：兼容 `data` 为数组、`data.data` 为数组、
  /// `data.data.<key>` 为数组三种形状。
  ///
  /// [key] 为期望的子字段名（如 `songs` / `schedules`）。
  static List<dynamic> pickList(Object? decoded, String key) {
    final Map<String, dynamic> top = map(decoded);
    if (top.isEmpty) return const <dynamic>[];
    final Object? payload = top['data'];
    if (payload is List<dynamic>) return payload;
    final Map<String, dynamic> body = map(payload);
    final Object? inner = body[key];
    if (inner is List<dynamic>) return inner;
    // 兜底一：`data` 本身是列表常被套在 `data.data` 之外的 `items`/`list`。
    for (final String alt in <String>['items', 'list', 'results']) {
      final Object? v = body[alt] ?? top[alt];
      if (v is List<dynamic>) return v;
    }
    // 兜底二：顶层直接就是 `{songs: [...]}`。
    final Object? topInner = top[key];
    return topInner is List<dynamic> ? topInner : const <dynamic>[];
  }

  /// 从响应体里取出分页：兼容 `data.pagination` 与 `data.total` 两种写法。
  static VoiceHubPagination pagination(
    Object? decoded,
    int fallbackPage,
    int fallbackLimit,
  ) {
    final Map<String, dynamic> top = map(decoded);
    final Map<String, dynamic> body = map(top['data']);
    final Map<String, dynamic> p = map(body['pagination']);
    final int total = intOrNull(p['total']) ??
        intOrNull(body['total']) ??
        intOrNull(top['total']) ??
        0;
    final int limit = intOrNull(p['limit']) ??
        intOrNull(p['pageSize']) ??
        (fallbackLimit > 0 ? fallbackLimit : 0);
    final int page = intOrNull(p['page']) ?? fallbackPage;
    final int totalPages =
        intOrNull(p['totalPages']) ?? (limit > 0 ? (total / limit).ceil() : 0);
    return VoiceHubPagination(
      page: page,
      limit: limit,
      total: total,
      totalPages: totalPages,
    );
  }
}

/// 分页信息（`{page, limit, total, totalPages}`）。
class VoiceHubPagination {
  const VoiceHubPagination({
    this.page = 1,
    this.limit = 0,
    this.total = 0,
    this.totalPages = 0,
  });

  final int page;
  final int limit;
  final int total;
  final int totalPages;

  /// 是否还有下一页（无分页信息时保守返回 false，避免无限加载）。
  bool hasMore(int currentPage, int currentLimit) {
    if (totalPages > 0) return currentPage < totalPages;
    if (total > 0 && currentLimit > 0) {
      return currentPage * currentLimit < total;
    }
    return false;
  }
}

/// 播出时段（`playTimes` 表）。
class VoiceHubPlayTime {
  const VoiceHubPlayTime({
    this.id = 0,
    this.name = '',
    this.startTime = '',
    this.endTime = '',
    this.enabled = false,
  });

  final int id;
  final String name;
  final String startTime;
  final String endTime;
  final bool enabled;

  factory VoiceHubPlayTime.fromJson(Object? raw) {
    final Map<String, dynamic> j = VoiceHubJson.map(raw);
    return VoiceHubPlayTime(
      id: VoiceHubJson.intOf(j['id']),
      name: VoiceHubJson.str(j['name']),
      startTime: VoiceHubJson.str(j['startTime']),
      endTime: VoiceHubJson.str(j['endTime']),
      enabled: VoiceHubJson.boolOf(j['enabled']),
    );
  }
}

/// 一条点歌（`songs` 表）。
///
/// 字段对齐 `server/api/open/songs.get.ts` 的 `formattedSongs` 与
/// `server/api/songs/index.get.ts` 的 `SongResponse` 交集。
class VoiceHubSong {
  const VoiceHubSong({
    required this.id,
    this.title = '',
    this.artist = '',
    this.cover,
    this.durationSeconds,
    this.playUrl,
    this.musicPlatform = '',
    this.musicId = '',
    this.played = false,
    this.scheduled = false,
    this.semester = '',
    this.requestedAt = '',
    this.voteCount = 0,
    this.voted = false,
    this.submissionNote,
    this.submissionNotePublic = false,
    this.preferredPlayTimeId,
    this.preferredPlayTime,
    this.requester = '',
    this.requesterId,
  });

  final int id;
  final String title;
  final String artist;

  /// 封面地址。后端字段名为 `cover`（历史版本曾为 `coverUrl`）。
  final String? cover;

  /// 时长（秒）。可能为 null（后端未补齐）。
  final int? durationSeconds;

  /// 直链播放地址（有值时可不经平台解析直接播）。
  final String? playUrl;

  /// 平台标识：`netease` / `bilibili` / `qq` …（后端 `musicPlatform`）。
  final String musicPlatform;

  /// 平台内曲目 id（B 站通常只有 `BVxx` / `avxx` 本体）。
  ///
  /// ⚠️ **读取侧**可能遇到 `BVxx:cid:page` 复合形式（服务端
  /// `songRequestService.ts:452-465` 用 `bilibiliCid` / `bilibiliPage` 拼出
  /// 并落库），本模型的 [VoiceHubSong.bvid] 取首段即可正常播放。
  /// 但**提交侧不要把复合串塞进 musicId**：服务端会以 `musicId.split(':')[0]`
  /// 重建 id，未传 `bilibiliCid` 时 cid/page 会被整段丢掉。分 P 必须走
  /// `VoiceHubClient.submitSong` 的 bilibiliCid / bilibiliPage 独立字段。
  final String musicId;

  final bool played;
  final bool scheduled;
  final String semester;

  /// 投稿时间（后端已格式化为字符串，直接展示）。
  final String requestedAt;

  final int voteCount;

  /// 当前用户是否已投过票（仅私有端点 `/api/songs` 返回）。
  final bool voted;

  /// 投稿留言（后端对未公开留言返回 null）。
  final String? submissionNote;
  final bool submissionNotePublic;
  final int? preferredPlayTimeId;
  final VoiceHubPlayTime? preferredPlayTime;

  /// 投稿人展示名（后端已处理重名后缀）。
  final String requester;

  /// 投稿人 id：用于「我的投稿」判 own（可能为 null）。
  final int? requesterId;

  /// 是否已排期/已播放——两者都不可再投票（后端 votes 前置校验）。
  bool get votable => !played && !scheduled;

  /// 平台是否为 B 站（后端以 `musicPlatform === 'bilibili'` 或 `BV`/`av` 前缀判定）。
  bool get isBilibili =>
      musicPlatform.toLowerCase().contains('bilibili') ||
      musicId.startsWith('BV') ||
      musicId.startsWith('av');

  /// 平台是否为网易云。
  bool get isNetease => musicPlatform.toLowerCase().contains('netease');

  /// B 站 bvid（复合 musicId 取首段）。
  String get bvid => musicId.split(':').first;

  factory VoiceHubSong.fromJson(Object? raw) {
    final Map<String, dynamic> j = VoiceHubJson.map(raw);
    final Object? rawNote = j['submissionNote'];
    final Object? cover = j['cover'] ?? j['coverUrl'];
    final Object? playTime =
        j['preferredPlayTime'] ?? j['playTime'];
    return VoiceHubSong(
      id: VoiceHubJson.intOf(j['id']),
      title: VoiceHubJson.str(j['title']),
      artist: VoiceHubJson.str(j['artist']),
      cover: VoiceHubJson.strOrNull(cover),
      durationSeconds: VoiceHubJson.intOrNull(j['durationSeconds']),
      playUrl: VoiceHubJson.strOrNull(j['playUrl']),
      musicPlatform: VoiceHubJson.str(j['musicPlatform']),
      musicId: VoiceHubJson.str(j['musicId']),
      played: VoiceHubJson.boolOf(j['played']),
      scheduled: VoiceHubJson.boolOf(j['scheduled']),
      semester: VoiceHubJson.str(j['semester']),
      requestedAt: VoiceHubJson.str(
        j['requestedAt'] ?? j['createdAt'],
      ),
      voteCount:
          VoiceHubJson.intOf(j['voteCount'] ?? j['votes'] ?? j['vote_count']),
      voted: VoiceHubJson.boolOf(j['voted']),
      submissionNote: VoiceHubJson.strOrNull(rawNote),
      submissionNotePublic:
          VoiceHubJson.boolOf(j['submissionNotePublic'], fallback: false),
      preferredPlayTimeId: VoiceHubJson.intOrNull(j['preferredPlayTimeId']),
      preferredPlayTime:
          playTime == null ? null : VoiceHubPlayTime.fromJson(playTime),
      requester: VoiceHubJson.str(j['requester'] ?? j['requestedBy']),
      requesterId: VoiceHubJson.intOrNull(j['requesterId']),
    );
  }

  /// 更新投票数（乐观刷新用）。
  VoiceHubSong copyWithVote({int? voteCount, bool? voted}) => VoiceHubSong(
        id: id,
        title: title,
        artist: artist,
        cover: cover,
        durationSeconds: durationSeconds,
        playUrl: playUrl,
        musicPlatform: musicPlatform,
        musicId: musicId,
        played: played,
        scheduled: scheduled,
        semester: semester,
        requestedAt: requestedAt,
        voteCount: voteCount ?? this.voteCount,
        voted: voted ?? this.voted,
        submissionNote: submissionNote,
        submissionNotePublic: submissionNotePublic,
        preferredPlayTimeId: preferredPlayTimeId,
        preferredPlayTime: preferredPlayTime,
        requester: requester,
        requesterId: requesterId,
      );
}

/// 一条排期（`schedules` 表，已发布）。
///
/// 后端结构是「排期 → 歌曲」两层（`schedules.get.ts` 的 `formattedSchedules`），
/// 这里把播放联动需要的歌曲字段平铺出来，UI 不必再解一层 Map。
class VoiceHubSchedule {
  const VoiceHubSchedule({
    required this.id,
    this.playDate = '',
    this.playDateFormatted = '',
    this.semester = '',
    this.songId = 0,
    this.songTitle = '',
    this.songArtist = '',
    this.songCover,
    this.songPlatform = '',
    this.songMusicId = '',
    this.songDurationSeconds,
    this.songPlayUrl,
    this.songPlayed = false,
    this.songRequestedAt = '',
    this.requester = '',
    this.playTimeId = 0,
    this.playTimeName = '',
    this.playTimeStart = '',
    this.playTimeEnd = '',
    this.collaborators = const <String>[],
  });

  final int id;

  /// 播出日期（ISO 字符串，排序用）。
  final String playDate;

  /// 播出日期（后端格式化后的展示串）。
  final String playDateFormatted;
  final String semester;

  final int songId;
  final String songTitle;
  final String songArtist;
  final String? songCover;
  final String songPlatform;
  final String songMusicId;
  final int? songDurationSeconds;
  final String? songPlayUrl;
  final bool songPlayed;
  final String songRequestedAt;

  /// 投稿人展示名（`requester.name`，可能为 ''）。
  final String requester;

  final int playTimeId;
  final String playTimeName;
  final String playTimeStart;
  final String playTimeEnd;

  /// 联合投稿人姓名列表。
  final List<String> collaborators;

  /// 展示用日期：优先后端格式化串，否则回退原始值。
  String get dateLabel =>
      playDateFormatted.isNotEmpty ? playDateFormatted : playDate;

  /// 时段标签（如「午间 12:00-12:30」）；无时段信息时为空串。
  String get timeLabel {
    if (playTimeName.isEmpty) return '';
    if (playTimeStart.isEmpty && playTimeEnd.isEmpty) return playTimeName;
    return '$playTimeName $playTimeStart-$playTimeEnd';
  }

  factory VoiceHubSchedule.fromJson(Object? raw) {
    final Map<String, dynamic> j = VoiceHubJson.map(raw);
    final Map<String, dynamic> song = VoiceHubJson.map(j['song']);
    final Map<String, dynamic> playTime = VoiceHubJson.map(j['playTime']);
    // 排期接口的歌曲字段在 `song` 子对象里；若后端某天平铺到顶层，也兼容。
    // 注意：open/schedules 的 song 选择列（`schedules.get.ts:77-89`）不含
    // playUrl（对比 open/songs 的 `songs.get.ts:216` 有），所以 songPlayUrl
    // 对排期**恒为 null 是预期行为**，不是解析失败。影响见
    // `voicehub_play.dart` 的 playSchedule 注释。
    final Object? cover = song['cover'] ?? song['coverUrl'] ?? j['cover'];
    final Object? musicId = song['musicId'] ?? j['musicId'];
    final Object? platform = song['musicPlatform'] ?? j['musicPlatform'];
    final Object? playUrl = song['playUrl'] ?? j['playUrl'];
    final Object? duration =
        song['durationSeconds'] ?? j['durationSeconds'];
    final Map<String, dynamic> requester =
        VoiceHubJson.map(j['requester'] ?? song['requester']);
    final List<dynamic> rawCollaborators =
        VoiceHubJson.list(song['collaborators']);

    return VoiceHubSchedule(
      id: VoiceHubJson.intOf(j['id']),
      playDate: VoiceHubJson.str(j['playDate']),
      playDateFormatted:
          VoiceHubJson.str(j['playDateFormatted'] ?? j['playDate']),
      semester: VoiceHubJson.str(j['semester'] ?? song['semester']),
      songId: VoiceHubJson.intOf(song['id'] ?? j['songId']),
      songTitle: VoiceHubJson.str(song['title'] ?? j['title']),
      songArtist: VoiceHubJson.str(song['artist'] ?? j['artist']),
      songCover: VoiceHubJson.strOrNull(cover),
      songPlatform: VoiceHubJson.str(platform),
      songMusicId: VoiceHubJson.str(musicId),
      songDurationSeconds: VoiceHubJson.intOrNull(duration),
      songPlayUrl: VoiceHubJson.strOrNull(playUrl),
      songPlayed: VoiceHubJson.boolOf(song['played']),
      songRequestedAt: VoiceHubJson.str(
        song['requestedAt'] ?? song['createdAt'],
      ),
      requester: VoiceHubJson.str(
        requester['name'] ?? j['requesterName'] ?? song['requester'],
      ),
      playTimeId: VoiceHubJson.intOf(
        playTime['id'] ?? j['playTimeId'],
      ),
      playTimeName: VoiceHubJson.str(playTime['name'] ?? j['playTimeName']),
      playTimeStart: VoiceHubJson.str(playTime['startTime']),
      playTimeEnd: VoiceHubJson.str(playTime['endTime']),
      collaborators: <String>[
        for (final dynamic c in rawCollaborators)
          VoiceHubJson.str(VoiceHubJson.map(c)['name']),
      ],
    );
  }
}

/// 点歌列表结果（列表 + 分页）。
class VoiceHubSongPage {
  const VoiceHubSongPage({
    this.songs = const <VoiceHubSong>[],
    this.pagination = const VoiceHubPagination(),
  });

  final List<VoiceHubSong> songs;
  final VoiceHubPagination pagination;
}

/// 排期列表结果（列表 + 分页）。
class VoiceHubSchedulePage {
  const VoiceHubSchedulePage({
    this.schedules = const <VoiceHubSchedule>[],
    this.pagination = const VoiceHubPagination(),
  });

  final List<VoiceHubSchedule> schedules;
  final VoiceHubPagination pagination;
}

/// 投稿额度状态（`GET /api/songs/submission-status`）。
///
/// 全部字段可空：后端未开启限额时返回的结构字段更少，UI 只按需展示非空项。
class VoiceHubSubmissionStatus {
  const VoiceHubSubmissionStatus({
    this.limitEnabled = false,
    this.submissionClosed = false,
    this.timeLimitationEnabled = false,
    this.dailyLimit,
    this.weeklyLimit,
    this.monthlyLimit,
    this.dailyUsed = 0,
    this.weeklyUsed = 0,
    this.monthlyUsed = 0,
    this.dailyRemaining,
    this.weeklyRemaining,
    this.monthlyRemaining,
    this.currentTimePeriodName = '',
  });

  final bool limitEnabled;
  final bool submissionClosed;
  final bool timeLimitationEnabled;
  final int? dailyLimit;
  final int? weeklyLimit;
  final int? monthlyLimit;
  final int dailyUsed;
  final int weeklyUsed;
  final int monthlyUsed;
  final int? dailyRemaining;
  final int? weeklyRemaining;
  final int? monthlyRemaining;
  final String currentTimePeriodName;

  /// 剩余额度（日/周/月取第一个有值的），无限制时返回 null。
  int? get remaining =>
      dailyRemaining ?? weeklyRemaining ?? monthlyRemaining;

  /// UI 文案：无限制或未开启时返回空串（由调用方决定是否展示）。
  String get summary {
    if (submissionClosed) return '投稿已关闭';
    final int? left = remaining;
    if (!limitEnabled || left == null) return '';
    return '本期剩余投稿额度 $left 次';
  }

  factory VoiceHubSubmissionStatus.fromJson(Object? raw) {
    final Map<String, dynamic> j = VoiceHubJson.map(raw);
    final Map<String, dynamic> period =
        VoiceHubJson.map(j['currentTimePeriod']);
    return VoiceHubSubmissionStatus(
      limitEnabled: VoiceHubJson.boolOf(j['limitEnabled']),
      submissionClosed: VoiceHubJson.boolOf(j['submissionClosed']),
      timeLimitationEnabled:
          VoiceHubJson.boolOf(j['timeLimitationEnabled']),
      dailyLimit: VoiceHubJson.intOrNull(j['dailyLimit']),
      weeklyLimit: VoiceHubJson.intOrNull(j['weeklyLimit']),
      monthlyLimit: VoiceHubJson.intOrNull(j['monthlyLimit']),
      dailyUsed: VoiceHubJson.intOf(j['dailyUsed']),
      weeklyUsed: VoiceHubJson.intOf(j['weeklyUsed']),
      monthlyUsed: VoiceHubJson.intOf(j['monthlyUsed']),
      dailyRemaining: VoiceHubJson.intOrNull(j['dailyRemaining']),
      weeklyRemaining: VoiceHubJson.intOrNull(j['weeklyRemaining']),
      monthlyRemaining: VoiceHubJson.intOrNull(j['monthlyRemaining']),
      currentTimePeriodName: VoiceHubJson.str(period['name']),
    );
  }
}

/// B 站曲目 id（`BVxx[:cid[:page]]`）拆分。
///
/// 服务端 `songRequestService.ts:452-465` 在 isBilibili 时会把 `musicId`
/// 按 `split(':')[0]` 重建：没给 `bilibiliCid` 的话，`BVxx:cid:page` 会被
/// 截成纯 `BVxx`，分 P 信息丢失。所以提交时必须把 cid / page 拆成
/// `bilibiliCid` / `bilibiliPage` 两个独立字段（`request.post.ts` 白名单里
/// 有这两个字段），读取时再拼回来（服务端返回的 `musicId` 就是拼好的）。
class VoiceHubBilibiliId {
  const VoiceHubBilibiliId({
    required this.bvid,
    this.cid = '',
    this.page = '',
  });

  /// 视频 BV 号（也可能是 av 号）。
  final String bvid;

  /// 分 P 的 cid。
  final String cid;

  /// 分 P 序号字符串（保持字符串形态，服务端自己 `Number()` 转换）。
  final String page;

  static const VoiceHubBilibiliId _empty =
      VoiceHubBilibiliId(bvid: '');

  /// 是否为空（非 B 站曲目 / 空 id）。
  bool get isEmpty => bvid.isEmpty;

  /// 按 `:` 拆分；非 B 站形态（`BV`/`av` 前缀都不满足）返回空。
  static VoiceHubBilibiliId parse(String? raw) {
    final String id = (raw ?? '').trim();
    if (id.isEmpty) return _empty;
    if (!id.startsWith('BV') && !id.startsWith('av')) return _empty;
    final List<String> parts = id.split(':');
    return VoiceHubBilibiliId(
      bvid: parts[0],
      cid: parts.length > 1 ? parts[1] : '',
      page: parts.length > 2 ? parts[2] : '',
    );
  }
}

/// VoiceHub 异常。
class VoiceHubException implements Exception {
  const VoiceHubException(this.message);

  final String message;

  @override
  String toString() => message;
}
