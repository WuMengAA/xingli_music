/// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
/// 绌洪棿闊虫晥 路 娣烽煶/鎾斁鍣紙SpatialMixer锛?
/// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
///
/// - 涓?[SpatialSound] 鐨勬瘡鏉￠煶杞ㄥ垱寤虹嫭绔?audioplayers 鎾斁鍣?
/// - 鎸?[ChannelLayout] 鏄犲皠澹伴亾澧炵泭锛氱珛浣撳０鐢ㄥ乏鍙冲０閬撳０鍍忥紙pan锛夛紝
///   鍗曞０閬撻檷绾э紝鐜粫鎸夋柟鍚戞槧灏勶紙audioplayers 鍘熺敓浠?L/R pan锛?
///   鐜粫閫氳繃澧炵泭杩戜技锛?
/// - 鏉愭枡闅旈煶锛氱洰鏍囧闅斿鏁?[walls] 鎶樼畻闊抽噺琛板噺锛圼transmissionLoss]锛?
/// - 闊宠建鏂囦欢锛氫紭鍏?[SpatialTrack.audioPath]锛屽惁鍒欑▼搴忓悎鎴愮紦瀛?
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as ap;
import '../../../core/paths.dart';

import '../../log_service.dart';
import 'spatial_models.dart';
import 'spatial_synth.dart';

/// 绌洪棿闊虫晥鎾斁鍣紙绠＄悊涓€涓?SpatialSound 鐨勫杞ㄥ疄渚嬶級銆?
class SpatialPlayer {
  SpatialPlayer(this.sound, {this.layout = ChannelLayout.stereo});

  final SpatialSound sound;
  final ChannelLayout layout;

  final List<ap.AudioPlayer> _players = <ap.AudioPlayer>[];
  bool _started = false;

  /// 璺濈琛板噺鍊嶇巼锛?~1锛夛紝鐢变笘鐣岄煶鏁堝紩鎿庢寜鐩告満璺濈鍔ㄦ€佸啓鍏ャ€?
  double _distanceGain = 1.0;

  /// 褰撳墠闅斿鏁帮紙materials 琛板噺鐢級銆?
  int _walls = 0;

  /// 鍚姩鍏ㄩ儴闊宠建锛堟寜澹板儚/闊抽噺/鏉愭枡琛板噺锛夈€?
  Future<void> start({int walls = 0}) async {
    if (_started) return;
    _started = true;
    _walls = walls;
    for (final SpatialTrack track in sound.tracks) {
      try {
        final ap.AudioPlayer p = ap.AudioPlayer();
        // 涓嶆姠鐒︾偣锛氫笌鍦烘櫙闊虫櫙涓€鑷达紝閬垮厤鎵撴柇闊充箰锛圧3 澶嶇敤锛?
        await p.setAudioContext(
          ap.AudioContextConfig(focus: ap.AudioContextConfigFocus.mixWithOthers).build(),
        );
        await p.setReleaseMode(ap.ReleaseMode.loop);
        await p.setSource(await _sourceFor(track));
        await p.setVolume(_effectiveVolume(track, walls));
        // 鍒濆澹板儚锛氭寜闊宠建鐨勫嚑浣曞０閬?
        await _applyBalance(p, _panOf(track));
        await p.resume();
        _players.add(p);
      } catch (e) {
        LogService.instance.w('spatial', '闊宠建 ${track.id} 鍚姩澶辫触: $e');
      }
    }
  }

  /// 鍔ㄦ€佹洿鏂拌窛绂昏“鍑?+ 澹板儚锛堜笘鐣岄煶鏁堬細鐩告満绉诲姩鏃舵瘡 tick 璋冪敤锛夈€?
  ///
  /// [gain] 0~1 璺濈琛板噺鍊嶇巼锛沎pan] -1(鍏ㄥ乏)~1(鍏ㄥ彸)锛宯ull 琛ㄧず娌跨敤闊宠建鍑犱綍澹伴亾銆?
  Future<void> updateDynamics({double? gain, double? pan}) async {
    if (gain != null) _distanceGain = gain.clamp(0.0, 1.0);
    for (int i = 0; i < _players.length && i < sound.tracks.length; i++) {
      final SpatialTrack t = sound.tracks[i];
      try {
        await _players[i].setVolume(_effectiveVolume(t, _walls));
        await _applyBalance(_players[i], pan ?? _panOf(t));
      } catch (_) {}
    }
  }

  /// 闊宠建鍑犱綍澹伴亾鎶樼畻鐨勫０鍍忓€硷紙-1~1锛夈€?
  double _panOf(SpatialTrack track) {
    if (layout == ChannelLayout.mono) return 0;
    final ChannelGains g = track.gainsFor(layout);
    final double sum = g.left + g.right;
    if (sum <= 1e-6) return 0;
    return ((g.right - g.left) / sum).clamp(-1.0, 1.0);
  }

