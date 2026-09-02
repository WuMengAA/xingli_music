/// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
/// 璁剧疆甯冨眬 Provider锛氬姞杞?/ 淇敼 / 鎸佷箙鍖栬嚜瀹氫箟甯冨眬
/// 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
///
/// 鏁版嵁娴侊細
///   1. 鍐峰惎鍔ㄨ `assets/settings_layout.json`锛堣嫢鎵撳寘浜嗚嚜瀹氫箟璧勪骇锛夆啋 鍚﹀垯鐢?///      [kDefaultSettingsLayout]锛堜唬鐮佸唴宓岄粯璁わ級銆?///   2. 缂栬緫鍣紙settings_organizer_page锛変慨鏀?[settingsLayoutProvider]銆?///   3. 銆屽鍑鸿祫浜с€嶆妸褰撳墠甯冨眬鍐欐垚 JSON 瀛楃涓?鈫?寮€鍙戣€呯矘璐翠负
///      `assets/settings_layout.json` 鈫?閲嶆柊鏋勫缓鍗抽殢鍖呭垎鍙戯紙璺ㄨ澶囦紶鎾級銆?library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/settings_layout.dart';

/// 褰撳墠鐢熸晥鐨勮缃竷灞€锛堥粯璁?= 浠ｇ爜鍐呭祵锛夈€?final StateProvider<SettingsLayout> settingsLayoutProvider =
    StateProvider<SettingsLayout>((Ref ref) => kDefaultSettingsLayout);

/// 甯冨眬椹卞姩瑙嗗浘涓綋鍓嶉€変腑鐨勫悎闆?id锛堥粯璁ら涓級銆?final StateProvider<String> layoutSelectedCollectionProvider =
    StateProvider<String>((Ref ref) => 'audio');

/// 鏄惁宸插姞杞借祫浜ц鐩栵紙鍐峰惎鍔ㄥ紓姝ュ姞杞藉畬鎴愬墠涓?false锛孶I 鏄剧ず榛樿涓嶉棯璺筹級銆?final StateProvider<bool> settingsLayoutLoadedProvider =
    StateProvider<bool>((Ref ref) => false);

/// 鍐峰惎鍔細灏濊瘯璇?`assets/settings_layout.json` 瑕嗙洊榛樿甯冨眬銆?Future<void> loadSettingsLayoutAsset(WidgetRef ref) async {
  try {
    final String raw = await rootBundle.loadString('assets/settings_layout.json');
    if (raw.trim().isEmpty) return;
    final dynamic parsed = const JsonDecoder().convert(raw);
    if (parsed is Map<String, dynamic>) {
      final SettingsLayout layout = SettingsLayout.fromJson(parsed);
      if (layout.collections.isNotEmpty) {
        ref.read(settingsLayoutProvider.notifier).state = layout;
      }
    }
  } catch (_) {
    // 璧勪骇缂哄け/鎹熷潖 鈫?淇濇寔榛樿甯冨眬锛堝紑鍙戣€呮湭鎵撳寘鑷畾涔夊竷灞€鐨勬甯歌矾寰勶級銆?  } finally {
    ref.read(settingsLayoutLoadedProvider.notifier).state = true;
  }
}

/// 瀵煎嚭褰撳墠甯冨眬涓?JSON 璧勪骇鍐呭锛堝紑鍙戣€呯矘璐村埌 assets/settings_layout.json锛夈€?String exportSettingsLayoutJson(SettingsLayout layout) => layout.encode();

/// 鏂板缓鍚堥泦锛堣繑鍥?id锛夈€?String newCollectionId() => 'col_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

/// 鏂板缓缁勶紙杩斿洖 id锛夈€?String newGroupId() => 'grp_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

