import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_theme_colors.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';

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

/// 远程歌词获取钩子签名：曲目 -> `.lrc` 文本（无结果返回 null）。
typedef RemoteLyricsFetcher = Future<String?> Function(Track track);

/// 远程歌词钩子（**预留**）。
///
/// 默认 `null` = 未接入任何在线歌词源。后续接网易云 API 时，只需在
/// `ProviderScope.overrides` 或此处返回一个 [RemoteLyricsFetcher] 实现，
/// 歌词界面无需任何改动。
final Provider<RemoteLyricsFetcher?> remoteLyricsFetcherProvider =
    Provider<RemoteLyricsFetcher?>((Ref ref) => null);

/// 读取与曲目同目录、同名的 `.lrc` 文件。
///
/// 仅对**本地文件路径**生效；网络流 / 电台 / `content://` 一律返回 null。
Future<String?> loadLocalLrc(Track track) async {
  final String uri = track.uri;
  if (uri.isEmpty) return null;
  // 非本地文件路径（http 流、Android 媒体库 content uri、asset）跳过
  if (uri.startsWith('http') ||
      uri.startsWith('content://') ||
      uri.startsWith('asset')) {
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

/// 歌词原文（`.lrc` 文本）：本地优先，远程钩子次选，都没有则 null。
///
/// `autoDispose`：切歌后旧曲目的缓存自动释放。
final AutoDisposeFutureProviderFamily<String?, Track> lyricsProvider =
    FutureProvider.autoDispose
        .family<String?, Track>((Ref ref, Track track) async {
  final String? local = await loadLocalLrc(track);
  if (local != null && local.trim().isNotEmpty) return local;

  final RemoteLyricsFetcher? fetch = ref.watch(remoteLyricsFetcherProvider);
  if (fetch == null) return null;
  try {
    return await fetch(track);
  } catch (_) {
    return null;
  }
});

/// 解析后的歌词行（供 [LyricsView] 直接消费）。
final AutoDisposeFutureProviderFamily<List<LyricLine>, Track>
    parsedLyricsProvider = FutureProvider.autoDispose
        .family<List<LyricLine>, Track>((Ref ref, Track track) async {
  final String? raw = await ref.watch(lyricsProvider(track).future);
  if (raw == null) return const <LyricLine>[];
  return LrcParser.parse(raw);
});

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

    return lyrics.when(
      loading: () => _placeholder(context, text: '歌词加载中…'),
      error: (Object _, StackTrace __) => _placeholder(context),
      data: (List<LyricLine> lines) => lines.isEmpty
          ? _placeholder(context)
          : SizedBox(
              height: height,
              child: _LyricsScroller(lines: lines, height: height),
            ),
    );
  }

  Widget _placeholder(BuildContext context, {String text = '暂无歌词'}) {
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

/// 歌词滚动体：固定行高 + 二分定位当前行 + 居中动画。
///
/// 固定 [_extent] 行高让「当前行居中」可纯数学求解，无需测量子项，
/// 因此滚动不掉帧、也不依赖额外的第三方列表库。
class _LyricsScroller extends ConsumerStatefulWidget {
  const _LyricsScroller({required this.lines, required this.height});

  final List<LyricLine> lines;
  final double height;

  @override
  ConsumerState<_LyricsScroller> createState() => _LyricsScrollerState();
}

class _LyricsScrollerState extends ConsumerState<_LyricsScroller> {
  /// 单行占位高度（容纳两行文本：15sp × 1.25 × 2 ≈ 37.5）。
  static const double _extent = 40;

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

  /// 把第 [index] 行滚到视口中央。
  ///
  /// 列表上下各留了 `(height - _extent) / 2` 的留白，
  /// 因此目标偏移恰为 `index * _extent`。
  void _centerOn(int index) {
    if (!_ctrl.hasClients) return;
    final double target =
        (index * _extent).clamp(0.0, _ctrl.position.maxScrollExtent);
    if ((_ctrl.offset - target).abs() < 0.5) return;
    _ctrl.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Duration pos =
        ref.watch(musicPositionProvider).valueOrNull ?? Duration.zero;

    final int index = _locate(pos);
    if (index != _index) {
      _index = index;
      if (index >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _centerOn(index);
        });
      }
    }

    final double pad = ((widget.height - _extent) / 2).clamp(0.0, 1000.0);
    final AppThemeColors colors = context.appColors;

    return ListView.builder(
      controller: _ctrl,
      itemExtent: _extent,
      padding: EdgeInsets.symmetric(vertical: pad),
      itemCount: widget.lines.length,
      itemBuilder: (BuildContext context, int i) {
        final bool active = i == index;
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              style: TextStyle(
                color: active ? colors.accent : colors.textTertiary,
                fontSize: active ? 15 : 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                height: 1.25,
              ),
              child: Text(
                widget.lines[i].$2,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}