  Future<void> _applyBalance(ap.AudioPlayer p, double pan) async {
    if (layout == ChannelLayout.mono) return;
    try {
      await p.setBalance(pan.clamp(-1.0, 1.0));
    } catch (_) {
      // 閮ㄥ垎骞冲彴涓嶆敮鎸?balance锛岄潤榛橀檷绾э紙浠呴煶閲忕敓鏁堬級
    }
  }

  /// 闊虫簮瑙ｆ瀽锛歛ssets/ 鍓嶇紑璧?[ap.AssetSource]锛屽叾浣欒蛋鏈湴鏂囦欢 / 绋嬪簭鍚堟垚銆?
  Future<ap.Source> _sourceFor(SpatialTrack track) async {
    final String? path = track.audioPath;
    if (path != null && path.startsWith('assets/')) {
      // audioplayers 鐨?AssetSource 鐩稿 `assets/` 鏍癸紝闇€鍘绘帀鍓嶇紑
      return ap.AssetSource(path.substring('assets/'.length));
    }
    return ap.DeviceFileSource(await _ensureTrackFile(track));
  }

  /// 鍋滄鍏ㄩ儴闊宠建骞堕噴鏀俱€?
  Future<void> stop() async {
    for (final ap.AudioPlayer p in _players) {
      try {
        await p.stop();
        await p.dispose();
      } catch (_) {}
    }
    _players.clear();
    _started = false;
  }

  /// 鏇存柊闅斿鏁帮紙鏉愭枡闅旈煶鍔ㄦ€佺敓鏁堬級銆?
  Future<void> setWalls(int walls) async {
    _walls = walls;
    for (int i = 0; i < _players.length && i < sound.tracks.length; i++) {
      try {
        await _players[i].setVolume(_effectiveVolume(sound.tracks[i], walls));
      } catch (_) {}
    }
  }

  double _effectiveVolume(SpatialTrack track, int walls) {
    final double base = track.volume * _distanceGain;
    final double loss = transmissionLoss(sound.material, walls);
    return (base * dbToGain(loss)).clamp(0.0, 1.0);
  }

  Future<String> _ensureTrackFile(SpatialTrack track) async {
    if (track.audioPath != null && await File(track.audioPath!).exists()) {
      return track.audioPath!;
    }
    final Directory dir = await appDataDir();
    final String synthId = track.synthesisId ?? track.id;
    final File f = File('${dir.path}/spatial_${sound.id}_${track.id}_$synthId.wav');
    if (await f.exists()) return f.path;
    final Uint8List wav = SpatialSynth.synthesizeWav(synthId, seed: sound.id.hashCode);
    await f.writeAsBytes(wav, flush: true);
    return f.path;
  }
}

/// 绌洪棿闊虫晥璋冨害鍣細绠＄悊澶氱粍绌洪棿闊虫晥鐨勫惎鍋溿€?
class SpatialMixer {
  SpatialMixer({this.layout = ChannelLayout.stereo});

  final ChannelLayout layout;
  final List<SpatialPlayer> _active = <SpatialPlayer>[];

  /// 鎾斁涓€缁勭┖闂撮煶鏁堬紙鏇挎崲鍚?id 鐨勬棫瀹炰緥锛夈€?
  Future<void> play(SpatialSound sound, {int walls = 0}) async {
    await stopById(sound.id);
    final SpatialPlayer p = SpatialPlayer(sound, layout: layout);
    await p.start(walls: walls);
    _active.add(p);
  }

  /// 鍋滄鎸囧畾 id銆?
  Future<void> stopById(String id) async {
    final List<SpatialPlayer> matches =
        _active.where((p) => p.sound.id == id).toList();
    for (final SpatialPlayer p in matches) {
      await p.stop();
      _active.remove(p);
    }
  }

  /// 鍋滄鍏ㄩ儴銆?
  Future<void> stopAll() async {
    for (final SpatialPlayer p in _active) {
      await p.stop();
    }
    _active.clear();
  }

  /// 鏇存柊鏌愰煶鏁堢殑闅斿鏁般€?
  Future<void> updateWalls(String id, int walls) async {
    for (final SpatialPlayer p in _active) {
      if (p.sound.id == id) {
        await p.setWalls(walls);
      }
    }
  }

  /// 鏇存柊鏌愰煶鏁堢殑璺濈琛板噺 / 澹板儚锛堜笘鐣岄煶鏁堝紩鎿庢瘡 tick 璋冪敤锛夈€?
  Future<void> updateDynamics(
    String id, {
    double? gain,
    double? pan,
    int? walls,
  }) async {
    for (final SpatialPlayer p in _active) {
      if (p.sound.id != id) continue;
      if (walls != null) await p.setWalls(walls);
      await p.updateDynamics(gain: gain, pan: pan);
    }
  }

  /// 褰撳墠鍦ㄦ挱鐨勯煶鏁?id 闆嗗悎銆?
  Set<String> get activeIds =>
      _active.map((SpatialPlayer p) => p.sound.id).toSet();

  Future<void> dispose() => stopAll();
}

