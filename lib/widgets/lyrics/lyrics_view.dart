import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/sources/netease_provider.dart';
import '../../providers/storage/storage_providers.dart';
import '../../services/audio/sources/netease/netease_api.dart';
import '../../services/audio/sources/netease/netease_source.dart';

/// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
/// 姝岃瘝妯″潡锛堣В鏋?+ 鏁版嵁婧?+ 灞曠ず锛?
/// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
///
/// 鐙珛浜庢挱鏀惧櫒瀹炵幇锛歔UnifiedPlayer] 鍙€氳繃鍙€夊弬鏁?`lyricsSlot` 鎵胯浇鏈粍浠讹紝
/// 涓嶆劅鐭ユ瓕璇嶇殑鏉ユ簮涓庤В鏋愮粏鑺傘€?
///
/// ### 鏁版嵁鏉ユ簮浼樺厛绾?
/// 1. **鏈湴**锛氫笌褰撳墠鏇茬洰**鍚岀洰褰曘€佸悓鍚?*鐨?`.lrc` 鏂囦欢锛堟湰鍦伴煶涔愬満鏅級锛?
/// 2. **杩滅▼**锛歔remoteLyricsFetcherProvider] 閽╁瓙锛堥鐣欑綉鏄撲簯绛夊湪绾挎瓕璇嶆簮锛?
///    褰撳墠榛樿鏈帴鍏ワ紝杩斿洖 `null`锛夈€?
///
/// ### 绾跨▼
/// 鏂囦欢 IO 涓庤В鏋愰兘鍦?[FutureProvider] 鐨勫紓姝ラ摼璺噷瀹屾垚锛屼笉鍦?`build` 涓墽琛岋紝
/// 鍥犳涓嶄細闃诲 UI 甯с€?

/// 涓€琛屾瓕璇嶏細`(鏃堕棿杞? 鏂囨湰)`銆?
typedef LyricLine = (Duration time, String text);

/// 姝岃瘝鍗曡鍗犱綅楂樺害锛堝绾充袱琛?15sp 鏂囨湰锛?5 脳 1.25 脳 2 鈮?37.5锛岀暀浣欓噺鍙?40锛夈€?
/// 鍚屾椂浣滀负銆屽崟琛屽畬鏁存樉绀恒€嶇殑鏈€灏忛珮搴﹀熀鍑嗭紙瑙?[LyricsView]锛夈€?
const double _kLyricRowExtent = 40.0;

// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
// 涓€銆佽В鏋愶細鏍囧噯 .lrc
// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

/// 鏍囧噯 `.lrc` 姝岃瘝瑙ｆ瀽鍣ㄣ€?
///
/// 鏀寔锛?
/// - `[mm:ss]` / `[mm:ss.xx]` / `[mm:ss.xxx]` 涓夌鏃堕棿绮惧害锛?
/// - 涓€琛屽鏃堕棿杞达紙`[00:12.30][01:20.10]鍚屼竴鍙ユ瓕璇峘锛夛紱
/// - `[offset:卤ms]` 鍏ㄥ眬鏃堕棿琛ュ伩锛堟鍊艰〃绀烘瓕璇嶆暣浣撴彁鍓嶏級锛?
/// - 鍏冧俊鎭锛坄[ti:]` `[ar:]` `[al:]` `[by:]` 绛夛級鑷姩蹇界暐銆?
///
/// 瀹归敊锛氫换浣曟棤娉曡瘑鍒殑琛岋紙缂烘椂闂磋酱 / 鏃堕棿鏍煎紡闈炴硶 / 绾枃鏈級閮借闈欓粯璺宠繃锛?
/// 涓嶆姏寮傚父锛屼繚璇佸潖姝岃瘝鏂囦欢涓嶄細璁╃晫闈㈠穿婧冦€?
abstract final class LrcParser {
  /// 鏃堕棿杞存爣绛撅細鍒?绉?.姣)锛屾绉掍綅 1~3 浣嶃€?
  static final RegExp _timeTag =
      RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  /// 鏃堕棿琛ュ伩鏍囩锛屽 `[offset:-500]`銆?
  static final RegExp _offsetTag =
      RegExp(r'^\[offset:\s*([+-]?\d{1,7})\s*\]$', caseSensitive: false);

