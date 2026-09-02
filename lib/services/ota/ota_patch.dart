/// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
/// OTA 琛ヤ竵鍩虹嚎绠＄悊锛坈l76_hotfix5锛氬閲忓樊鍒嗙儹淇锛?
/// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
///
/// 澧為噺琛ヤ竵闇€瑕佷竴涓€屾棫 APK 鍩虹嚎銆嶆墠鑳藉悎鎴愭柊鍖呫€侫ndroid 涓?*鏃犳硶鐩存帴璇?
/// /data/app 涓嬪凡瀹夎鍖呯殑瀛楄妭**锛屾墍浠ラ娆″惎鍔?瀹夎鍚庢妸褰撳墠 APK 澶嶅埗涓€浠藉埌
/// 绉佹湁 files 鐩綍锛坄ota_base.apk`锛夛紱涓嬫鏇存柊涓嬭浇琛ヤ竵 鈫?鍩虹嚎+琛ヤ竵鍚堟垚鏂板寘 鈫?
/// 鏍￠獙閫氳繃鍚庢妸鏂板寘鎻愬崌涓烘柊鍩虹嚎锛屽姝よ凯浠ｃ€?
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../core/paths.dart';

/// 鍙栧綋鍓嶅畨瑁呭寘璺緞鐨勫師鐢熼€氶亾锛圡ainActivity 娉ㄥ唽锛夈€?
const String kAppInfoChannel = 'com.stelarith.xingli_music/app_info';

/// OTA 琛ヤ竵鍩虹嚎銆?
class OtaPatchBase {
  OtaPatchBase._();

  static const MethodChannel _channel = MethodChannel(kAppInfoChannel);

  /// 褰撳墠瀹夎鍖呯粷瀵硅矾寰勶紙鍘熺敓 `sourceDir`锛涢潪 Android / 澶辫触杩斿洖绌轰覆锛夈€?
  static Future<String> sourceDir() async {
    if (!Platform.isAndroid) return '';
    try {
      final String? s = await _channel.invokeMethod<String>('sourceDir');
      return s ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> _basePath() async {
    final Directory dir = await appDataDir();
    return p.join(dir.path, 'ota_base.apk');
  }

  /// 纭繚琛ヤ竵鍚堟垚鍩虹嚎瀛樺湪锛堥娆″垯澶嶅埗褰撳墠瀹夎鍖咃紱宸插瓨鍦ㄧ洿鎺ヨ繑鍥烇級銆?
  /// 杩斿洖鍩虹嚎璺緞锛涙棤娉曞彇寰楋紙闈?Android / 澶嶅埗澶辫触锛夎繑鍥?null銆?
  static Future<String?> ensureBase() async {
    final String base = await _basePath();
    if (File(base).existsSync()) return base;
    final String src = await sourceDir();
    if (src.isEmpty) return null;
    try {
      await File(src).copy(base);
      return base;
    } catch (_) {
      return null;
    }
  }

  /// 琛ヤ竵鍚堟垚骞堕€氳繃 SHA-256 鏍￠獙鍚庯紝鎶婃柊 APK 鎻愬崌涓烘柊鍩虹嚎锛堜緵涓嬫琛ヤ竵锛夈€?
  static Future<void> promoteBase(String newApk) async {
    final String base = await _basePath();
    try {
      final File src = File(newApk);
      if (src.existsSync()) await src.copy(base);
    } catch (_) {}
  }

  /// 鍒犻櫎鏃у熀绾匡紙鍙€夛細搴旂敤鏇存柊鏇挎崲鑷韩鍚庡熀绾垮彲鑳藉凡杩囨湡锛夈€?
  static Future<void> clearBase() async {
    try {
      final File f = File(await _basePath());
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}

