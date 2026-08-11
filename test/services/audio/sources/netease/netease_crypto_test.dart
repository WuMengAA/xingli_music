import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/services/audio/sources/netease/netease_crypto.dart';

/// I 域 · 网易云 weapi 协议加密单测（**全离线，不发任何网络请求**）。
///
/// 拿不到官方参考实现的密文，无法逐字节比对 params；因此本测试守三条线：
///   1. 底层 AES 必须对得上 FIPS-197 官方向量 —— 否则一个写反的 ShiftRows
///      也能自洽地跑通，却根本不是 AES；
///   2. 给定同一明文 + 同一 secretKey，输出必须完全确定；
///   3. 不给 secretKey 时必须每次不同（随机密钥没退化成常量），
///      且返回结构与长度符合协议约定。
void main() {
  group('AES 正确性（FIPS-197 官方向量）', () {
    test('附录 C.1：AES-128 单块加密结果与标准一致', () {
      expect(
        neteaseAesBlockHexForTest(
          keyHex: '000102030405060708090a0b0c0d0e0f',
          plainHex: '00112233445566778899aabbccddeeff',
        ),
        '69c4e0d86a7b0430d8cdb78070b4c55a',
      );
    });

    test('附录 C.2：AES-192 单块加密结果与标准一致', () {
      expect(
        neteaseAesBlockHexForTest(
          keyHex: '000102030405060708090a0b0c0d0e0f1011121314151617',
          plainHex: '00112233445566778899aabbccddeeff',
        ),
        'dda97ca4864cdfe06eaf70a0ec0d7191',
      );
    });
  });

  group('weapi 输出结构', () {
    test('返回且仅返回 params / encSecKey 两个非空字段', () {
      final Map<String, String> out = weapi(jsonEncode(<String, dynamic>{'s': '星璃'}));

      expect(out.keys.toSet(), <String>{'params', 'encSecKey'});
      expect(out['params'], isNotEmpty);
      expect(out['encSecKey'], isNotEmpty);
    });

    test('params 是合法 base64，且长度为 AES 分组的整数倍', () {
      final Map<String, String> out = weapi('{"id":1}');
      final int len = base64Decode(out['params']!).length;

      expect(len % 16, 0);
      expect(len, greaterThan(0));
    });

    test('encSecKey 为 256 位十六进制小写串（RSA 1024 bit 输出）', () {
      final Map<String, String> out = weapi('{"id":1}');

      expect(out['encSecKey']!.length, 256);
      expect(RegExp(r'^[0-9a-f]{256}$').hasMatch(out['encSecKey']!), isTrue);
    });
  });

  group('确定性与随机性', () {
    const String plain = '{"ids":"[347230]","level":"standard"}';
    const String fixedSecret = 'abcdefgh12345678';

    test('同一明文 + 同一 secretKey → params 与 encSecKey 完全一致', () {
      final Map<String, String> a = weapi(plain, secretKey: fixedSecret);
      final Map<String, String> b = weapi(plain, secretKey: fixedSecret);

      expect(a['params'], b['params']);
      expect(a['encSecKey'], b['encSecKey']);
    });

    test('明文不同 → params 不同（内层 AES 真的参与了运算）', () {
      final Map<String, String> a = weapi(plain, secretKey: fixedSecret);
      final Map<String, String> b = weapi('{"ids":"[1]"}', secretKey: fixedSecret);

      expect(a['params'], isNot(b['params']));
      // 密钥没变，encSecKey 只由密钥决定
      expect(a['encSecKey'], b['encSecKey']);
    });

    test('不传 secretKey → 每次随机密钥，两次输出必然不同', () {
      final Map<String, String> a = weapi(plain);
      final Map<String, String> b = weapi(plain);

      expect(a['params'], isNot(b['params']));
      expect(a['encSecKey'], isNot(b['encSecKey']));
    });

    test('secretKey 长度非法时立即抛错，不产出可疑密文', () {
      expect(() => weapi(plain, secretKey: 'tooshort'), throwsArgumentError);
    });
  });

  test('weapiJson 与 weapi(jsonEncode(...)) 等价', () {
    const String secret = 'ABCDEFGH87654321';
    final Map<String, String> a =
        weapiJson(<String, dynamic>{'s': 'test', 'limit': 30}, secretKey: secret);
    final Map<String, String> b = weapi(
      jsonEncode(<String, dynamic>{'s': 'test', 'limit': 30}),
      secretKey: secret,
    );

    expect(a['params'], b['params']);
    expect(a['encSecKey'], b['encSecKey']);
  });
}
