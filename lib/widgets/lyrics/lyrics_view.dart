import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/sources/netease_provider.dart';
import '../../providers/storage/storage_providers.dart';
import '../../services/audio/sources/netease/netease_api.dart';
import '../../services/audio/sources/netease/netease_source.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 歌词模块（解析 + 数据源 + 展示）
/// ════════════════════════════════════════════════════════════════════════
///
/// 独立于播放器实现：[UnifiedPlayer] 只通过可选参数 `lyricsSlot` 承载本组件，
/// 不感知歌词的来源与解析细节。
///
/// ### 数据来源优先级
/// 1. **本地**：与当前曲目**同目录、同名**的 `.lrc` 文件（本地音乐场景）；
/// 2. **远程**：[remoteLyricsFetcherProvider] 钩子（预留网易云等在线歌词源，
///    当前默认未接入，返回 `null`）。
///
/// ### 线程
/// 文件 IO 与解析都在 [FutureProvider] 的异步链路里完成，不在 `build` 中执行，
/// 因此不会阻塞 UI 帧。

/// 一行歌词：`(时间轴, 文本)`。
typedef LyricLine = (Duration time, String text);

/// 歌词单行占位高度（容纳两行 15sp 文本：15 × 1.25 × 2 ≈ 37.5，留余量取 40）。
/// 同时作为「单行完整显示」的最小高度基准（见 [LyricsView]）。
const double _kLyricRowExtent = 40.0;

// ════════════════════════════════════════════════════════════════════════
// 一、解析：标准 .lrc
// ════════════════════════════════════════════════════════════════════════

/// 标准 `.lrc` 歌词解析器。
///
/// 支持：
/// - `[mm:ss]` / `[mm:ss.xx]` / `[mm:ss.xxx]` 三种时间精度；
/// - 一行多时间轴（`[00:12.30][01:20.10]同一句歌词`）；
/// - `[offset:±ms]` 全局时间补偿（正值表示歌词整体提前）；
/// - 元信息行（`[ti:]` `[ar:]` `[al:]` `[by:]` 等）自动忽略。
///
/// 容错：任何无法识别的行（缺时间轴 / 时间格式非法 / 纯文本）都被静默跳过，
/// 不抛异常，保证坏歌词文件不会让界面崩溃。
abstract final class LrcParser {
  /// 时间轴标签：分:秒(.毫秒)，毫秒位 1~3 位。
  static final RegExp _timeTag =
      RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  /// 时间补偿标签，如 `[offset:-500]`。
  static final RegExp _offsetTag =
      RegExp(r'^\[offset:\s*([+-]?\d{1,7})\s*\]$', caseSensitive: false);

  /// 解析整份 `.lrc` 文本，返回按时间升序排列的歌词行。
  ///
  /// 输入为空 / 全是元信息时返回空列表（由 [LyricsView] 渲染「暂无歌词」）。
  static List<LyricLine> parse(String raw) {
    if (raw.trim().isEmpty) return const <LyricLine>[];

    final List<LyricLine> lines = <LyricLine>[];
    int offsetMs = 0;

    for (final String rawLine in const LineSplitter().convert(raw)) {
      final String line = rawLine.trim();
      if (line.isEmpty) continue;

      // ① 时间补偿标签
      final RegExpMatch? off = _offsetTag.firstMatch(line);
      if (off != null) {
        offsetMs = int.tryParse(off.group(1)!) ?? 0;
        continue;
      }

      // ② 连续时间轴前缀（一行可挂多个时间点）
      final List<Duration> stamps = <Duration>[];
      int cursor = 0;
      while (cursor < line.length) {
        // 允许时间轴之间存在空格：[00:01.00] [00:05.00]文本
        while (cursor < line.length && line[cursor] == ' ') {
          cursor++;
        }
        final Match? m = _timeTag.matchAsPrefix(line, cursor);
        if (m == null) break;
        final Duration? d = _toDuration(m);
        if (d != null) stamps.add(d);
        cursor = m.end;
      }
      // 无时间轴 -> 元信息或垃圾行，跳过（容错）
      if (stamps.isEmpty) continue;

      final String text = line.substring(cursor).trim();
      for (final Duration d in stamps) {
        lines.add((d, text));
      }
    }

    // ③ 应用全局补偿（正 offset = 提前显示）后排序
    if (offsetMs != 0) {
      final Duration shift = Duration(milliseconds: offsetMs);
      for (int i = 0; i < lines.length; i++) {
        final Duration t = lines[i].$1 - shift;
        lines[i] = (t.isNegative ? Duration.zero : t, lines[i].$2);
      }
    }
    lines.sort((LyricLine a, LyricLine b) => a.$1.compareTo(b.$1));
    return lines;
  }

