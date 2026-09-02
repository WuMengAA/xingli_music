import 'dart:io';

import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import '../../core/paths.dart';

import '../../models/track.dart';
import '../log_service.dart';

/// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
/// 鏈湴闊充箰鎵弿鍣細閫氳繃绯荤粺濯掍綋搴撹鍙栫湡瀹炲厓鏁版嵁锛坥n_audio_query锛夈€?
/// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
///
/// 涓昏矾寰勶細`on_audio_query` 鏌ヨ绯荤粺 MediaStore锛堝甫鍏冩暟鎹?/ 灏侀潰锛夈€?
///
/// **Fallback 璺緞**锛堟柊澧烇級锛氬綋绯荤粺濯掍綋搴撲笉鍙敤鏃讹紙瑁佸壀 ROM / Wear OS
/// GSI 缂哄皯 `READ_MEDIA_AUDIO` 鏉冮檺瀹氫箟銆乣on_audio_query` 鎶?`PlatformException`
/// Unknown permission銆佹垨鏉冮檺璇锋眰琚嫆锛夛紝鍥為€€鍒?**鐩綍閬嶅巻** 鐩存帴璇?
/// `/sdcard/Music/`銆乣/sdcard/Download/` 涓嬬殑 `.mp3/.flac/.m4a/.wav/.ogg`锛?
/// 淇濊瘉鑰佽澶?绮剧畝绯荤粺涔熻兘鎷垮埌鏈湴鏇茬洰锛堢壓鐗插厓鏁版嵁绮惧害鎹㈠彇鍙敤鎬э級銆?
///
/// 妗岄潰 / 鏃犲獟浣撳簱骞冲彴鐩存帴杩斿洖绌猴紝鐢辫仛鍚堝眰鍥為€€鍒板叾瀹冮煶婧愩€?
class LocalMusicScanner {
  static final OnAudioQuery _query = OnAudioQuery();
  static const String _coverSubdir = 'covers';

  /// 鍏佽鐨勫悗缂€锛堢洰褰曢亶鍘嗙敤锛?
  static const Set<String> _audioExts = <String>{
    '.mp3', '.flac', '.m4a', '.wav', '.ogg', '.aac', '.opus',
  };