  /// 瑙ｆ瀽鏁翠唤 `.lrc` 鏂囨湰锛岃繑鍥炴寜鏃堕棿鍗囧簭鎺掑垪鐨勬瓕璇嶈銆?
  ///
  /// 杈撳叆涓虹┖ / 鍏ㄦ槸鍏冧俊鎭椂杩斿洖绌哄垪琛紙鐢?[LyricsView] 娓叉煋銆屾殏鏃犳瓕璇嶃€嶏級銆?
  static List<LyricLine> parse(String raw) {
    if (raw.trim().isEmpty) return const <LyricLine>[];

    final List<LyricLine> lines = <LyricLine>[];
    int offsetMs = 0;

    for (final String rawLine in const LineSplitter().convert(raw)) {
      final String line = rawLine.trim();
      if (line.isEmpty) continue;

      // 鈶?鏃堕棿琛ュ伩鏍囩
      final RegExpMatch? off = _offsetTag.firstMatch(line);
      if (off != null) {
        offsetMs = int.tryParse(off.group(1)!) ?? 0;
        continue;
      }

      // 鈶?杩炵画鏃堕棿杞村墠缂€锛堜竴琛屽彲鎸傚涓椂闂寸偣锛?
      final List<Duration> stamps = <Duration>[];
      int cursor = 0;
      while (cursor < line.length) {
        // 鍏佽鏃堕棿杞翠箣闂村瓨鍦ㄧ┖鏍硷細[00:01.00] [00:05.00]鏂囨湰
        while (cursor < line.length && line[cursor] == ' ') {
          cursor++;
        }
        final Match? m = _timeTag.matchAsPrefix(line, cursor);
        if (m == null) break;
        final Duration? d = _toDuration(m);
        if (d != null) stamps.add(d);
        cursor = m.end;
      }
      // 鏃犳椂闂磋酱 -> 鍏冧俊鎭垨鍨冨溇琛岋紝璺宠繃锛堝閿欙級
      if (stamps.isEmpty) continue;

      final String text = line.substring(cursor).trim();
      for (final Duration d in stamps) {
        lines.add((d, text));
      }
    }

    // 鈶?搴旂敤鍏ㄥ眬琛ュ伩锛堟 offset = 鎻愬墠鏄剧ず锛夊悗鎺掑簭
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

  /// 鏃堕棿杞存鍒欏懡涓?-> [Duration]锛涢潪娉曪紙濡傜 鈮?60锛夎繑鍥?null銆?
  static Duration? _toDuration(Match m) {
    final int? mm = int.tryParse(m.group(1) ?? '');
    final int? ss = int.tryParse(m.group(2) ?? '');
    if (mm == null || ss == null || ss > 59) return null;

    // 灏忔暟浣嶏細1 浣?= 100ms锛? 浣?= 10ms锛堝帢绉掞紝鏈€甯歌锛夛紝3 浣?= 1ms
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

// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
// 浜屻€佹暟鎹簮锛氭湰鍦?.lrc锛堝凡瀹炵幇锛?+ 杩滅▼閽╁瓙锛堥鐣欙級
// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

/// 杩滅▼姝岃瘝鑾峰彇閽╁瓙绛惧悕锛氭洸鐩?-> 姝岃瘝缁撴灉锛堜富璇?+ 鍙€夎瘧鏂囷紱鏃犵粨鏋滆繑鍥?null锛夈€?
typedef RemoteLyricsFetcher = Future<LyricResult?> Function(Track track);

/// 姝岃瘝纾佺洏缂撳瓨锛歴ongId -> [LyricResult]锛岃惤鐩?`<搴旂敤鏂囨。>/lyrics/<id>.json`锛?
/// 璺ㄤ細璇濆鐢紝绂荤嚎涔熻兘鏄剧ず锛堥娆¤仈缃戞媺鍙栧悗闀挎湡鏈夋晥锛夈€?
///
/// 缃戠粶/IO 寮傚父涓€寰嬮潤榛樺悶鎺夛紙鍥為€€鍒板唴瀛樻垨鍦ㄧ嚎锛夛紝涓嶈鍙栬瘝閾捐矾宕╂簝銆?
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
      // 缂撳瓨鍐欏叆澶辫触涓嶈嚧鍛?
    }
  }
}