  /// 时间轴正则命中 -> [Duration]；非法（如秒 ≥ 60）返回 null。
  static Duration? _toDuration(Match m) {
    final int? mm = int.tryParse(m.group(1) ?? '');
    final int? ss = int.tryParse(m.group(2) ?? '');
    if (mm == null || ss == null || ss > 59) return null;

    // 小数位：1 位 = 100ms，2 位 = 10ms（厘秒，最常见），3 位 = 1ms
    final String frac = m.group(3) ?? '';
    int ms = 0;
    if (frac.isNotEmpty) {
      final int? v = int.tryParse(frac);
      if (v == null) return null;
      ms = switch (frac.length) {
        1 => v * 100,
        2 => v * 10,
        _ => v,
      };
    }
    return Duration(minutes: mm, seconds: ss, milliseconds: ms);
  }
}

// ════════════════════════════════════════════════════════════════════════
// 二、数据源：本地 .lrc（已实现） + 远程钩子（预留）
// ════════════════════════════════════════════════════════════════════════

/// 远程歌词获取钩子签名：曲目 -> 歌词结果（主词 + 可选译文；无结果返回 null）。
typedef RemoteLyricsFetcher = Future<LyricResult?> Function(Track track);

/// 歌词磁盘缓存：songId -> [LyricResult]，落盘 `<应用文档>/lyrics/<id>.json`，
/// 跨会话复用，离线也能显示（首次联网拉取后长期有效）。
///
/// 网络/IO 异常一律静默吞掉（回退到内存或在线），不让取词链路崩溃。
class LyricsCache {
  LyricsCache(this._dir);
  final Directory _dir;

  File _fileFor(int id) => File('${_dir.path}/lyrics/$id.json');

  Future<LyricResult?> get(int id) async {
    try {
      final File f = _fileFor(id);
      if (!f.existsSync()) return null;
      final Map<String, dynamic> j =
          jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final String? lrc = j['lrc'] as String?;
      if (lrc == null || lrc.isEmpty) return null;
      return LyricResult(lrc: lrc, translation: j['translation'] as String?);
    } catch (_) {
      return null;
    }
  }

  Future<void> put(int id, LyricResult r) async {
    try {
      final File f = _fileFor(id);
      await f.create(recursive: true);
      await f.writeAsString(jsonEncode(<String, dynamic>{
        'lrc': r.lrc,
        'translation': r.translation,
      }));
    } catch (_) {
      // 缓存写入失败不致命
    }
  }
}

/// 歌词缓存目录（应用文档目录；取不到时退化为系统临时目录，仅内存兜底）。
final FutureProvider<LyricsCache> lyricsCacheProvider =
    FutureProvider<LyricsCache>((Ref ref) async {
  try {
    final Directory docs = await getApplicationDocumentsDirectory();
    return LyricsCache(docs);
  } catch (_) {
    return LyricsCache(Directory.systemTemp);
  }
});

/// 远程歌词钩子（**预设网易云实现**）。
///
/// 默认只接网易云：曲目若是 `netease://song/<id>` 占位符（或其 `extras`
/// 带 `songId`），就走 [NeteaseApi.getLyrics] 拉取；先查磁盘缓存，未命中再
/// 联网并回写。其它源返回 null，由上游 [lyricsProvider] 降级为「暂无歌词」。
/// 后续若要接其它在线源，可在 `ProviderScope.overrides` 覆盖本 provider，
/// 歌词界面无需改动。
final Provider<RemoteLyricsFetcher?> remoteLyricsFetcherProvider =
    Provider<RemoteLyricsFetcher?>((Ref ref) {
  final NeteaseApi api = ref.watch(neteaseApiProvider);
  return (Track track) async {
    final int? songId = NeteaseSource.songIdOf(track);
    if (songId == null) return null;
    try {
      final LyricsCache cache = await ref.read(lyricsCacheProvider.future);
      final LyricResult? cached = await cache.get(songId);
      if (cached != null) return cached;
      final LyricResult? fetched = await api.getLyrics(songId);
      if (fetched != null) await cache.put(songId, fetched);
      return fetched;
    } catch (_) {
      return null;
    }
  };
});

