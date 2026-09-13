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
import '../../models/capability.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/content/capability_providers.dart';
import '../../providers/search/search_history_provider.dart';
import '../../providers/sources/netease_provider.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/track_action_buttons.dart';
import '../../widgets/sources/netease_login_sheet.dart';
import '../../widgets/sources/bilibili_login_sheet.dart';
import '../../widgets/notification/app_notify.dart';

/// 首批页大小（与各源 provider 内默认值一致）：网易云 30 / B站 20。
const int kNeteaseSearchPageSize = 30;
const int kBilibiliSearchPageSize = 20;

/// 媒体源筛选。
enum _SrcFilter {
  all('全部'),
  local('本地'),
  netease('网易云'),
  bilibili('哔哩哔哩');

  const _SrcFilter(this.label);

  final String label;
}

/// 筛选器对应的能力 id；「全部」不绑定单一能力。
///
/// 本地曲库对应 `local.library`（本地固有能力，enabled 恒为 true），
/// 两个在线源对应各自的搜索能力。
String? _capabilityOfFilter(_SrcFilter f) => switch (f) {
  _SrcFilter.all => null,
  _SrcFilter.local => 'local.library',
  _SrcFilter.netease => 'netease.search',
  _SrcFilter.bilibili => 'bilibili.search',
};

