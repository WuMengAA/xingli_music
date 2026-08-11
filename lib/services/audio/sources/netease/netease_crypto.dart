/// 星璃 · 网易云 weapi 协议加密（I 域 · P1-1）
///
/// ⚠ 与 `services/security/secure_store.dart` 的 `SecureBox` 是**两件事**：
///   - 本文件是**协议加密**，唯一目的是让网易云服务器接受我们的请求体；
///   - `SecureBox` 是**凭证加密**，保护落盘的 cookie。
///   两者不可互相替代，也不要合并（见 docs/方案_音源扩充.md §4.1）。
///
/// weapi 算法（社区逆向，常量固定，见 §4.7.4）：
///   1. inner     = base64(AES-CBC(text, presetKey, iv))
///   2. secret    = 16 位 base62 随机串（每次请求全新）
///   3. params    = base64(AES-CBC(inner, secret, iv))
///   4. encSecKey = hex(RSA-NoPadding(reverse(secret), n, e))
///
/// AES 位宽由密钥字节长度决定（16/24/32 → AES-128/192/256）。weapi 的
/// presetKey 与 secret 均为 16 字节，故实际走 AES-128-CBC。
///
/// AES 为本工程自实现（`crypto` 包只有哈希，不含分组密码），与
/// `secure_store.dart` 的取向一致；正确性由 FIPS-197 官方向量守护，
/// 见 test/services/audio/sources/netease/netease_crypto_test.dart。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

// ════════════════════════════════════════════════════════════════
// 协议常量（社区逆向，固定值，勿改）
// ════════════════════════════════════════════════════════════════

/// 第一次 AES 的预设密钥。
const String kWeapiPresetKey = '0CoJUm6Qyw8W8jud';

/// 两次 AES 共用的 CBC 初始向量（ASCII '0102030405060708'，即 16 字节）。
const String kWeapiIv = '0102030405060708';

/// RSA 公钥指数 0x010001。
const String kWeapiPubExp = '010001';

/// RSA 公钥模数（1024 bit，首字节 0x00 为符号位）。
const String kWeapiModulus = '00e0b509f6259df8642dbc3566290147'
    '7df22677ec152b5ff68ace615bb7b725'
    '152b3ab17a876aea8a5aa76d2e417629'
    'ec4ee341f56135fccf695280104e0312'
    'ecbda92557c93870114af6c9d05c4f7f'
    '0c3685b7a46bee255932575cce10b424'
    'd813cfe4875d3e82047b97ddef52741d'
    '546b8e289dc6935b3ece0462db0a22b8'
    'e7';

/// 随机 secretKey 的字符集。
const String kWeapiBase62 =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// RSA 输出固定 128 字节 = 256 个十六进制字符。
const int _kEncSecKeyHexLen = 256;

const int _kSecretLen = 16;

// ════════════════════════════════════════════════════════════════
// 对外 API
// ════════════════════════════════════════════════════════════════

/// 加密 weapi 请求体。
///
/// [text] 为已 `jsonEncode` 的明文请求体；返回可直接作为
/// `application/x-www-form-urlencoded` 表单提交的两个字段。
///
/// [secretKey] 仅供测试注入固定密钥以获得确定性输出；生产调用**不要传**，
/// 让它每次生成全新随机密钥。
Map<String, String> weapi(String text, {String? secretKey}) {
  final String secret = secretKey ?? _randomSecret();
  if (secret.length != _kSecretLen) {
    throw ArgumentError('weapi secretKey 必须为 $_kSecretLen 字符');
  }

  final String inner = _aesCbcBase64(text, kWeapiPresetKey, kWeapiIv);
  final String params = _aesCbcBase64(inner, secret, kWeapiIv);
  final String encSecKey = _rsaNoPaddingHex(
    secret.split('').reversed.join(),
    kWeapiModulus,
    kWeapiPubExp,
  );

  return <String, String>{'params': params, 'encSecKey': encSecKey};
}

/// [weapi] 的便捷包装：直接接受 Map 请求体。
Map<String, String> weapiJson(Map<String, dynamic> body, {String? secretKey}) =>
    weapi(jsonEncode(body), secretKey: secretKey);

// ════════════════════════════════════════════════════════════════
// 测试钩子
// ════════════════════════════════════════════════════════════════