/// 读取与曲目同目录、同名的 `.lrc` 文件。
///
/// 仅对**本地文件路径**生效；网络流 / 电台 / `content://` 一律返回 null。
Future<String?> loadLocalLrc(Track track) async {
  final String uri = track.uri;
  if (uri.isEmpty) return null;
  // 非本地文件路径（http 流、Android 媒体库 content uri、asset、
  // 网易云 netease:// 占位符等）跳过，交给远程钩子处理
  if (uri.startsWith('http') ||
      uri.startsWith('content://') ||
      uri.startsWith('asset') ||
      uri.startsWith('netease://')) {
    return null;
  }

  final String base = p.withoutExtension(uri);
  for (final String ext in const <String>['.lrc', '.LRC']) {
    final File f = File('$base$ext');
    try {
      if (await f.exists()) return await _readText(f);
    } catch (_) {
      // 权限 / IO 异常：视作无歌词，不打断播放界面
    }
  }
  return null;
}

/// 读取歌词文本：优先 UTF-8，失败时容错解码（不因编码问题抛异常）。
///
/// TODO(歌词): 国产歌词站下载的 `.lrc` 常见 GBK 编码，当前容错解码会出现乱码，
/// 后续可引入 charset 检测（需新增依赖，暂不改 pubspec）。
Future<String> _readText(File f) async {
  try {
    return await f.readAsString();
  } on FormatException {
    return utf8.decode(await f.readAsBytes(), allowMalformed: true);
  }
}

/// 歌词结果（主词 + 可选译文）：本地优先，远程钩子次选，都没有则 null。
///
/// `autoDispose`：切歌后旧曲目的缓存自动释放。
final AutoDisposeFutureProviderFamily<LyricResult?, Track> lyricsProvider =
    FutureProvider.autoDispose
        .family<LyricResult?, Track>((Ref ref, Track track) async {
  final String? local = await loadLocalLrc(track);
  if (local != null && local.trim().isNotEmpty) {
    return LyricResult(lrc: local); // 本地 .lrc 无译文
  }

  final RemoteLyricsFetcher? fetch = ref.watch(remoteLyricsFetcherProvider);
  if (fetch == null) return null;
  try {
    return await fetch(track);
  } catch (_) {
    return null;
  }
});

/// 解析后的主歌词行（供 [LyricsView] 直接消费）。
final AutoDisposeFutureProviderFamily<List<LyricLine>, Track>
    parsedLyricsProvider = FutureProvider.autoDispose
        .family<List<LyricLine>, Track>((Ref ref, Track track) async {
  final LyricResult? raw = await ref.watch(lyricsProvider(track).future);
  if (raw == null) return const <LyricLine>[];
  return LrcParser.parse(raw.lrc);
});

/// 译文（已解析为歌词行，供激活行下方展示）；无译文时为空列表。
final AutoDisposeFutureProviderFamily<List<LyricLine>, Track>
    lyricsTranslationProvider = FutureProvider.autoDispose
        .family<List<LyricLine>, Track>((Ref ref, Track track) async {
  final LyricResult? raw = await ref.watch(lyricsProvider(track).future);
  if (raw?.translation == null || raw!.translation!.trim().isEmpty) {
    return const <LyricLine>[];
  }
  return LrcParser.parse(raw.translation!);
});

/// 是否显示译文（持久化于 SharedPreferences 键 [kLyricsShowTranslation]）。
final StateNotifierProvider<LyricsShowTranslation, bool>
    lyricsShowTranslationProvider =
    StateNotifierProvider<LyricsShowTranslation, bool>(
  (Ref ref) => LyricsShowTranslation(ref.read(prefsProvider)),
);

class LyricsShowTranslation extends StateNotifier<bool> {
  LyricsShowTranslation(this._prefs)
      : super(_prefs.getBool(kLyricsShowTranslation) ?? false);
  final SharedPreferences _prefs;

  void toggle() {
    state = !state;
    _prefs.setBool(kLyricsShowTranslation, state);
  }
}

/// 用户手动歌词时间偏移（毫秒，持久化于 [kLyricsOffsetMs]），用于校正歌词
/// 整体快/慢几秒；正值 = 歌词延后显示（音频已唱、词还没到 → 调大）。
final StateNotifierProvider<LyricsOffset, int> lyricsOffsetMsProvider =
    StateNotifierProvider<LyricsOffset, int>(
  (Ref ref) => LyricsOffset(ref.read(prefsProvider)),
);