/// 姝岃瘝缂撳瓨鐩綍锛堝簲鐢ㄦ枃妗ｇ洰褰曪紱鍙栦笉鍒版椂閫€鍖栦负绯荤粺涓存椂鐩綍锛屼粎鍐呭瓨鍏滃簳锛夈€?
final FutureProvider<LyricsCache> lyricsCacheProvider =
    FutureProvider<LyricsCache>((Ref ref) async {
  try {
    final Directory docs = await appDataDir();
    return LyricsCache(docs);
  } catch (_) {
    return LyricsCache(Directory.systemTemp);
  }
});

/// 杩滅▼姝岃瘝閽╁瓙锛?*棰勮缃戞槗浜戝疄鐜?*锛夈€?
///
/// 榛樿鍙帴缃戞槗浜戯細鏇茬洰鑻ユ槸 `netease://song/<id>` 鍗犱綅绗︼紙鎴栧叾 `extras`
/// 甯?`songId`锛夛紝灏辫蛋 [NeteaseApi.getLyrics] 鎷夊彇锛涘厛鏌ョ鐩樼紦瀛橈紝鏈懡涓啀
/// 鑱旂綉骞跺洖鍐欍€傚叾瀹冩簮杩斿洖 null锛岀敱涓婃父 [lyricsProvider] 闄嶇骇涓恒€屾殏鏃犳瓕璇嶃€嶃€?
/// 鍚庣画鑻ヨ鎺ュ叾瀹冨湪绾挎簮锛屽彲鍦?`ProviderScope.overrides` 瑕嗙洊鏈?provider锛?
/// 姝岃瘝鐣岄潰鏃犻渶鏀瑰姩銆?
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

/// 璇诲彇涓庢洸鐩悓鐩綍銆佸悓鍚嶇殑 `.lrc` 鏂囦欢銆?
///
/// 浠呭**鏈湴鏂囦欢璺緞**鐢熸晥锛涚綉缁滄祦 / 鐢靛彴 / `content://` 涓€寰嬭繑鍥?null銆?
Future<String?> loadLocalLrc(Track track) async {
  final String uri = track.uri;
  if (uri.isEmpty) return null;
  // 闈炴湰鍦版枃浠惰矾寰勶紙http 娴併€丄ndroid 濯掍綋搴?content uri銆乤sset銆?
  // 缃戞槗浜?netease:// 鍗犱綅绗︾瓑锛夎烦杩囷紝浜ょ粰杩滅▼閽╁瓙澶勭悊
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
      // 鏉冮檺 / IO 寮傚父锛氳浣滄棤姝岃瘝锛屼笉鎵撴柇鎾斁鐣岄潰
    }
  }
  return null;
}

/// 璇诲彇姝岃瘝鏂囨湰锛氫紭鍏?UTF-8锛屽け璐ユ椂瀹归敊瑙ｇ爜锛堜笉鍥犵紪鐮侀棶棰樻姏寮傚父锛夈€?
///
/// TODO(姝岃瘝): 鍥戒骇姝岃瘝绔欎笅杞界殑 `.lrc` 甯歌 GBK 缂栫爜锛屽綋鍓嶅閿欒В鐮佷細鍑虹幇涔辩爜锛?
/// 鍚庣画鍙紩鍏?charset 妫€娴嬶紙闇€鏂板渚濊禆锛屾殏涓嶆敼 pubspec锛夈€?
Future<String> _readText(File f) async {
  try {
    return await f.readAsString();
  } on FormatException {
    return utf8.decode(await f.readAsBytes(), allowMalformed: true);
  }
}

/// 姝岃瘝缁撴灉锛堜富璇?+ 鍙€夎瘧鏂囷級锛氭湰鍦颁紭鍏堬紝杩滅▼閽╁瓙娆￠€夛紝閮芥病鏈夊垯 null銆?
///
/// `autoDispose`锛氬垏姝屽悗鏃ф洸鐩殑缂撳瓨鑷姩閲婃斁銆?
final AutoDisposeFutureProviderFamily<LyricResult?, Track> lyricsProvider =
    FutureProvider.autoDispose
        .family<LyricResult?, Track>((Ref ref, Track track) async {
  final String? local = await loadLocalLrc(track);
  if (local != null && local.trim().isNotEmpty) {
    return LyricResult(lrc: local); // 鏈湴 .lrc 鏃犺瘧鏂?
  }

  final RemoteLyricsFetcher? fetch = ref.watch(remoteLyricsFetcherProvider);
  if (fetch == null) return null;
  try {
    return await fetch(track);
  } catch (_) {
    return null;
  }
});