/// 仅供测试：对**单个分组**跑裸 AES（等价 ECB），用于校验底层实现是否
/// 符合 FIPS-197 官方测试向量。生产代码禁止调用。
@visibleForTesting
String neteaseAesBlockHexForTest({
  required String keyHex,
  required String plainHex,
}) {
  final Uint8List block = _hexToBytes(plainHex);
  if (block.length != 16) {
    throw ArgumentError('AES 分组必须是 16 字节');
  }
  // 零 IV 的 CBC 首块 == 该块的裸 AES；PKCS#7 会多补一整块，只取前 16 字节。
  final Uint8List out = _AesCbc(_hexToBytes(keyHex)).encrypt(block, Uint8List(16));
  return _bytesToHex(Uint8List.sublistView(out, 0, 16));
}

// ════════════════════════════════════════════════════════════════
// 内部实现
// ════════════════════════════════════════════════════════════════

final Random _rng = Random.secure();

String _randomSecret() => List<String>.generate(
      _kSecretLen,
      (_) => kWeapiBase62[_rng.nextInt(kWeapiBase62.length)],
    ).join();

String _aesCbcBase64(String text, String key, String iv) {
  final Uint8List out = _AesCbc(Uint8List.fromList(utf8.encode(key)))
      .encrypt(Uint8List.fromList(utf8.encode(text)),
          Uint8List.fromList(utf8.encode(iv)));
  return base64Encode(out);
}

/// RSA 无填充（textbook）加密：`m^e mod n`，左侧补零到固定长度。
String _rsaNoPaddingHex(String plain, String modulusHex, String expHex) {
  final BigInt n = BigInt.parse(modulusHex, radix: 16);
  final BigInt e = BigInt.parse(expHex, radix: 16);
  final BigInt m = _bytesToBigInt(utf8.encode(plain));
  return m.modPow(e, n).toRadixString(16).padLeft(_kEncSecKeyHexLen, '0');
}

BigInt _bytesToBigInt(List<int> bytes) {
  BigInt r = BigInt.zero;
  for (final int b in bytes) {
    r = (r << 8) | BigInt.from(b);
  }
  return r;
}