class LyricsOffset extends StateNotifier<int> {
  LyricsOffset(this._prefs) : super(_prefs.getInt(kLyricsOffsetMs) ?? 0);
  final SharedPreferences _prefs;

  static const int _step = 500;

  /// 歌词延后 0.5s（词来晚了）。
  void delay() => _set(state + _step);

  /// 歌词提前 0.5s（词来早了）。
  void advance() => _set(state - _step);

  void _set(int v) {
    state = v.clamp(-10000, 10000);
    _prefs.setInt(kLyricsOffsetMs, state);
  }
}

const String kLyricsShowTranslation = 'lyrics_show_translation';
const String kLyricsOffsetMs = 'lyrics_offset_ms';

// ── cl05：歌词字号 / 风格（Apple Music 风格）─────────────
/// 歌词字号档。
enum LyricSize { small, medium, large }

/// 歌词风格：默认 / Apple Music（当前行更大更亮、其余更暗）。
enum LyricStyle { normal, appleMusic }

const String kLyricsSize = 'lyrics_size';
const String kLyricsStyle = 'lyrics_style';

final StateNotifierProvider<LyricsSizePrefs, LyricSize> lyricsSizeProvider =
    StateNotifierProvider<LyricsSizePrefs, LyricSize>(
  (Ref ref) => LyricsSizePrefs(ref.read(prefsProvider)),
);

class LyricsSizePrefs extends StateNotifier<LyricSize> {
  LyricsSizePrefs(this._prefs)
      : super(switch (_prefs.getString(kLyricsSize)) {
          'small' => LyricSize.small,
          'large' => LyricSize.large,
          _ => LyricSize.medium,
        });
  final SharedPreferences _prefs;

  void set(LyricSize s) {
    state = s;
    _prefs.setString(kLyricsSize, s.name);
  }
}

final StateNotifierProvider<LyricsStylePrefs, LyricStyle> lyricsStyleProvider =
    StateNotifierProvider<LyricsStylePrefs, LyricStyle>(
  (Ref ref) => LyricsStylePrefs(ref.read(prefsProvider)),
);

class LyricsStylePrefs extends StateNotifier<LyricStyle> {
  LyricsStylePrefs(this._prefs)
      : super(_prefs.getString(kLyricsStyle) == 'appleMusic'
            ? LyricStyle.appleMusic
            : LyricStyle.normal);
  final SharedPreferences _prefs;

  void toggle() {
    state = state == LyricStyle.appleMusic
        ? LyricStyle.normal
        : LyricStyle.appleMusic;
    _prefs.setString(kLyricsStyle, state.name);
  }
}

// ════════════════════════════════════════════════════════════════════════
// 三、展示
// ════════════════════════════════════════════════════════════════════════

/// 歌词视图：实时高亮当前行 + 平滑居中滚动。
///
/// - 播放位置来自 `audio_providers` 的 [musicPositionProvider]；
/// - 曲目默认取 [nowPlayingProvider]（也可由调用方显式传入 [track]）；
/// - 无歌词 / 加载失败统一显示「暂无歌词」。
///
/// 高度默认 160；置于 `Flexible` 中时会自动被父级最大高度收敛，不会溢出。
class LyricsView extends ConsumerWidget {
  const LyricsView({super.key, this.track, this.height = 160});

  /// 指定曲目；为 null 时自动跟随 [nowPlayingProvider]。
  final Track? track;

  /// 歌词区高度。
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Track? current = track ?? ref.watch(nowPlayingProvider);
    if (current == null) return _placeholder(context);

    final AsyncValue<List<LyricLine>> lyrics =
        ref.watch(parsedLyricsProvider(current));
    final bool hasTranslation =
        ref.watch(lyricsTranslationProvider(current)).valueOrNull?.isNotEmpty ??
            false;

