/// ════════════════════════════════════════════════════════════════════════
/// OTA GitHub Pages manifest 解析单测（clOTA）
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/services/ota/pages_manifest.dart';

const String _kSampleManifest = '''
{
  "schema": 1,
  "source": "github-pages",
  "updatedAt": "2026-08-31T06:20:00+08:00",
  "channels": {
    "beta": {
      "latest": {
        "tag": "0.26.8.31_beta_cl01",
        "dateKey": 260831,
        "build": 1,
        "hotfix": null,
        "notes": "clOTA：GitHub Pages 分发链路"
      }
    },
    "alpha": {
      "latest": {
        "tag": "0.26.8.31_alpha_cl03",
        "dateKey": 260831,
        "build": 3,
        "hotfix": 1,
        "notes": "alpha 热修补丁"
      }
    }
  },
  "assets": {
    "0.26.8.31_beta_cl01": {
      "android": {
        "arm64-v8a": {"name": "app-arm64-v8a-release.apk", "size": 44890000, "sha256": "aaaaaaaa"},
        "armeabi-v7a": {"name": "app-armeabi-v7a-release.apk", "size": 42200000, "sha256": "bbbbbbbb"}
      },
      "windows": {
        "x64": {"name": "xingli_music_windows_x64.zip", "size": 81200000, "sha256": "cccccccc"}
      }
    }
  },
  "versions": ["0.26.8.31_beta_cl01"]
}
''';

void main() {
  group('parsePagesManifest', () {
    test('正常 manifest 解析：渠道/资产/版本齐备', () {
      final PagesOtaManifest? m = parsePagesManifest(_kSampleManifest);
      expect(m, isNotNull);
      expect(m!.schema, 1);
      expect(m.updatedAt, contains('2026-08-31'));

      // 渠道 latest。
      final PagesChannelLatest beta = m.channels['beta']!;
      expect(beta.tag, '0.26.8.31_beta_cl01');
      expect(beta.dateKey, 260831);
      expect(beta.build, 1);
      expect(beta.hotfix, isNull);
      expect(beta.channelTag, 'beta');
      expect(beta.notes, contains('clOTA'));

      final PagesChannelLatest alpha = m.channels['alpha']!;
      expect(alpha.build, 3);
      expect(alpha.hotfix, 1);

      // 版本列表。
      expect(m.versions, ['0.26.8.31_beta_cl01']);

      // 资产。
      final PagesTagAssets ta = m.assetsByTag['0.26.8.31_beta_cl01']!;
      expect(ta.android['arm64-v8a']!.name, 'app-arm64-v8a-release.apk');
      expect(ta.android['arm64-v8a']!.size, 44890000);
      expect(ta.android['arm64-v8a']!.sha256, 'aaaaaaaa');
      expect(ta.windows!['x64']!.name, 'xingli_music_windows_x64.zip');
    });

    test('assetFor：按平台/ABI 命中与未命中', () {
      final PagesOtaManifest? m = parsePagesManifest(_kSampleManifest);
      final String tag = '0.26.8.31_beta_cl01';

      expect(
        m!.assetFor(tag, 'arm64-v8a', windows: false)!.name,
        'app-arm64-v8a-release.apk',
      );
      expect(
        m.assetFor(tag, 'armeabi-v7a', windows: false)!.name,
        'app-armeabi-v7a-release.apk',
      );
      expect(
        m.assetFor(tag, 'x64', windows: true)!.name,
        'xingli_music_windows_x64.zip',
      );
      // 未收录 tag / 平台。
      expect(m.assetFor('0.26.8.31_alpha_cl03', 'arm64-v8a', windows: false), isNull);
      expect(m.assetFor(tag, 'x64', windows: false), isNull);
    });

    test('缺渠道版本记录时通道为空但不崩溃', () {
      final PagesOtaManifest? m = parsePagesManifest('''
{
  "schema": 1,
  "channels": {},
  "assets": {},
  "versions": []
}
''');
      expect(m, isNotNull);
      expect(m!.channels, isEmpty);
      expect(m.versions, isEmpty);
    });

    test('schema 不符 / 坏 JSON / 空串 → null', () {
      expect(parsePagesManifest('{"schema":2}'), isNull);
      expect(parsePagesManifest('not json {'), isNull);
      expect(parsePagesManifest(''), isNull);
      expect(parsePagesManifest('"plain string"'), isNull);
    });

    test('资产条目缺名被跳过；windows 缺省为 null', () {
      final PagesOtaManifest? m = parsePagesManifest('''
{
  "schema": 1,
  "channels": {},
  "assets": {
    "0.26.8.31_beta_cl01": {
      "android": {
        "arm64-v8a": {"name": "", "size": 1, "sha256": "dd"},
        "armeabi-v7a": {"name": "app-armeabi-v7a-release.apk", "size": 2, "sha256": "ee"}
      }
    }
  },
  "versions": ["0.26.8.31_beta_cl01"]
}
''');
      final PagesTagAssets? ta = m!.assetsByTag['0.26.8.31_beta_cl01'];
      expect(ta, isNotNull);
      expect(ta!.android.containsKey('arm64-v8a'), isFalse);
      expect(ta.android['armeabi-v7a']!.name, 'app-armeabi-v7a-release.apk');
      expect(ta.windows, isNull);
    });

    test('versions 非字符串项被过滤', () {
      final PagesOtaManifest? m = parsePagesManifest('''
{
  "schema": 1,
  "channels": {},
  "assets": {},
  "versions": ["0.26.8.31_beta_cl01", 42, null, "0.26.8.30_beta_cl02"]
}
''');
      expect(m!.versions, ['0.26.8.31_beta_cl01', '0.26.8.30_beta_cl02']);
    });
  });
}