/// 星璃 · 本地密钥安全存储（P-3）
///
/// 目标：让「网易云 cookie」这类长期凭据**不再明文落盘**。
///
/// 方案：AES-256-CBC + HMAC-SHA256（Encrypt-then-MAC），密钥由
/// PBKDF2-HMAC-SHA256（每安装随机盐 + 设备稳定标识）派生，密文以
/// base64 存进 SharedPreferences。
///
/// ─────────────────────────────────────────────────────────────
/// ⚠ 安全边界（必读，勿高估本模块）
///
/// 本模块提供的是**静态数据混淆级**保护，不是密钥托管：
///   - 盐存在 SharedPreferences，设备标识可被同机进程推导，因此**能读到
///     prefs 文件的攻击者理论上可重新派生出密钥**。它挡的是「拿到备份/
///     导出的 prefs 就直接看见 cookie 明文」，挡不住已取得同等运行权限
///     的攻击者（root / 越狱 / 恶意同机应用）。
///   - 真正的密钥保护需落到平台安全区（Android Keystore / iOS Keychain，
///     即 `flutter_secure_storage`）。本工程当前约束为「不新增依赖」，
///     故先以纯 Dart 方案兜底；[SecureBox.deviceSeed] 已预留注入点，
///     将来接入 Keystore 派生的设备密钥即可平滑升级。
///   - AES 为本工程自实现（`crypto` 包只提供哈希，不含分组密码）。
///     实现已用 FIPS-197 官方测试向量校验（见 test/security/），但
///     **自实现密码学天然弱于经审计的库**，条件允许时应换 `cryptography`
///     / `encrypt` 包或平台原生实现。
/// ─────────────────────────────────────────────────────────────
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════════════════════════
// 对外 API
// ════════════════════════════════════════════════════════════════

/// 本地加密保险箱。
///
/// 典型用法：
/// ```dart
/// final box = SecureBox();
/// await box.writeSecret('netease.cookie', rawCookie); // 自动加密后落盘
/// final String? cookie = await box.readSecret('netease.cookie');
/// ```
///
/// 也可只用纯加解密（自行决定存哪）：
/// ```dart
/// final String armored = await box.encrypt(rawCookie);
/// final String? back = await box.decrypt(armored); // 失败/被篡改返回 null
/// ```
class SecureBox {
  /// [prefs] 可注入（测试用）；不传则懒加载全局实例。
  ///
  /// [deviceSeed] 为设备稳定标识，参与密钥派生。默认用平台名 —— 刻意选了
  /// 一个**跨系统升级不变**的值：若混入 OS 版本号，用户升级系统后旧密文
  /// 将永久无法解密。将来若接入 Keystore/Keychain，把设备密钥从这里注入。
  SecureBox({SharedPreferences? prefs, String? deviceSeed})
      : _prefs = prefs,
        deviceSeed = deviceSeed ?? _defaultDeviceSeed();

  /// 参与密钥派生的设备标识（见构造函数说明）。
  final String deviceSeed;

  SharedPreferences? _prefs;

  /// per-install 随机盐的 prefs key（盐本身明文无碍，密钥不落盘）。
  static const String kSaltKey = 'sec.salt';

  /// 密文条目的 key 前缀（便于识别/整体清除）。
  static const String kSecretPrefix = 'sec.v1.';

  /// 信封版本号：第 1 字节，为将来换算法留升级位。
  static const int _envelopeVersion = 1;

  /// PBKDF2 迭代次数。纯 Dart 实现，取值兼顾低端机冷启动耗时与暴力破解成本；
  /// 派生结果在内存缓存，一个进程内只算一次。
  static const int kPbkdf2Iterations = 30000;

  static const int _saltLen = 16;
  static const int _ivLen = 16;
  static const int _macLen = 32;

  /// 派生出的子密钥（内存缓存，**绝不落盘**）。
  Uint8List? _encKey;
  Uint8List? _macKey;

  static String _defaultDeviceSeed() =>
      'xingli.secure.v1|${defaultTargetPlatform.name}';

  Future<SharedPreferences> _sp() async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ── 加解密 ────────────────────────────────────────

  /// 加密明文，返回 base64 信封串。
  ///
  /// 信封布局：`version(1) || iv(16) || ciphertext || hmac-sha256(32)`，
  /// MAC 覆盖前三段（Encrypt-then-MAC：先验 MAC 再解密，天然免疫
  /// CBC padding oracle）。每次加密用全新随机 IV，故同一明文两次加密
  /// 结果不同 —— 这是正确行为，不要据此判断"加密失效"。
  Future<String> encrypt(String plain) async {
    await _ensureKeys();
    final Uint8List iv = _randomBytes(_ivLen);
    final Uint8List ct =
        _AesCbc(_encKey!).encrypt(Uint8List.fromList(utf8.encode(plain)), iv);

    final Uint8List head = Uint8List(1 + _ivLen + ct.length)
      ..[0] = _envelopeVersion
      ..setRange(1, 1 + _ivLen, iv)
      ..setRange(1 + _ivLen, 1 + _ivLen + ct.length, ct);

    final Uint8List mac =
        Uint8List.fromList(Hmac(sha256, _macKey!).convert(head).bytes);

    final Uint8List envelope = Uint8List(head.length + _macLen)
      ..setRange(0, head.length, head)
      ..setRange(head.length, head.length + _macLen, mac);

    return base64Encode(envelope);
  }