    // 保证至少能完整显示 2 行歌词（一行激活行 + 上下留白），避免「展开音量后
    // 歌词区被压扁、单行被纵向裁切」的问题（用户反馈）。
    final double h = height < _kLyricRowExtent * 2 + 24
        ? _kLyricRowExtent * 2 + 24
        : height;
    return lyrics.when(
      loading: () => _placeholder(context, text: '歌词加载中…', height: h),
      error: (Object _, StackTrace __) => _placeholder(context, height: h),
      data: (List<LyricLine> lines) => lines.isEmpty
          ? _placeholder(context, height: h)
          : SizedBox(
              height: h,
              child: Stack(
                children: <Widget>[
                  _LyricsScroller(
                    lines: lines,
                    height: h,
                    track: current,
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _LyricsControlsMenu(hasTranslation: hasTranslation),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _placeholder(BuildContext context, {String text = '暂无歌词', double height = 160}) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: context.appColors.textTertiary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// 歌词区右上角设置菜单：译文开关 + 时间偏移微调（±0.5s，持久化）。
class _LyricsControlsMenu extends ConsumerWidget {
  const _LyricsControlsMenu({required this.hasTranslation});
  final bool hasTranslation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors colors = context.appColors;
    final bool showTranslation = ref.watch(lyricsShowTranslationProvider);
    final int offsetMs = ref.watch(lyricsOffsetMsProvider);
    final LyricStyle style = ref.watch(lyricsStyleProvider);
    final LyricSize size = ref.watch(lyricsSizeProvider);

    final List<PopupMenuEntry<String>> items = <PopupMenuEntry<String>>[
      if (hasTranslation)
        PopupMenuItem<String>(
          value: 'translation',
          child: Row(
            children: <Widget>[
              Icon(showTranslation ? Icons.check : Icons.add, size: 16),
              const SizedBox(width: 8),
              const Text('显示译文', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      PopupMenuItem<String>(
        value: 'delay',
        child: const Text('歌词延后 +0.5s', style: TextStyle(fontSize: 13)),
      ),
      PopupMenuItem<String>(
        value: 'advance',
        child: const Text('歌词提前 −0.5s', style: TextStyle(fontSize: 13)),
      ),
      if (offsetMs != 0)
        PopupMenuItem<String>(
          value: 'offset',
          enabled: false,
          child: Text(
            '当前偏移 ${(offsetMs / 1000).toStringAsFixed(1)}s',
            style: TextStyle(fontSize: 12, color: colors.textTertiary),
          ),
        ),
      // cl05：歌词风格（默认 / Apple Music）+ 字号。
      PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'style',
        child: Row(
          children: <Widget>[
            Icon(
              style == LyricStyle.appleMusic
                  ? Icons.music_note_rounded
                  : Icons.notes,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              style == LyricStyle.appleMusic ? '风格：Apple Music' : '风格：默认',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'size_small',
        child: Row(
          children: <Widget>[
            Icon(
              size == LyricSize.small ? Icons.check : Icons.text_fields,
              size: 16,
            ),
            const SizedBox(width: 8),
            const Text('字号：小', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'size_medium',
        child: Row(
          children: <Widget>[
            Icon(
              size == LyricSize.medium ? Icons.check : Icons.text_fields,
              size: 16,
            ),
            const SizedBox(width: 8),
            const Text('字号：中', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'size_large',
        child: Row(
          children: <Widget>[
            Icon(
              size == LyricSize.large ? Icons.check : Icons.text_fields,
              size: 16,
            ),
            const SizedBox(width: 8),
            const Text('字号：大', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ];

    return PopupMenuButton<String>(
      icon: Icon(Icons.tune, size: 18, color: colors.textTertiary),
      padding: EdgeInsets.zero,
      tooltip: '歌词设置',
      onSelected: (String v) {
        if (v == 'translation') {
          ref.read(lyricsShowTranslationProvider.notifier).toggle();
        } else if (v == 'delay') {
          ref.read(lyricsOffsetMsProvider.notifier).delay();
        } else if (v == 'advance') {
          ref.read(lyricsOffsetMsProvider.notifier).advance();
        } else if (v == 'style') {
          ref.read(lyricsStyleProvider.notifier).toggle();
        } else if (v == 'size_small') {
          ref.read(lyricsSizeProvider.notifier).set(LyricSize.small);
        } else if (v == 'size_medium') {
          ref.read(lyricsSizeProvider.notifier).set(LyricSize.medium);
        } else if (v == 'size_large') {
          ref.read(lyricsSizeProvider.notifier).set(LyricSize.large);
        }
      },
      itemBuilder: (_) => items,
    );
  }
}

/// 歌词滚动体：固定行高 + 二分定位当前行 + 居中动画。
///
/// 固定 [_extent] 行高让「当前行居中」可纯数学求解，无需测量子项，
/// 因此滚动不掉帧、也不依赖额外的第三方列表库。
class _LyricsScroller extends ConsumerStatefulWidget {
  const _LyricsScroller({
    required this.lines,
    required this.height,
    required this.track,
  });

  final List<LyricLine> lines;
  final double height;
  final Track track;

  @override
  ConsumerState<_LyricsScroller> createState() => _LyricsScrollerState();
}

class _LyricsScrollerState extends ConsumerState<_LyricsScroller> {
  /// 单行占位高度（容纳两行文本：15sp × 1.25 × 2 ≈ 37.5）。
  static const double _extent = _kLyricRowExtent;

  final ScrollController _ctrl = ScrollController();

  /// 当前高亮行下标，-1 = 尚未进入第一句。
  int _index = -1;

  @override
  void didUpdateWidget(covariant _LyricsScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换歌：重置高亮与滚动位置
    if (!identical(oldWidget.lines, widget.lines)) {
      _index = -1;
      if (_ctrl.hasClients) _ctrl.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 二分查找 `time <= pos` 的最后一行。
  int _locate(Duration pos) {
    final List<LyricLine> lines = widget.lines;
    int lo = 0;
    int hi = lines.length - 1;
    int found = -1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      if (lines[mid].$1 <= pos) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// 把第 [index] 行滚到视口中央（行高 [extent] 随字号/风格动态变化）。
  void _centerOn(int index, double extent) {
    if (!_ctrl.hasClients) return;
    final double target =
        (index * extent).clamp(0.0, _ctrl.position.maxScrollExtent);
    if ((_ctrl.offset - target).abs() < 0.5) return;
    _ctrl.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showTranslation = ref.watch(lyricsShowTranslationProvider);
    final int offsetMs = ref.watch(lyricsOffsetMsProvider);
    // cl05：歌词字号 / 风格（Apple Music）驱动行高与高亮样式。
    final LyricSize size = ref.watch(lyricsSizeProvider);
    final LyricStyle style = ref.watch(lyricsStyleProvider);
    final List<LyricLine> transLines =
        ref.watch(lyricsTranslationProvider(widget.track)).valueOrNull ??
            const <LyricLine>[];

    final Duration pos =
        ref.watch(musicPositionProvider).valueOrNull ?? Duration.zero;
    // 用户手动时间偏移：歌词整体快/慢时校正。
    final Duration effPos = pos + Duration(milliseconds: offsetMs);

    final double scale = switch (size) {
      LyricSize.small => 0.85,
      LyricSize.medium => 1.0,
      LyricSize.large => 1.2,
    };
    final double extent =
        _extent * scale * (style == LyricStyle.appleMusic ? 1.25 : 1.0);

    final int index = _locate(effPos);
    if (index != _index) {
      _index = index;
      if (index >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _centerOn(index, extent);
        });
      }
    }

    final double pad = ((widget.height - extent) / 2).clamp(0.0, 1000.0);
    final AppThemeColors colors = context.appColors;

    return ListView.builder(
      controller: _ctrl,
      itemExtent: extent,
      padding: EdgeInsets.symmetric(vertical: pad),
      itemCount: widget.lines.length,
      itemBuilder: (BuildContext context, int i) {
        final bool active = i == index;
        final String trans = (active && showTranslation)
            ? _translationFor(transLines, widget.lines[i].$1)
            : '';
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            // Apple Music 风格「跳动回弹」：激活行 scale 1.0→1.06→1.0，
            // 弹性曲线模拟轻快弹跳；非激活行保持 1.0（无动画）。
            child: AnimatedScale(
              scale: active ? 1.06 : 1.0,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              style: TextStyle(
                color: active
                    ? colors.accent
                    : (style == LyricStyle.appleMusic
                        ? colors.textTertiary.withValues(alpha: 0.55)
                        : colors.textTertiary),
                fontSize: active
                    ? (style == LyricStyle.appleMusic ? 19.0 : 15.0) * scale
                    : 13.0 * scale,
                fontWeight: active
                    ? (style == LyricStyle.appleMusic
                        ? FontWeight.w700
                        : FontWeight.w600)
                    : FontWeight.w400,
                height: 1.25,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    widget.lines[i].$2,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  if (trans.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        trans,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
              ), // AnimatedDefaultTextStyle
            ), // AnimatedScale
          ),
        );
      },
    );
  }

  /// 取激活行对应的译文（取时间不超过该句主词时间的最后一行）。
  String _translationFor(List<LyricLine> trans, Duration mainTime) {
    if (trans.isEmpty) return '';
    int lo = 0;
    int hi = trans.length - 1;
    int found = -1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      if (trans[mid].$1 <= mainTime) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found >= 0 ? trans[found].$2 : '';
  }
}