/// 瑙ｆ瀽鍚庣殑涓绘瓕璇嶈锛堜緵 [LyricsView] 鐩存帴娑堣垂锛夈€?
final AutoDisposeFutureProviderFamily<List<LyricLine>, Track>
    parsedLyricsProvider = FutureProvider.autoDispose
        .family<List<LyricLine>, Track>((Ref ref, Track track) async {
  final LyricResult? raw = await ref.watch(lyricsProvider(track).future);
  if (raw == null) return const <LyricLine>[];
  return LrcParser.parse(raw.lrc);
});

/// 璇戞枃锛堝凡瑙ｆ瀽涓烘瓕璇嶈锛屼緵婵€娲昏涓嬫柟灞曠ず锛夛紱鏃犺瘧鏂囨椂涓虹┖鍒楄〃銆?
final AutoDisposeFutureProviderFamily<List<LyricLine>, Track>
    lyricsTranslationProvider = FutureProvider.autoDispose
        .family<List<LyricLine>, Track>((Ref ref, Track track) async {
  final LyricResult? raw = await ref.watch(lyricsProvider(track).future);
  if (raw?.translation == null || raw!.translation!.trim().isEmpty) {
    return const <LyricLine>[];
  }
  return LrcParser.parse(raw.translation!);
});

/// 鏄惁鏄剧ず璇戞枃锛堟寔涔呭寲浜?SharedPreferences 閿?[kLyricsShowTranslation]锛夈€?
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

/// 鐢ㄦ埛鎵嬪姩姝岃瘝鏃堕棿鍋忕Щ锛堟绉掞紝鎸佷箙鍖栦簬 [kLyricsOffsetMs]锛夛紝鐢ㄤ簬鏍℃姝岃瘝
/// 鏁翠綋蹇?鎱㈠嚑绉掞紱姝ｅ€?= 姝岃瘝寤跺悗鏄剧ず锛堥煶棰戝凡鍞便€佽瘝杩樻病鍒?鈫?璋冨ぇ锛夈€?
final StateNotifierProvider<LyricsOffset, int> lyricsOffsetMsProvider =
    StateNotifierProvider<LyricsOffset, int>(
  (Ref ref) => LyricsOffset(ref.read(prefsProvider)),
);

class LyricsOffset extends StateNotifier<int> {
  LyricsOffset(this._prefs) : super(_prefs.getInt(kLyricsOffsetMs) ?? 0);
  final SharedPreferences _prefs;

  static const int _step = 500;

  /// 姝岃瘝寤跺悗 0.5s锛堣瘝鏉ユ櫄浜嗭級銆?
  void delay() => _set(state + _step);

  /// 姝岃瘝鎻愬墠 0.5s锛堣瘝鏉ユ棭浜嗭級銆?
  void advance() => _set(state - _step);

  void _set(int v) {
    state = v.clamp(-10000, 10000);
    _prefs.setInt(kLyricsOffsetMs, state);
  }
}

const String kLyricsShowTranslation = 'lyrics_show_translation';
const String kLyricsOffsetMs = 'lyrics_offset_ms';

// 鈹€鈹€ cl05锛氭瓕璇嶅瓧鍙?/ 椋庢牸锛圓pple Music 椋庢牸锛夆攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
/// 姝岃瘝瀛楀彿妗ｃ€?
enum LyricSize { small, medium, large }

/// 姝岃瘝椋庢牸锛氶粯璁?/ Apple Music锛堝綋鍓嶈鏇村ぇ鏇翠寒銆佸叾浣欐洿鏆楋級銆?
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
  // R32 浜?2锛氭墍鏈夋瓕璇嶉粯璁ら噰鐢?Apple Music 椋庢牸锛堜粎鏄惧紡閫夎繃銆岄粯璁ゃ€嶆墠鍥為€€锛夈€?
  LyricsStylePrefs(this._prefs)
      : super(_prefs.getString(kLyricsStyle) == 'normal'
            ? LyricStyle.normal
            : LyricStyle.appleMusic);
  final SharedPreferences _prefs;

  void toggle() {
    state = state == LyricStyle.appleMusic
        ? LyricStyle.normal
        : LyricStyle.appleMusic;
    _prefs.setString(kLyricsStyle, state.name);
  }
}

// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
// 涓夈€佸睍绀?
// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

/// 姝岃瘝瑙嗗浘锛氬疄鏃堕珮浜綋鍓嶈 + 骞虫粦灞呬腑婊氬姩銆?
///
/// - 鎾斁浣嶇疆鏉ヨ嚜 `audio_providers` 鐨?[musicPositionProvider]锛?
/// - 鏇茬洰榛樿鍙?[nowPlayingProvider]锛堜篃鍙敱璋冪敤鏂规樉寮忎紶鍏?[track]锛夛紱
/// - 鏃犳瓕璇?/ 鍔犺浇澶辫触缁熶竴鏄剧ず銆屾殏鏃犳瓕璇嶃€嶃€?
///
/// 楂樺害榛樿 160锛涚疆浜?`Flexible` 涓椂浼氳嚜鍔ㄨ鐖剁骇鏈€澶ч珮搴︽敹鏁涳紝涓嶄細婧㈠嚭銆?
class LyricsView extends ConsumerWidget {
  const LyricsView({super.key, this.track, this.height = 160});

  /// 鎸囧畾鏇茬洰锛涗负 null 鏃惰嚜鍔ㄨ窡闅?[nowPlayingProvider]銆?
  final Track? track;

  /// 姝岃瘝鍖洪珮搴︺€?
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