  /// 鎵弿绯荤粺濯掍綋搴擄紝杩斿洖鐪熷疄鍏冩暟鎹殑鏈湴鏇茬洰鍒楄〃
  static Future<List<Track>> scan() async {
    // 妗岄潰骞冲彴鏃犲獟浣撳簱姒傚康锛屼氦缁欒仛鍚堝眰鍥為€€
    if (!Platform.isAndroid && !Platform.isIOS) return const [];

    // 涓昏矾寰勶細on_audio_query 璧?MediaStore
    final List<Track> mediaTracks = await _scanViaMediaStore();
    if (mediaTracks.isNotEmpty) return mediaTracks;

    // Fallback锛氱洿鎺ョ洰褰曢亶鍘嗭紙鍏煎瑁佸壀绯荤粺 / Wear OS GSI锛?
    LogService.instance.w(
        'scan', 'MediaStore 鏈繑鍥炴洸鐩紝鍥為€€鍒扮洰褰曢亶鍘?);
    return _scanViaDirectory();
  }

  /// on_audio_query 涓昏矾寰?
  static Future<List<Track>> _scanViaMediaStore() async {
    final bool granted = await _requestPermission();
    if (!granted) {
      LogService.instance.w('scan', '鏈巿浜堥煶涔愬簱鏉冮檺锛岃烦杩?MediaStore 鎵弿');
      return const <Track>[];
    }

    try {
      final List<SongModel> songs = await _query.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
      );

      final Directory coverDir = await _coverDir();
      final List<Track> tracks = <Track>[];

      for (final SongModel s in songs) {
        // R33锛歁ediaStore 涓嶅悓瀹炵幇杩斿洖绫诲瀷涓嶄竴鑷达紙Android 渚у父涓?int锛岄儴鍒嗕负 String锛夛紝
        // 瀹归敊澶勭悊閬垮厤 "int is not a subtype of String?" 寮鸿浆宕╂簝銆?
        final int? durMs = switch (s.duration) {
          int di => di,
          _ => int.tryParse(s.duration.toString()),
        };
        final Duration? duration =
            durMs != null ? Duration(milliseconds: durMs) : null;

        // 灏侀潰锛氭寜闇€鍐欏叆搴旂敤鏂囨。鐩綍缂撳瓨锛堢己澶变笉鑷村懡锛?
        String? coverPath;
        try {
          final Uint8List? art = await _query.queryArtwork(
            s.id,
            ArtworkType.AUDIO,
            size: 300,
            quality: 75,
          );
          if (art != null) {
            final File f = File(p.join(coverDir.path, '${s.id}.jpg'));
            await f.writeAsBytes(art);
            coverPath = f.path;
          }
        } catch (_) {
          // 灏侀潰缂哄け涓嶉樆鏂壂鎻?
        }

        tracks.add(Track(
          title: s.title,
          artist: (s.artist ?? '鏈煡鑹轰汉'),
          uri: s.data,
          source: TrackSource.local,
          sourceId: 'local',
          album: s.album,
          duration: duration,
          coverPath: coverPath,
          extras: <String, dynamic>{
            'androidId': s.id,
            'albumId': s.albumId,
          },
        ));
      }

      LogService.instance
          .i('scan', 'MediaStore 鎵弿瀹屾垚: ${tracks.length} 棣?);
      return tracks;
    } catch (e, st) {
      LogService.instance.e('scan', 'MediaStore 鎵弿澶辫触: $e\n$st');
      return const <Track>[];
    }
  }

  /// Fallback 鐩綍閬嶅巻锛氱洿鎺ヨ甯歌闊充箰鐩綍鐨勯煶棰戞枃浠?
  ///
  /// 浠呭湪 [_scanViaMediaStore] 杩斿洖绌烘椂璋冪敤銆傛棤鍏冩暟鎹紝鏇插悕鍙栨枃浠跺悕銆?
  static Future<List<Track>> _scanViaDirectory() async {
    final List<Directory> roots = await _candidateRoots();
    final List<Track> tracks = <Track>[];

    for (final Directory dir in roots) {
      try {
        if (!await dir.exists()) continue;
        await for (final FileSystemEntity ent
            in dir.list(recursive: false, followLinks: false)) {
          if (ent is! File) continue;
          final String path = ent.path;
          final String ext = p.extension(path).toLowerCase();
          if (!_audioExts.contains(ext)) continue;
          final String name =
              p.basenameWithoutExtension(path).trim();
          if (name.isEmpty) continue;
          tracks.add(Track(
            title: name,
            artist: '鏈湴闊抽',
            uri: path,
            source: TrackSource.local,
            sourceId: 'local',
            album: null,
            duration: null,
            coverPath: null,
            extras: <String, dynamic>{
              'fromFallback': true,
              'ext': ext,
            },
          ));
        }
      } catch (e) {
        // P-1锛氬彧璁版渶鍚庝竴绾х洰褰曞悕锛屼笉钀藉畬鏁寸粷瀵硅矾寰勶紙鍙兘鍚敤鎴峰悕/绉佷汉鐩綍鍚嶏級
        LogService.instance
            .w('scan', '鐩綍閬嶅巻澶辫触 鈥?${p.basename(dir.path)}: $e');
      }
    }

    LogService.instance
        .i('scan', '鐩綍閬嶅巻瀹屾垚: ${tracks.length} 棣?);
    return tracks;
  }

  /// 鍊欓€夐煶涔愭牴鐩綍锛堟寜浼樺厛绾э級
  static Future<List<Directory>> _candidateRoots() async {
    final List<Directory> roots = <Directory>[];
    final List<String> paths = <String>[
      '/sdcard/Music',
      '/sdcard/Download',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
    ];
    for (final String s in paths) {
      try {
        final Directory d = Directory(s);
        if (await d.exists()) roots.add(d);
      } catch (_) {}
    }
    if (kDebugMode) {
      //debugPrint('[scan] candidate roots: ${roots.map((d) => d.path).toList()}');
    }
    return roots;
  }

  /// 璇锋眰绯荤粺濯掍綋搴撴潈闄愶紙on_audio_query 鑷甫鏉冮檺鎺ュ彛锛?
  static Future<bool> _requestPermission() async {
    try {
      if (await _query.permissionsStatus()) return true;
      return await _query.permissionsRequest();
    } catch (e) {
      // 鍏抽敭鍏滃簳锛歐ear OS / 瑁佸壀绯荤粺璋冪敤鏉冮檺 API 鏃朵細鎶?
      // `PlatformException(Unknown permission ...)`锛岃繖閲屾崟鑾峰悗杩斿洖 false锛?
      // 璁?scan() 杩涘叆 fallback 鐩綍閬嶅巻銆?
      LogService.instance.w('scan', '鏉冮檺璇锋眰澶辫触锛堢郴缁熶笉璇嗗埆锛燂級: $e');
      return false;
    }
  }

  static Future<Directory> _coverDir() async {
    final Directory appDir = await appDataDir();
    final Directory d = Directory(p.join(appDir.path, _coverSubdir));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 鍙栨煇鏇插皝闈紙鎸夐渶鎳掑姞杞斤紝渚?UI / 閿佸睆浣跨敤锛?
  static Future<String?> coverPathFor(Track track) async {
    final int? id = track.extras?['androidId'] as int?;
    if (id == null) return track.coverPath;
    final Directory coverDir = await _coverDir();
    final File f = File(p.join(coverDir.path, '$id.jpg'));
    if (await f.exists()) return f.path;
    try {
      final Uint8List? art = await _query.queryArtwork(
        id,
        ArtworkType.AUDIO,
        size: 300,
        quality: 75,
      );
      if (art != null) {
        await f.writeAsBytes(art);
        return f.path;
      }
    } catch (_) {
      // 蹇界暐
    }
    return null;
  }
}

