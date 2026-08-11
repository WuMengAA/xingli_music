import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xingli_music/services/security/secure_store.dart';

/// P-3 SecureBox 测试。
///
/// 重点不只是「往返能通」——自实现的密码学必须对**官方测试向量**，
/// 否则一个写反的 ShiftRows 也能自洽地加解密成功，却根本不是 AES。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AES-256 正确性（FIPS-197 官方向量）', () {
    test('附录 C.3：AES-256 单块加密结果与标准一致', () {
      // key = 000102...1f, plaintext = 00112233445566778899aabbccddeeff
      // 期望密文 = 8ea2b7ca516745bfeafc49904b496089（FIPS-197 附录 C.3）
      final String got = aesEcbBlockHexForTest(
        keyHex: '000102030405060708090a0b0c0d0e0f'
            '101112131415161718191a1b1c1d1e1f',
        plainHex: '00112233445566778899aabbccddeeff',
      );
      expect(got, '8ea2b7ca516745bfeafc49904b496089');
    });
  });

  group('加解密往返', () {
    test('普通字符串往返一致', () async {
      final box = SecureBox(deviceSeed: 'seed-a');
      const String plain = 'MUSIC_U=deadbeef; __csrf=abc123';
      final String armored = await box.encrypt(plain);

      expect(armored, isNot(contains('deadbeef')), reason: '密文不得含明文片段');
      expect(await box.decrypt(armored), plain);
    });

    test('中文 / emoji / 空串 / 长文本均可往返', () async {
      final box = SecureBox(deviceSeed: 'seed-a');
      final List<String> samples = <String>[
        '',
        '星璃音乐空间',
        '🎧🌌',
        'x' * 5000,
      ];
      for (final String s in samples) {
        expect(await box.decrypt(await box.encrypt(s)), s,
            reason: '长度 ${s.length} 的样本往返失败');
      }
    });

    test('同一明文两次加密结果不同（随机 IV）但都能解开', () async {
      final box = SecureBox(deviceSeed: 'seed-a');
      const String plain = 'same-plaintext';
      final String a = await box.encrypt(plain);
      final String b = await box.encrypt(plain);

      expect(a, isNot(equals(b)));
      expect(await box.decrypt(a), plain);
      expect(await box.decrypt(b), plain);
    });
  });

  group('完整性与失败处理', () {
    test('密文被篡改 → 返回 null（HMAC 拦截）', () async {
      final box = SecureBox(deviceSeed: 'seed-a');
      final String armored = await box.encrypt('secret');

      // 翻转信封中部一个字节
      final List<int> raw = base64Decode(armored);
      raw[raw.length ~/ 2] ^= 0x01;

      expect(await box.decrypt(base64Encode(raw)), isNull);
    });

    test('非法 base64 / 垃圾串 → 返回 null，不抛异常', () async {
      final box = SecureBox(deviceSeed: 'seed-a');
      expect(await box.decrypt('not-base64!!!'), isNull);
      expect(await box.decrypt(''), isNull);
      expect(await box.decrypt(base64Encode(<int>[1, 2, 3])), isNull);
    });

    test('换设备标识（等价于换设备）→ 解不开旧密文', () async {
      final prefs = await SharedPreferences.getInstance();
      final String armored =
          await SecureBox(prefs: prefs, deviceSeed: 'device-1')
              .encrypt('cookie');

      final other = SecureBox(prefs: prefs, deviceSeed: 'device-2');
      expect(await other.decrypt(armored), isNull);
    });
  });

  group('落盘读写', () {
    test('writeSecret 后 prefs 中不存在明文，readSecret 能取回', () async {
      final prefs = await SharedPreferences.getInstance();
      final box = SecureBox(prefs: prefs, deviceSeed: 'seed-a');
      const String cookie = 'MUSIC_U=very-secret-token-value';

      await box.writeSecret(SecureBox.kNeteaseCookie, cookie);

      final String? stored =
          prefs.getString('${SecureBox.kSecretPrefix}${SecureBox.kNeteaseCookie}');
      expect(stored, isNotNull);
      expect(stored, isNot(contains('very-secret-token-value')),
          reason: 'prefs 里必须是密文');

      expect(await box.readSecret(SecureBox.kNeteaseCookie), cookie);
    });

    test('未写入的 key 返回 null；deleteSecret 后再读为 null', () async {
      final prefs = await SharedPreferences.getInstance();
      final box = SecureBox(prefs: prefs, deviceSeed: 'seed-a');

      expect(await box.readSecret('nope'), isNull);

      await box.writeSecret('k', 'v');
      expect(await box.readSecret('k'), 'v');
      await box.deleteSecret('k');
      expect(await box.readSecret('k'), isNull);
    });

    test('盐持久化：新建实例仍能解开旧密文', () async {
      final prefs = await SharedPreferences.getInstance();
      await SecureBox(prefs: prefs, deviceSeed: 'seed-a')
          .writeSecret('k', 'persisted');

      expect(prefs.getString(SecureBox.kSaltKey), isNotNull, reason: '盐应已落盘');

      final fresh = SecureBox(prefs: prefs, deviceSeed: 'seed-a');
      expect(await fresh.readSecret('k'), 'persisted');
    });
  });
}