    // 淇濊瘉鑷冲皯鑳藉畬鏁存樉绀?2 琛屾瓕璇嶏紙涓€琛屾縺娲昏 + 涓婁笅鐣欑櫧锛夛紝閬垮厤銆屽睍寮€闊抽噺鍚?
    // 姝岃瘝鍖鸿鍘嬫墎銆佸崟琛岃绾靛悜瑁佸垏銆嶇殑闂锛堢敤鎴峰弽棣堬級銆?
    final double h = height < _kLyricRowExtent * 2 + 24
        ? _kLyricRowExtent * 2 + 24
        : height;
    return lyrics.when(
      loading: () => _placeholder(context, text: '姝岃瘝鍔犺浇涓€?, height: h),
      error: (Object _, StackTrace __) => _placeholder(context, height: h),
      data: (List<LyricLine> lines) => lines.isEmpty
          ? _placeholder(context, height: h)
          : SizedBox(
              height: h,
              child: Stack(
                children: <Widget>[
                  // R32 浜?2锛欰pple Music 椋庢牸鈥斺€旀瓕璇嶄笂涓嬭竟缂樻笎鍙樻贰鍑猴紝
                  // 涓庤儗鏅瀺鍚堬紙闈炴暣琛岀獊鍏€鎴柇锛夛紱婊氬姩鍒拌竟缂樼殑姝岃瘝鑷劧娓愰殣銆?
                  ShaderMask(
                    shaderCallback: (Rect bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.transparent,
                        Colors.black,
                        Colors.black,
                        Colors.transparent,
                      ],
                      stops: <double>[0, 0.12, 0.88, 1],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: _LyricsScroller(
                      lines: lines,
                      height: h,
                      track: current,
                    ),
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

  Widget _placeholder(BuildContext context, {String text = '鏆傛棤姝岃瘝', double height = 160}) {
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

/// 姝岃瘝鍖哄彸涓婅璁剧疆鑿滃崟锛氳瘧鏂囧紑鍏?+ 鏃堕棿鍋忕Щ寰皟锛埪?.5s锛屾寔涔呭寲锛夈€?
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
              const Text('鏄剧ず璇戞枃', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      PopupMenuItem<String>(
        value: 'delay',
        child: const Text('姝岃瘝寤跺悗 +0.5s', style: TextStyle(fontSize: 13)),
      ),
      PopupMenuItem<String>(
        value: 'advance',
        child: const Text('姝岃瘝鎻愬墠 鈭?.5s', style: TextStyle(fontSize: 13)),
      ),
      if (offsetMs != 0)
        PopupMenuItem<String>(
          value: 'offset',
          enabled: false,
          child: Text(
            '褰撳墠鍋忕Щ ${(offsetMs / 1000).toStringAsFixed(1)}s',
            style: TextStyle(fontSize: 12, color: colors.textTertiary),
          ),
        ),
      // cl05锛氭瓕璇嶉鏍硷紙榛樿 / Apple Music锛? 瀛楀彿銆?
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
              style == LyricStyle.appleMusic ? '椋庢牸锛欰pple Music' : '椋庢牸锛氶粯璁?,
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
            const Text('瀛楀彿锛氬皬', style: TextStyle(fontSize: 13)),
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
            const Text('瀛楀彿锛氫腑', style: TextStyle(fontSize: 13)),
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
            const Text('瀛楀彿锛氬ぇ', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ];

    return PopupMenuButton<String>(
      icon: Icon(Icons.tune, size: 18, color: colors.textTertiary),
      padding: EdgeInsets.zero,
      tooltip: '姝岃瘝璁剧疆',
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

/// 姝岃瘝婊氬姩浣擄細鍥哄畾琛岄珮 + 浜屽垎瀹氫綅褰撳墠琛?+ 灞呬腑鍔ㄧ敾銆?
///
/// 鍥哄畾 [_extent] 琛岄珮璁┿€屽綋鍓嶈灞呬腑銆嶅彲绾暟瀛︽眰瑙ｏ紝鏃犻渶娴嬮噺瀛愰」锛?
/// 鍥犳婊氬姩涓嶆帀甯с€佷篃涓嶄緷璧栭澶栫殑绗笁鏂瑰垪琛ㄥ簱銆?
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
  /// 鍗曡鍗犱綅楂樺害锛堝绾充袱琛屾枃鏈細15sp 脳 1.25 脳 2 鈮?37.5锛夈€?
  static const double _extent = _kLyricRowExtent;

  final ScrollController _ctrl = ScrollController();

  /// 褰撳墠楂樹寒琛屼笅鏍囷紝-1 = 灏氭湭杩涘叆绗竴鍙ャ€?
  int _index = -1;

  @override
  void didUpdateWidget(covariant _LyricsScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 鎹㈡瓕锛氶噸缃珮浜笌婊氬姩浣嶇疆
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

  /// 浜屽垎鏌ユ壘 `time <= pos` 鐨勬渶鍚庝竴琛屻€?
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

  /// 鎶婄 [index] 琛屾粴鍒拌鍙ｄ腑澶紙琛岄珮 [extent] 闅忓瓧鍙?椋庢牸鍔ㄦ€佸彉鍖栵級銆?
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
    // cl05锛氭瓕璇嶅瓧鍙?/ 椋庢牸锛圓pple Music锛夐┍鍔ㄨ楂樹笌楂樹寒鏍峰紡銆?
    final LyricSize size = ref.watch(lyricsSizeProvider);
    final LyricStyle style = ref.watch(lyricsStyleProvider);
    final List<LyricLine> transLines =
        ref.watch(lyricsTranslationProvider(widget.track)).valueOrNull ??
            const <LyricLine>[];

    final Duration pos =
        ref.watch(musicPositionProvider).valueOrNull ?? Duration.zero;
    // 鐢ㄦ埛鎵嬪姩鏃堕棿鍋忕Щ锛氭瓕璇嶆暣浣撳揩/鎱㈡椂鏍℃銆?
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
            // Apple Music 椋庢牸銆岃烦鍔ㄥ洖寮广€嶏細婵€娲昏 scale 1.0鈫?.06鈫?.0锛?
            // 寮规€ф洸绾挎ā鎷熻交蹇脊璺筹紱闈炴縺娲昏淇濇寔 1.0锛堟棤鍔ㄧ敾锛夈€?
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
                  SelectableText(
                    widget.lines[i].$2,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                  if (trans.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: SelectableText(
                        trans,
                        maxLines: 1,
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

  /// 鍙栨縺娲昏瀵瑰簲鐨勮瘧鏂囷紙鍙栨椂闂翠笉瓒呰繃璇ュ彞涓昏瘝鏃堕棿鐨勬渶鍚庝竴琛岋級銆?
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