  /// 解密 base64 信封串。
  ///
  /// 任何异常情况（格式错误、MAC 不匹配即被篡改、密钥不对、padding 非法）
  /// 一律返回 `null`，不抛异常也不区分原因 —— 不给攻击者任何区分信号。
  Future<String?> decrypt(String cipher) async {
    await _ensureKeys();
    try {
      final Uint8List env = base64Decode(cipher);
      if (env.length < 1 + _ivLen + 16 + _macLen) return null;
      if (env[0] != _envelopeVersion) return null;

      final int headLen = env.length - _macLen;
      final Uint8List head = Uint8List.sublistView(env, 0, headLen);
      final Uint8List mac = Uint8List.sublistView(env, headLen);

      final List<int> expect = Hmac(sha256, _macKey!).convert(head).bytes;
      if (!_constantTimeEquals(mac, expect)) return null;

      final Uint8List iv = Uint8List.sublistView(head, 1, 1 + _ivLen);
      final Uint8List ct = Uint8List.sublistView(head, 1 + _ivLen);
      final Uint8List? plain = _AesCbc(_encKey!).decrypt(ct, iv);
      if (plain == null) return null;
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  // ── 落盘读写 ──────────────────────────────────────

  /// 加密并写入 SharedPreferences（明文永不进入 prefs）。
  Future<void> writeSecret(String key, String value) async {
    final String armored = await encrypt(value);
    await (await _sp()).setString('$kSecretPrefix$key', armored);
  }

  /// 读取并解密。不存在 / 已损坏 / 被篡改均返回 `null`。
  Future<String?> readSecret(String key) async {
    final String? armored = (await _sp()).getString('$kSecretPrefix$key');
    if (armored == null) return null;
    return decrypt(armored);
  }

  /// 删除某条密文（退出登录 / 解绑账号时调用）。
  Future<void> deleteSecret(String key) async {
    await (await _sp()).remove('$kSecretPrefix$key');
  }

  // ── 密钥派生 ──────────────────────────────────────

  /// 派生并缓存 enc / mac 双子密钥。
  ///
  /// 步骤：
  ///   1. 取（或首次生成）per-install 16 字节随机盐，存 prefs；
  ///   2. `master = PBKDF2-HMAC-SHA256(deviceSeed, salt, 30000, 32)`；
  ///   3. 由 master 用不同 info 串 HMAC 出两把独立子密钥
  ///      （加密与认证绝不复用同一把密钥）。
  Future<void> _ensureKeys() async {
    if (_encKey != null && _macKey != null) return;

    final SharedPreferences sp = await _sp();
    Uint8List salt;
    final String? stored = sp.getString(kSaltKey);
    if (stored == null) {
      salt = _randomBytes(_saltLen);
      await sp.setString(kSaltKey, base64Encode(salt));
    } else {
      try {
        salt = base64Decode(stored);
        if (salt.length != _saltLen) throw const FormatException('bad salt');
      } catch (_) {
        // 盐损坏：重建。旧密文将无法解密（读取时返回 null，调用方按
        // 「凭据失效、请重新登录」处理即可）。
        salt = _randomBytes(_saltLen);
        await sp.setString(kSaltKey, base64Encode(salt));
      }
    }

    final Uint8List master = _pbkdf2Sha256(
      Uint8List.fromList(utf8.encode(deviceSeed)),
      salt,
      kPbkdf2Iterations,
      32,
    );
    _encKey = Uint8List.fromList(
        Hmac(sha256, master).convert(utf8.encode('xingli.enc.v1')).bytes);
    _macKey = Uint8List.fromList(
        Hmac(sha256, master).convert(utf8.encode('xingli.mac.v1')).bytes);
  }

  // ── 接入钩子：网易云 cookie（示例，非真实实现）────
  //
  // 未来 `neteaseCookieProvider` 拿到登录 cookie 后，不要直接 setString，
  // 改走本保险箱：
  //
  //   await SecureBox().writeSecret('netease.cookie', rawCookie);
  //   final String? cookie = await SecureBox().readSecret('netease.cookie');
  //
  // 退出登录：`await SecureBox().deleteSecret('netease.cookie');`
  // 另注意：cookie 拼进请求 URL 后一律不得直接进日志，
  // 需经 `AudioService._redact` / `LogService.redact`（见 P-1）。

  /// 网易云 cookie 的约定 key（供未来 provider 复用，避免各处硬编码字符串）。
  static const String kNeteaseCookie = 'netease.cookie';

  /// 第三方大模型 API Key 的约定 key（用户自配，AES-256 加密落盘）。
  static const String kLlmApiKey = 'llm.apiKey';
}

// ════════════════════════════════════════════════════════════════
// 测试钩子
// ════════════════════════════════════════════════════════════════

/// 仅供测试：对**单个分组**跑裸 AES-256（等价 ECB），用于校验底层实现
/// 是否符合 FIPS-197 官方测试向量。
///
/// 生产代码禁止调用 —— 裸 ECB 无 IV 无 MAC，任何实际用途都应走 [SecureBox]。
@visibleForTesting
String aesEcbBlockHexForTest({required String keyHex, required String plainHex}) {
  final Uint8List key = _hexToBytes(keyHex);
  final Uint8List block = _hexToBytes(plainHex);
  if (block.length != 16) {
    throw ArgumentError('AES 分组必须是 16 字节');
  }
  // 用全零 IV 的 CBC 加密单块 == 该块的裸 AES 加密（首块 XOR 0）。
  // CBC 会补一整块 PKCS#7，只取前 16 字节即为裸密文。
  final Uint8List out = _AesCbc(key).encrypt(block, Uint8List(16));
  return _bytesToHex(Uint8List.sublistView(out, 0, 16));
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
// PBKDF2-HMAC-SHA256
// ════════════════════════════════════════════════════════════════

/// RFC 2898 PBKDF2，PRF = HMAC-SHA256。
Uint8List _pbkdf2Sha256(
    Uint8List password, Uint8List salt, int iterations, int dkLen) {
  final Hmac prf = Hmac(sha256, password);
  final Uint8List out = Uint8List(dkLen);
  final int blocks = (dkLen + 31) ~/ 32;
  int offset = 0;

  for (int i = 1; i <= blocks; i++) {
    // U1 = PRF(P, S || INT_32_BE(i))
    final Uint8List seed = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..[salt.length] = (i >> 24) & 0xFF
      ..[salt.length + 1] = (i >> 16) & 0xFF
      ..[salt.length + 2] = (i >> 8) & 0xFF
      ..[salt.length + 3] = i & 0xFF;

    Uint8List u = Uint8List.fromList(prf.convert(seed).bytes);
    final Uint8List t = Uint8List.fromList(u);
    for (int c = 1; c < iterations; c++) {
      u = Uint8List.fromList(prf.convert(u).bytes);
      for (int j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    final int take = (dkLen - offset) < 32 ? (dkLen - offset) : 32;
    out.setRange(offset, offset + take, t);
    offset += take;
  }
  return out;
}

/// 定时安全比较：耗时与内容无关，避免 MAC 校验被计时侧信道爆破。
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  int diff = 0;
  for (int i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

final Random _secureRandom = Random.secure();

Uint8List _randomBytes(int n) {
  final Uint8List b = Uint8List(n);
  for (int i = 0; i < n; i++) {
    b[i] = _secureRandom.nextInt(256);
  }
  return b;
}

// ════════════════════════════════════════════════════════════════
// AES-256 / CBC（FIPS-197 纯 Dart 实现）
//
// `crypto` 包只提供哈希（sha/md5/hmac），不含分组密码，故此处自实现。
// 已用 FIPS-197 附录 C.3 官方向量校验，见 test/security/secure_store_test.dart。
// ════════════════════════════════════════════════════════════════

/// AES-256-CBC + PKCS#7 填充。
///
/// 仅供本文件使用；对外统一走 [SecureBox]（后者才有 MAC 保护，
/// 裸 CBC 无完整性校验，绝不能单独用于存储不可信数据）。
class _AesCbc {
  _AesCbc(Uint8List key) : _rk = _expandKey256(_require256(key));

  static Uint8List _require256(Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError('AES-256 需要 32 字节密钥，实际 ${key.length}');
    }
    return key;
  }

  /// 展开后的轮密钥（240 字节 = 4 字节 × 4 列 × 15 轮）。
  final Uint8List _rk;

  static const int _rounds = 14;

  Uint8List encrypt(Uint8List plain, Uint8List iv) {
    final int padLen = 16 - (plain.length % 16); // PKCS#7：整块也补一整块
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

  /// 解密。长度非法或 PKCS#7 填充不合法返回 `null`。
  Uint8List? decrypt(Uint8List cipher, Uint8List iv) {
    if (cipher.isEmpty || cipher.length % 16 != 0) return null;

    final Uint8List out = Uint8List(cipher.length);
    final Uint8List prev = Uint8List.fromList(iv);
    final Uint8List block = Uint8List(16);

    for (int off = 0; off < cipher.length; off += 16) {
      block.setRange(0, 16, cipher, off);
      _decryptBlock(block);
      for (int j = 0; j < 16; j++) {
        out[off + j] = block[j] ^ prev[j];
      }
      prev.setRange(0, 16, cipher, off);
    }

    final int padLen = out[out.length - 1];
    if (padLen < 1 || padLen > 16 || padLen > out.length) return null;
    for (int i = out.length - padLen; i < out.length; i++) {
      if (out[i] != padLen) return null;
    }
    return Uint8List.sublistView(out, 0, out.length - padLen);
  }

  // ── 分组变换 ──────────────────────────────────────
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

  void _decryptBlock(Uint8List s) {
    _addRoundKey(s, _rounds);
    for (int r = _rounds - 1; r >= 1; r--) {
      _invShiftRows(s);
      _invSubBytes(s);
      _addRoundKey(s, r);
      _invMixColumns(s);
    }
    _invShiftRows(s);
    _invSubBytes(s);
    _addRoundKey(s, 0);
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

  static void _invSubBytes(Uint8List s) {
    for (int i = 0; i < 16; i++) {
      s[i] = _invSbox[s[i]];
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

  /// 第 r 行整体右移 r 位。
  static void _invShiftRows(Uint8List s) {
    final Uint8List t = Uint8List.fromList(s);
    for (int r = 1; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        s[r + 4 * ((c + r) & 3)] = t[r + 4 * c];
      }
    }
  }

  static void _mixColumns(Uint8List s) {
    for (int c = 0; c < 4; c++) {
      final int i = 4 * c;
      final int a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3];
      s[i] = _gmul(a0, 2) ^ _gmul(a1, 3) ^ a2 ^ a3;
      s[i + 1] = a0 ^ _gmul(a1, 2) ^ _gmul(a2, 3) ^ a3;
      s[i + 2] = a0 ^ a1 ^ _gmul(a2, 2) ^ _gmul(a3, 3);
      s[i + 3] = _gmul(a0, 3) ^ a1 ^ a2 ^ _gmul(a3, 2);
    }
  }

  static void _invMixColumns(Uint8List s) {
    for (int c = 0; c < 4; c++) {
      final int i = 4 * c;
      final int a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3];
      s[i] = _gmul(a0, 14) ^ _gmul(a1, 11) ^ _gmul(a2, 13) ^ _gmul(a3, 9);
      s[i + 1] = _gmul(a0, 9) ^ _gmul(a1, 14) ^ _gmul(a2, 11) ^ _gmul(a3, 13);
      s[i + 2] = _gmul(a0, 13) ^ _gmul(a1, 9) ^ _gmul(a2, 14) ^ _gmul(a3, 11);
      s[i + 3] = _gmul(a0, 11) ^ _gmul(a1, 13) ^ _gmul(a2, 9) ^ _gmul(a3, 14);
    }
  }

  /// GF(2^8) 乘法，既约多项式 0x11B。
  static int _gmul(int a, int b) {
    int p = 0;
    int x = a;
    int y = b;
    for (int i = 0; i < 8; i++) {
      if ((y & 1) != 0) p ^= x;
      final bool hi = (x & 0x80) != 0;
      x = (x << 1) & 0xFF;
      if (hi) x ^= 0x1B;
      y >>= 1;
    }
    return p & 0xFF;
  }

  /// AES-256 密钥扩展：Nk=8, Nr=14 → 60 个字（240 字节）。
  static Uint8List _expandKey256(Uint8List key) {
    const int nk = 8;
    const int words = 4 * (_rounds + 1); // 60
    final Uint8List w = Uint8List(4 * words)..setRange(0, 32, key);
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
      } else if (i % nk == 4) {
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

/// 轮常量，索引 1..7（AES-256 只用到 7 个）。
const List<int> _rcon = <int>[
  0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40,
];

const List<int> _sbox = <int>[
  0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, //
  0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
  0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0,
  0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
  0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc,
  0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
  0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a,
  0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
  0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0,
  0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
  0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b,
  0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
  0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85,
  0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
  0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5,
  0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
  0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17,
  0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
  0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88,
  0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
  0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c,
  0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
  0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9,
  0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
  0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6,
  0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
  0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e,
  0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
  0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94,
  0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
  0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68,
  0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
];

const List<int> _invSbox = <int>[
  0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, //
  0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
  0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87,
  0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
  0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d,
  0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
  0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2,
  0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
  0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16,
  0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
  0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda,
  0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
  0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a,
  0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
  0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02,
  0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
  0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea,
  0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
  0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85,
  0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
  0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89,
  0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
  0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20,
  0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
  0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31,
  0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
  0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d,
  0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
  0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0,
  0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
  0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26,
  0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d,
];
