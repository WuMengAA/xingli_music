import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/core/app_version.dart';
import 'package:xingli_music/services/ota_service.dart';

void main() {
  group('parseOtaTag 新格式 tag 解析', () {
    test('beta 渠道完整解析', () {
      final OtaTagInfo? info = parseOtaTag('0.26.08.17_beta_cl01');
      expect(info, isNotNull);
      expect(info!.dateKey, 260817);
      expect(info.channel, UpdateChannel.beta);
      expect(info.build, 1);
      expect(info.hotfix, isNull);
    });

    test('alpha 渠道 + hotfix 解析', () {
      final OtaTagInfo? info = parseOtaTag('0.26.8.17_alpha_cl02_hotfix1');
      expect(info, isNotNull);
      expect(info!.dateKey, 260817);
      expect(info.channel, UpdateChannel.alpha);
      expect(info.build, 2);
      expect(info.hotfix, 1);
    });

    test('历史 cl* tag（无日期）返回 null（不参与新比较）', () {
      expect(parseOtaTag('cl78'), isNull);
      expect(parseOtaTag('cl76_hotfix5'), isNull);
      expect(parseOtaTag('v0.26.8.14'), isNull);
    });

    test('缺渠道段 / 非 0.26.8 前缀返回 null', () {
      expect(parseOtaTag('0.26.8.17_cl01'), isNull);
      expect(parseOtaTag('1.2.3_beta_cl01'), isNull);
    });

    test('UpdateChannel.fromTag 未知回落 beta 默认', () {
      expect(UpdateChannel.fromTag('beta'), UpdateChannel.beta);
      expect(UpdateChannel.fromTag('alpha'), UpdateChannel.alpha);
      expect(UpdateChannel.fromTag('garbage'), UpdateChannel.beta);
    });
  });

  group('newerThanCurrent 渠道内新旧判断（2026-08-17 渠道化）', () {
    // 当前：2026-08-17（dateKey 260817）cl01
    const int curDate = 260817;
    const int curBuild = 1;

    test('同日 cl 更大 → 有更新', () {
      final OtaTagInfo tag = parseOtaTag('0.26.08.17_beta_cl02')!;
      expect(tag.newerThanCurrent(curDate, curBuild), isTrue);
    });

    test('同日 cl 更小 → 无更新', () {
      final OtaTagInfo tag = parseOtaTag('0.26.08.17_beta_cl01')!;
      expect(tag.newerThanCurrent(curDate, curBuild), isFalse);
    });

    test('历史跨天误判根治：昨天(8.16)cl78 vs 今天(8.17)cl01 → 无更新', () {
      // 这正是历史坑：cl78 > cl01 误判"有更新"。日期优先后 8.16 < 8.17 → 无更新。
      final OtaTagInfo tag = parseOtaTag('0.26.8.16_beta_cl78')!;
      expect(tag.dateKey, lessThan(curDate));
      expect(tag.newerThanCurrent(curDate, curBuild), isFalse);
    });

    test('明天(8.18)cl01 → 有更新（日期大）', () {
      final OtaTagInfo tag = parseOtaTag('0.26.8.18_beta_cl01')!;
      expect(tag.newerThanCurrent(curDate, curBuild), isTrue);
    });

    test('同日同版本 hotfix → 有更新（补丁包）', () {
      final OtaTagInfo tag = parseOtaTag('0.26.08.17_beta_cl01_hotfix1')!;
      expect(tag.newerThanCurrent(curDate, curBuild), isTrue);
    });
  });

  group('AppVersion 渠道化展示', () {
    test('displayShort 含渠道段（beta 默认）', () {
      // Windows VM 上 display 带 _pc；displayShort 无 cl/pc，稳定断言。
      // 版本号按日期演进（0.26.08.17 → 0.26.08.29 …），这里只校验格式
      // （x.yy.mm.dd_beta/alpha），不写死具体日期，避免随版本迭代失效。
      expect(AppVersion.displayShort, matches(RegExp(r'^0\.26\.\d{2}\.\d{2}_(beta|alpha)$')));
      expect(AppVersion.display, contains('_beta_cl'));
    });

    test('channel 默认 beta（稳定）', () {
      expect(AppVersion.channel, UpdateChannel.beta);
      expect(AppVersion.channel.label, contains('Beta'));
    });
  });

  group('电脑版 OTA 资产命名约定（cl77）', () {
    test('Windows 更新包固定名（不随 tag 变）', () {
      expect(otaWindowsAssetName(), 'xingli_music_windows_x64.zip');
      expect(otaWindowsShaAssetName(), 'xingli_music_windows_x64.zip.sha256');
    });

    test('安卓拆分包命名不受影响（arm64 / arm32）', () {
      expect(otaApkAssetForAbi(DeviceAbi.arm64),
          'app-arm64-v8a-release.apk');
      expect(otaApkAssetForAbi(DeviceAbi.arm32),
          'app-armeabi-v7a-release.apk');
      expect(otaShaAssetForAbi(DeviceAbi.arm64),
          'app-arm64-v8a-release.apk.sha256');
    });
  });
}