Uint8List _hexToBytes(String hex) {
  final String s = hex.replaceAll(' ', '');
  final Uint8List out = Uint8List(s.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _bytesToHex(Uint8List b) =>
    b.map((int v) => v.toRadixString(16).padLeft(2, '0')).join();

// ════════════════════════════════════════════════════════════════
// AES-CBC（仅加密方向，FIPS-197 纯 Dart 实现）
//
// 支持 128 / 192 / 256 位密钥；weapi 只用到 128。解密方向 weapi 用不上
// （响应是明文 JSON），故不实现，避免无用代码。
// ════════════════════════════════════════════════════════════════

class _AesCbc {
  _AesCbc(Uint8List key)
      : _rounds = _require(key).length ~/ 4 + 6,
        _rk = _expandKey(_require(key));

  static Uint8List _require(Uint8List key) {
    if (key.length != 16 && key.length != 24 && key.length != 32) {
      throw ArgumentError('AES 密钥必须为 16 / 24 / 32 字节，实际 ${key.length}');
    }
    return key;
  }

  final int _rounds;
  final Uint8List _rk;

  /// PKCS#7 填充后逐块 CBC 加密。
  Uint8List encrypt(Uint8List plain, Uint8List iv) {
    if (iv.length != 16) {
      throw ArgumentError('AES-CBC 的 IV 必须是 16 字节，实际 ${iv.length}');
    }
    final int padLen = 16 - (plain.length % 16); // 整块也补一整块
    final Uint8List padded = Uint8List(plain.length + padLen)
      ..setRange(0, plain.length, plain)
      ..fillRange(plain.length, plain.length + padLen, padLen);

    final Uint8List out = Uint8List(padded.length);
    final Uint8List prev = Uint8List.fromList(iv);
    final Uint8List block = Uint8List(16);

    for (int off = 0; off < padded.length; off += 16) {
      for (int j = 0; j < 16; j++) {
        block[j] = padded[off + j] ^ prev[j];
      }
      _encryptBlock(block);
      out.setRange(off, off + 16, block);
      prev.setRange(0, 16, block);
    }
    return out;
  }

  // state 为 16 字节扁平数组，索引 = row + 4 * col（列主序，同 FIPS-197）。
  void _encryptBlock(Uint8List s) {
    _addRoundKey(s, 0);
    for (int r = 1; r < _rounds; r++) {
      _subBytes(s);
      _shiftRows(s);
      _mixColumns(s);
      _addRoundKey(s, r);
    }
    _subBytes(s);
    _shiftRows(s);
    _addRoundKey(s, _rounds);
  }

  void _addRoundKey(Uint8List s, int round) {
    final int base = 16 * round;
    for (int i = 0; i < 16; i++) {
      s[i] ^= _rk[base + i];
    }
  }

  static void _subBytes(Uint8List s) {
    for (int i = 0; i < 16; i++) {
      s[i] = _sbox[s[i]];
    }
  }

  /// 第 r 行整体左移 r 位。
  static void _shiftRows(Uint8List s) {
    final Uint8List t = Uint8List.fromList(s);
    for (int r = 1; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        s[r + 4 * c] = t[r + 4 * ((c + r) & 3)];
      }
    }
  }

  static void _mixColumns(Uint8List s) {
    for (int c = 0; c < 4; c++) {
      final int i = 4 * c;
      final int a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3];
      s[i] = _xtime(a0) ^ (_xtime(a1) ^ a1) ^ a2 ^ a3;
      s[i + 1] = a0 ^ _xtime(a1) ^ (_xtime(a2) ^ a2) ^ a3;
      s[i + 2] = a0 ^ a1 ^ _xtime(a2) ^ (_xtime(a3) ^ a3);
      s[i + 3] = (_xtime(a0) ^ a0) ^ a1 ^ a2 ^ _xtime(a3);
    }
  }

  /// GF(2^8) 乘 2，既约多项式 0x11B。
  static int _xtime(int a) => ((a << 1) & 0xFF) ^ (((a & 0x80) != 0) ? 0x1B : 0);

  /// 通用密钥扩展：Nk = 4/6/8，Nr = Nk + 6。
  static Uint8List _expandKey(Uint8List key) {
    final int nk = key.length ~/ 4;
    final int rounds = nk + 6;
    final int words = 4 * (rounds + 1);
    final Uint8List w = Uint8List(4 * words)..setRange(0, key.length, key);
    final Uint8List temp = Uint8List(4);

    for (int i = nk; i < words; i++) {
      for (int j = 0; j < 4; j++) {
        temp[j] = w[4 * (i - 1) + j];
      }
      if (i % nk == 0) {
        // RotWord + SubWord + Rcon
        final int t = temp[0];
        temp[0] = _sbox[temp[1]];
        temp[1] = _sbox[temp[2]];
        temp[2] = _sbox[temp[3]];
        temp[3] = _sbox[t];
        temp[0] ^= _rcon[i ~/ nk];
      } else if (nk > 6 && i % nk == 4) {
        for (int j = 0; j < 4; j++) {
          temp[j] = _sbox[temp[j]];
        }
      }
      for (int j = 0; j < 4; j++) {
        w[4 * i + j] = w[4 * (i - nk) + j] ^ temp[j];
      }
    }
    return w;
  }
}

/// 轮常量，索引 1..10（AES-128 用到 10 个，192/256 更少）。
const List<int> _rcon = <int>[
  0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36,
];

/// S-box 按定义在运行时生成（GF(2^8) 乘法逆元 + 仿射变换），
/// 避免再抄一份 256 字节魔数表；结果由 FIPS-197 向量校验。
final Uint8List _sbox = _buildSbox();

Uint8List _buildSbox() {
  final Uint8List box = Uint8List(256);
  int p = 1;
  int q = 1;
  do {
    // p *= 3
    p = (p ^ (p << 1) ^ (((p & 0x80) != 0) ? 0x1B : 0)) & 0xFF;
    // q /= 3（等价于 q *= 0xF6），每步按 8 位截断
    q = (q ^ (q << 1)) & 0xFF;
    q = (q ^ (q << 2)) & 0xFF;
    q = (q ^ (q << 4)) & 0xFF;
    if ((q & 0x80) != 0) q ^= 0x09;

    box[p] =
        (q ^ _rotl8(q, 1) ^ _rotl8(q, 2) ^ _rotl8(q, 3) ^ _rotl8(q, 4) ^ 0x63) &
            0xFF;
  } while (p != 1);
  box[0] = 0x63;
  return box;
}

int _rotl8(int x, int shift) => ((x << shift) | (x >> (8 - shift))) & 0xFF;