/// 该筛选器对应的能力是否可用（受设置页「内容来源」里开关的约束）。
///
/// 判定顺序与探索页一致——服务端不可用时不能把本机能力藏起来：
/// 1. 用户显式关掉 → 不可用。选配存在本地，不依赖服务端可达性。
/// 2. 能力清单里有 → 以清单的 enabled / 是否 planned 为准。
/// 3. 清单里没有（离线且无缓存）→ 放行。
bool _filterAllows(WidgetRef ref, _SrcFilter f) {
  final String? id = _capabilityOfFilter(f);
  if (id == null) return true;
  if (ref.watch(capabilitySelectionProvider).contains(id)) return false;
  for (final Capability c in ref.watch(capabilitiesProvider)) {
    if (c.id == id) return c.enabled && !c.isPlanned;
  }
  return true;
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
  bool _disclaimerShown = false;

  // ── 分页状态（按源；本地源是内存过滤，无需分页）─────────────────────
  /// 触底追加批次（首批由 provider 提供，这里只缓存追加出来的结果）。
  final List<Track> _neMore = <Track>[];
  final List<Track> _biMore = <Track>[];

  /// 下一次请求的位置：网易云用 offset（0 起），B站用 page（1 起）。
  int _neOffset = kNeteaseSearchPageSize;
  int _biPage = 2;
  bool _neHasMore = true;
  bool _biHasMore = true;
  bool _neLoading = false;
  bool _biLoading = false;
  bool _neFailed = false;
  bool _biFailed = false;

  @override
  void initState() {
    super.initState();
    _playErrorSub = ref
        .read(audioServiceProvider)
        .playErrorStream
        .listen(_onPlayError);
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

  /// 重置全部分页状态（换词 / 下拉刷新时调用）。
  void _resetPaging() {
    _neMore.clear();
    _biMore.clear();
    _neOffset = kNeteaseSearchPageSize;
    _biPage = 2;
    _neHasMore = true;
    _biHasMore = true;
    _neLoading = false;
    _biLoading = false;
    _neFailed = false;
    _biFailed = false;
  }

  void _submit(String raw) {
    final String kw = raw.trim();
    if (kw.isNotEmpty) {
      ref.read(searchHistoryProvider.notifier).add(kw);
    }
    // 同词重搜时 provider 命中缓存不会重发 → 用户会感觉「按了搜索没反应」。
    // 显式失效，强制重取首批（换词时也顺带清掉旧词的缓存）。
    ref.invalidate(neteaseSearchProvider(kw));
    ref.invalidate(bilibiliSearchProvider(kw));
    setState(() {
      _keyword = kw;
      _resetPaging();
    });
  }

  /// 下拉刷新：清空分页状态并强制重取两个在线源的首批。
  Future<void> _refresh() async {
    if (_keyword.isEmpty) return;
    setState(_resetPaging);
    ref.invalidate(neteaseSearchProvider(_keyword));
    ref.invalidate(bilibiliSearchProvider(_keyword));
    try {
      await Future.wait<void>(<Future<void>>[
        ref.read(neteaseSearchProvider(_keyword).future).then<void>((_) {}),
        ref.read(bilibiliSearchProvider(_keyword).future).then<void>((_) {}),
      ]);
    } catch (_) {
      // 失败态由各源 provider 的 error 分支在界面上呈现。
    }
  }

  /// `_filterAllows` 的只读变体：分页回调不在 build 期，不能 watch。
  bool _capOn(String id) {
    if (ref.read(capabilitySelectionProvider).contains(id)) return false;
    for (final Capability c in ref.read(capabilitiesProvider)) {
      if (c.id == id) return c.enabled && !c.isPlanned;
    }
    return true;
  }

  Future<void> _loadMoreNetease() => _loadMore(netease: true);

  Future<void> _loadMoreBilibili() => _loadMore(netease: false);

  /// 聚合视图：两个源各自往后取一批（已取尽的会在 [_loadMore] 里自行短路）。
  Future<void> _loadMoreAll() async {
    await Future.wait<void>(<Future<void>>[
      _loadMore(netease: true),
      _loadMore(netease: false),
    ]);
  }

  /// 触底加载更多。网易云按 offset 翻页，B站按 page 翻页。
  ///
  /// 追加前按 `uri` 与已有结果统一去重；若本批去重后一条没新增，说明该源已
  /// 取尽（offset/page 越界时接口返回空或重复），置 `hasMore = false` 兜底，
  /// 否则会无限触发。offset/page 用**原始返回条数**推进。
  Future<void> _loadMore({required bool netease}) async {
    if (_keyword.isEmpty) return;
    final String kwAtStart = _keyword;
    if (netease) {
      if (!ref.read(neteaseAuthProvider).isLoggedIn ||
          !_capOn('netease.search')) {
        return;
      }
      if (_neLoading || !_neHasMore) return;
    } else {
      if (!_capOn('bilibili.search')) return;
      if (_biLoading || !_biHasMore) return;
    }
    setState(() {
      if (netease) {
        _neLoading = true;
        _neFailed = false;
      } else {
        _biLoading = true;
        _biFailed = false;
      }
    });
    try {
      final List<Track> raw = netease
          ? await ref.read(neteaseSourceProvider).search(
                _keyword,
                limit: kNeteaseSearchPageSize,
                offset: _neOffset,
              )
          : await ref.read(bilibiliSourceProvider).search(
                _keyword,
                limit: kBilibiliSearchPageSize,
                page: _biPage,
              );
      if (!mounted) return;
      // ⚠️ 竞态守卫：await 期间用户可能又搜了别的词（_submit 会换 _keyword 并
      // 清空追加批次）。若关键词已变，这批结果属于旧词，直接丢弃，避免把旧词
      // 的曲目追加进新词列表。
      if (kwAtStart != _keyword) return;
      final List<Track> existing = netease
          ? <Track>[
              ...?ref.read(neteaseSearchProvider(_keyword)).valueOrNull,
              ..._neMore,
            ]
          : <Track>[
              ...?ref.read(bilibiliSearchProvider(_keyword)).valueOrNull,
              ..._biMore,
            ];
      final Set<String> seen = <String>{for (final Track t in existing) t.uri};
      final List<Track> added = <Track>[
        for (final Track t in raw)
          if (seen.add(t.uri)) t,
      ];
      setState(() {
        if (netease) {
          _neMore.addAll(added);
          _neOffset += raw.length;
          if (added.isEmpty) _neHasMore = false;
        } else {
          _biMore.addAll(added);
          _biPage += 1;
          if (added.isEmpty) _biHasMore = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (netease) {
          _neFailed = true;
        } else {
          _biFailed = true;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          if (netease) {
            _neLoading = false;
          } else {
            _biLoading = false;
          }
        });
      }
    }
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
          FilledButton(
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
    if (!mounted) return;
    final bool? ok = await showNeteaseLoginSheet(context);
    if (ok == true && mounted) appNotify(context, '已登录网易云');
  }

  Future<void> _openBilibiliLogin() async {
    if (!await _ensureDisclaimer()) return;
    if (!mounted) return;
    final bool? ok = await showBilibiliLoginSheet(context);
    if (ok == true && mounted) appNotify(context, '已登录哔哩哔哩');
  }

  /// 点播：把当前结果列表作为播放队列传入，使自动续播在搜索列表内循环
  /// （cl64-5：搜索列表作播放队列）。
  Future<void> _play(Track t, [List<Track>? queue]) async {
    final String msg = await ref
        .read(playbackActionsProvider)
        .playTrack(t, queue: queue);
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
          if (_keyword.isEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            _buildHistory(),
          ],
          const SizedBox(height: AppSpace.md),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  /// 源筛选 chips：全部 / 本地 / 网易云 / 哔哩哔哩（被关掉的能力不出现在列表里）。
  Widget _buildSourceFilter() {
    final List<_SrcFilter> visible = _SrcFilter.values
        .where((_SrcFilter f) => _filterAllows(ref, f))
        .toList(growable: false);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          // 用下标而非 values.last 判断间距：过滤后最后一个可见项不再是
          // values.last，照旧写法会在末尾多留一个空隙。
          for (int i = 0; i < visible.length; i++) ...<Widget>[
            ChoiceChip(
              label: Text(visible[i].label, style: context.appText.caption),
              selected: _filter == visible[i],
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _filter = visible[i]),
            ),
            if (i != visible.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  /// 登录状态条（网易云 / B站，未登录显示登录按钮）。
  ///
  /// 已关掉的能力不再提示登录——用户明确说了不要这个来源，再催他登录是自相矛盾。
  Widget _buildLoginStrip() {
    final bool ne = ref.watch(neteaseAuthProvider).isLoggedIn;
    final bool bi = ref.watch(bilibiliAuthProvider).isLoggedIn;
    final bool neOn = _filterAllows(ref, _SrcFilter.netease);
    final bool biOn = _filterAllows(ref, _SrcFilter.bilibili);
    final bool need =
        (_filter == _SrcFilter.netease && neOn && !ne) ||
        (_filter == _SrcFilter.bilibili && biOn && !bi) ||
        (_filter == _SrcFilter.all && ((neOn && !ne) || (biOn && !bi)));
    if (!need) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        if (neOn && !ne)
          ActionChip(
            avatar: Icon(
              Icons.music_note_rounded,
              size: 14,
              color: context.appColors.accent,
            ),
            label: Text('登录网易云', style: context.appText.caption),
            visualDensity: VisualDensity.compact,
            onPressed: _openNeteaseLogin,
          ),
        if (biOn && !bi)
          ActionChip(
            avatar: Icon(
              Icons.video_library_outlined,
              size: 14,
              color: context.appColors.accent,
            ),
            label: Text('登录哔哩哔哩', style: context.appText.caption),
            visualDensity: VisualDensity.compact,
            onPressed: _openBilibiliLogin,
          ),
      ],
    );
  }

  Widget _buildHistory() {
    final List<String> history = ref.watch(searchHistoryProvider);
    if (history.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('搜索历史', style: context.appText.artist),
            const Spacer(),
            FilledButton(
              onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
              child: Text(
                '清空',
                style: context.appText.artist.copyWith(
                  color: context.appColors.iconInactive,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: history.map((String h) {
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
        prefixIcon: Icon(
          Icons.search_rounded,
          size: AppSize.iconSm,
          color: context.appColors.iconInactive,
        ),
        suffixIcon: _keyword.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _queryCtrl.clear();
                  _submit('');
                },
                icon: Icon(
                  Icons.close_rounded,
                  size: AppSize.iconSm,
                  color: context.appColors.iconInactive,
                ),
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
    // 当前筛选对应的能力被关掉了（很可能刚在设置页改过）：退回「全部」，
    // 而不是继续渲染一个用户已经明确关掉的来源。
    if (!_filterAllows(ref, _filter)) return _buildAll();
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
            .where(
              (Track t) =>
                  t.title.toLowerCase().contains(kw) ||
                  t.artist.toLowerCase().contains(kw),
            )
            .toList();
        if (hits.isEmpty) {
          return const _HintPanel(
            icon: Icons.music_off_rounded,
            message: '本地没有匹配的曲目',
          );
        }
        return _TrackList(tracks: hits, onTap: (t) => _play(t, hits));
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace st) => const _HintPanel(
        icon: Icons.error_outline_rounded,
        message: '本地曲库加载失败',
      ),
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
    final AsyncValue<List<Track>> result = ref.watch(
      neteaseSearchProvider(_keyword),
    );
    return result.when(
      data: (List<Track> tracks) {
        // 首批 + 触底追加批次（按 uri 去重）。
        final List<Track> all = _mergeUnique(tracks, _neMore);
        if (all.isEmpty) {
          return const _HintPanel(
            icon: Icons.music_off_rounded,
            message: '网易云没有找到相关歌曲',
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: _TrackList(
            tracks: all,
            onTap: (Track t) => _play(t, all),
            sourceTag: '网易云 · 音乐源',
            onLoadMore: _loadMoreNetease,
            isLoadingMore: _neLoading,
            hasMore: _neHasMore,
            loadFailed: _neFailed,
          ),
        );
      },
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
    // T7：B站搜索免登录。搜索接口本就公开（WBI 签名），未登录也能搜；
    // 登录只影响播放时的清晰度上限（未登录=标清，登录后=高清/超清）。
    final AsyncValue<List<Track>> result = ref.watch(
      bilibiliSearchProvider(_keyword),
    );
    return result.when(
      data: (List<Track> tracks) {
        final List<Track> all = _mergeUnique(tracks, _biMore);
        if (all.isEmpty) {
          return const _HintPanel(
            icon: Icons.music_off_rounded,
            message: 'B站没有找到相关视频',
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: _TrackList(
            tracks: all,
            onTap: (Track t) => _play(t, all),
            sourceTag: 'B站 · 视频源',
            onLoadMore: _loadMoreBilibili,
            isLoadingMore: _biLoading,
            hasMore: _biHasMore,
            loadFailed: _biFailed,
          ),
        );
      },
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

  /// 全部：本地 + 网易云（已登录）+ B站（免登录）合并展示。
  Widget _buildAll() {
    final bool ne = ref.watch(neteaseAuthProvider).isLoggedIn;
    // 能力开关：在设置页「内容来源」里关掉的来源，既不出结果也不发请求。
    // 登录态与开关是两件事——未登录是「暂时用不了」，关掉是「我不要它」。
    // T7：B站搜索免登录，未登录也出结果；登录只影响播放清晰度。
    final bool neOn = _filterAllows(ref, _SrcFilter.netease);
    final bool biOn = _filterAllows(ref, _SrcFilter.bilibili);
    final bool localOn = _filterAllows(ref, _SrcFilter.local);
    final AsyncValue<List<Track>> lib = ref.watch(musicLibraryProvider);
    final String kw = _keyword.toLowerCase();
    final List<Track> localHits =
        lib.valueOrNull
            ?.where(
              (Track t) =>
                  t.title.toLowerCase().contains(kw) ||
                  t.artist.toLowerCase().contains(kw),
            )
            .toList() ??
        const <Track>[];
    // 远程源结果（网易云需登录；被关掉的源不请求）。
    // 直接用 AsyncValue 而非 FutureBuilder：触底追加会频繁 setState，
    // FutureBuilder 每次重建都会重新订阅、出现「整列表闪没」的一帧。
    final bool neActive = ne && neOn;
    final AsyncValue<List<Track>> neAsync = neActive
        ? ref.watch(neteaseSearchProvider(_keyword))
        : const AsyncValue<List<Track>>.data(<Track>[]);
    final AsyncValue<List<Track>> biAsync = biOn
        ? ref.watch(bilibiliSearchProvider(_keyword))
        : const AsyncValue<List<Track>>.data(<Track>[]);
    final List<Track> neHits = neAsync.valueOrNull ?? const <Track>[];
    final List<Track> biHits = biAsync.valueOrNull ?? const <Track>[];
    // 本地命中固定在前面；触底追加批次接在各自源之后；整体按 uri 去重。
    final List<Track> all = _mergeUnique(
      <Track>[
        if (localOn) ...localHits,
        if (neActive) ...neHits,
        if (biOn) ...biHits,
      ],
      <Track>[
        if (neActive) ..._neMore,
        if (biOn) ..._biMore,
      ],
    );
    if (all.isEmpty) {
      final bool loading = (neActive && neAsync.isLoading) ||
          (biOn && biAsync.isLoading);
      if (loading) return const Center(child: CircularProgressIndicator());
      return const _HintPanel(
        icon: Icons.search_off_rounded,
        message: '没有匹配的结果',
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _TrackList(
        tracks: all,
        onTap: (Track t) => _play(t, all),
        // 行内按 sourceId 打「源 · 类型」徽标：网易云=音乐源，B站=视频源。
        tagOf: (Track t) => switch (t.sourceId) {
          'netease' => '网易云 · 音乐源',
          'bilibili' => 'B站 · 视频源',
          'local' => '本地 · 音乐源',
          _ => null,
        },
        onLoadMore: (neActive || biOn) ? _loadMoreAll : null,
        isLoadingMore: _neLoading || _biLoading,
        // 只统计当前真正参与聚合的源，避免「单源取尽 + 另一源被关掉」
        // 时尾部永远停在「加载中/空占位」而非「没有更多了」。
        hasMore: (neActive && _neHasMore) || (biOn && _biHasMore),
        loadFailed: _neFailed || _biFailed,
      ),
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
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 合并两组曲目并按 `uri` 去重（保留先出现的顺序）。
List<Track> _mergeUnique(List<Track> base, Iterable<Track> extra) {
  final Set<String> seen = <String>{for (final Track t in base) t.uri};
  final List<Track> out = <Track>[...base];
  for (final Track t in extra) {
    if (seen.add(t.uri)) out.add(t);
  }
  return out;
}

/// 结果列表（带源徽标，可选触底加载更多）。
class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.tracks,
    required this.onTap,
    this.sourceTag,
    this.tagOf,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.loadFailed = false,
  });

  final List<Track> tracks;
  final ValueChanged<Track> onTap;

  /// 统一源标签（单源列表用）。
  final String? sourceTag;

  /// 按曲目给标签（聚合列表用）。
  final String? Function(Track)? tagOf;

  /// 触底加载更多；为 null 时不启用分页（尾部不加多余 item）。
  final Future<void> Function()? onLoadMore;
  final bool isLoadingMore;

  /// 是否还有下一页；false 时尾部提示「没有更多了」。
  final bool hasMore;

  /// 上一次加载更多失败（尾部换成重试按钮）。
  final bool loadFailed;

  @override
  Widget build(BuildContext context) {
    final bool paging = onLoadMore != null;
    final Widget list = ListView.separated(
      padding: EdgeInsets.zero,
      // 内容不足一屏时也要能下拉（否则 RefreshIndicator 无法触发）。
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: tracks.length + (paging ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.xs),
      itemBuilder: (BuildContext _, int i) {
        if (paging && i == tracks.length) return _buildFooter(context);
        final Track t = tracks[i];
        final String? tag = tagOf != null ? tagOf!(t) : sourceTag;
        return _TrackTile(track: t, tag: tag, onTap: () => onTap(t));
      },
    );
    if (!paging) return list;
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification n) {
        if (hasMore &&
            !isLoadingMore &&
            n is ScrollUpdateNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
          onLoadMore!.call();
        }
        return false;
      },
      child: list,
    );
  }

  /// 尾部三态：加载中 / 加载失败可重试 / 没有更多了。
  Widget _buildFooter(BuildContext context) {
    if (loadFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: FilledButton(
            onPressed: () => onLoadMore?.call(),
            child: const Text('加载失败，点击重试'),
          ),
        ),
      );
    }
    if (isLoadingMore) {
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
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text('没有更多了', style: context.appText.artist),
        ),
      );
    }
    return const SizedBox(height: 12);
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
                            style: context.appText.artist.copyWith(
                              color: context.appColors.iconInactive,
                            ),
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
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.appColors.accentSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tag!,
                    style: context.appText.artist.copyWith(
                      color: context.appColors.accent,
                    ),
                  ),
                ),
              ],
              // T7：B站结果行音质提示（未登录=标清 / 登录=高清）。
              if (track.sourceId == 'bilibili' &&
                  track.extras?['qualityHint'] != null) ...<Widget>[
                const SizedBox(width: AppSpace.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.appColors.bgPlaceholder,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    track.extras!['qualityHint']! as String,
                    style: context.appText.artist.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ),
              ],
              // cl15：投稿 / 收藏（聚合搜索处即点即投）。
              const SizedBox(width: AppSpace.xs),
              TrackActionButtons(track: track),
              const SizedBox(width: AppSpace.xs),
              Icon(
                Icons.play_circle_outline_rounded,
                size: AppSize.icon,
                color: context.appColors.accent,
              ),
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
      cacheWidth: 256,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _CoverFallback(),
      loadingBuilder:
          (BuildContext context, Widget child, ImageChunkEvent? progress) =>
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
      child: Icon(
        Icons.music_note_rounded,
        size: 20,
        color: context.appColors.accent,
      ),
    );
  }
}

/// ⑩：音源搜索改为弹出式底部卡片，全局可调用、无风险。
///
/// 任意页面（音乐卡片 / 游戏内液态玻璃播放器 / 全屏卡片）都能拉起，
/// 内部仍是 [AggregateSearchPage]（网易云 / B站 / 本地三源合一），
/// 退出即回弹，不接管路由，亦不残留页面栈。
Future<void> showAggregateSearchSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext ctx) => const _AggregateSearchSheet(),
  );
}

class _AggregateSearchSheet extends StatelessWidget {
  const _AggregateSearchSheet();

  @override
  Widget build(BuildContext context) {
    final double h = MediaQuery.of(context).size.height;
    return Container(
      height: h * 0.86,
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
      ),
      child: Column(
        children: <Widget>[
          // 拖拽条（提示可下拉关闭）。
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.appColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(child: AggregateSearchPage()),
        ],
      ),
    );
  }
}
