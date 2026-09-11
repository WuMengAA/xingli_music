import 'dart:async';
import 'dart:io';

/// 本地音频文件 PCM / 编码属性探测（纯 Dart，零依赖）。
///
/// 覆盖常见本地曲库格式：WAV / FLAC / MP3 / Opus；其余按扩展名给 codec，
/// 采样率 / 位深 / 码率为 null（面板标注「—」）。用于曲目信息面板，
/// 避免引入额外原生依赖即可读出 Hi-Res 关键参数。
class AudioMeta {
  const AudioMeta(
      {this.sampleRate, this.bitDepth, this.bitrate, this.codec});

  /// 采样率（Hz）。
  final int? sampleRate;

  /// 位深（bits）。
  final int? bitDepth;

  /// 码率（kbps）。
  final int? bitrate;

  /// 编码名（PCM / FLAC / MP3 / Opus …）。
  final String? codec;
}

/// 探测本地音频文件属性；[duration] 用于无损格式按文件大小估算码率。
Future<AudioMeta?> probeAudioFile(String path, {Duration? duration}) async {
  final File f = File(path);
  if (!await f.exists()) return null;
  final List<int> head;
  try {
    head = await f.openRead(0, 200000).first;
  } catch (_) {
    return null;
  }
  if (head.length < 12) return null;
  final String lower = path.toLowerCase();

  if (_tag(head, 0, 'RIFF') && _tag(head, 8, 'WAVE')) {
    final AudioMeta? m = _parseWav(head);
    if (m != null) return m;
  }
  if (_tag(head, 0, 'fLaC')) {
    final AudioMeta? m = _parseFlac(head, f, duration);
    if (m != null) return m;
  }
  if (_tag(head, 0, 'OggS')) {
    final AudioMeta? m = _parseOpus(head);
    if (m != null) return m;
  }
  final AudioMeta? mp3 = _parseMp3(head);
  if (mp3 != null) return mp3;

  // 兜底：仅按扩展名给 codec。
  return AudioMeta(codec: _codecFromExt(lower));
}

bool _tag(List<int> b, int off, String tag) {
  if (off + tag.length > b.length) return false;
  for (int i = 0; i < tag.length; i++) {
    if (b[off + i] != tag.codeUnitAt(i)) return false;
  }
  return true;
}

String _codecFromExt(String lower) {
  if (lower.endsWith('.flac')) return 'FLAC';
  if (lower.endsWith('.wav')) return 'WAV';
  if (lower.endsWith('.mp3')) return 'MP3';
  if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'AAC/M4A';
  if (lower.endsWith('.ogg')) return 'OGG';
  if (lower.endsWith('.opus')) return 'Opus';
  if (lower.endsWith('.wma')) return 'WMA';
  return '未知';
}

int _u16le(List<int> b, int off) =>
    b[off] | (b[off + 1] << 8);

int _u32le(List<int> b, int off) =>
    b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);

int _indexOf(List<int> b, String s) {
  final List<int> pat = s.codeUnits.toList();
  for (int i = 0; i + pat.length <= b.length; i++) {
    bool ok = true;
    for (int j = 0; j < pat.length; j++) {
      if (b[i + j] != pat[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

/// WAV：在 fmt 块读 sampleRate / bitsPerSample / byteRate。
AudioMeta? _parseWav(List<int> b) {
  int off = 12;
  while (off + 8 <= b.length) {
    final String id = String.fromCharCodes(b.sublist(off, off + 4));
    final int size = _u32le(b, off + 4);
    if (id == 'fmt ') {
      if (off + 8 + 16 > b.length) break;
      final int audioFormat = _u16le(b, off + 8);
      final int sampleRate = _u32le(b, off + 8 + 4);
      final int byteRate = _u32le(b, off + 8 + 8);
      final int bits = _u16le(b, off + 8 + 14);
      final int bitrate = (byteRate * 8 / 1000).round();
      final String codec = audioFormat == 1
          ? 'PCM'
          : (audioFormat == 3 ? 'IEEE Float' : 'WAV (fmt $audioFormat)');
      return AudioMeta(
        sampleRate: sampleRate,
        bitDepth: bits,
        bitrate: bitrate,
        codec: codec,
      );
    }
    off += 8 + size + (size & 1); // 块对齐到偶
  }
  return null;
}

/// FLAC：STREAMINFO 块读 sampleRate / bitsPerSample；码率按文件大小估算。
AudioMeta? _parseFlac(List<int> b, File f, Duration? duration) {
  const int off = 4; // 跳过 'fLaC'
  if (off + 4 > b.length) return null;
  final int blockHeader = b[off];
  final int blockType = blockHeader & 0x7F;
  if (blockType != 0) return null; // 首块必为 STREAMINFO
  final int dataOff = off + 4;
  if (dataOff + 10 + 8 > b.length) return null;
  int v = 0;
  for (int i = 0; i < 8; i++) v = (v << 8) | b[dataOff + 10 + i];
  final int sampleRate = (v >> 44) & 0xFFFFF;
  final int bits = ((v >> 36) & 0x1F) + 1;
  int? bitrate;
  if (duration != null && duration.inMilliseconds > 0) {
    try {
      final int size = f.lengthSync();
      bitrate = ((size * 8) / duration.inMilliseconds).round();
    } catch (_) {}
  }
  return AudioMeta(
    sampleRate: sampleRate,
    bitDepth: bits,
    bitrate: bitrate,
    codec: 'FLAC',
  );
}

/// Opus（Ogg）：OpusHead 内 input sample rate（通常 48000）。
AudioMeta? _parseOpus(List<int> b) {
  final int idx = _indexOf(b, 'OpusHead');
  if (idx < 0 || idx + 12 > b.length) return null;
  final int sampleRate = _u32le(b, idx + 8);
  return AudioMeta(
    sampleRate: sampleRate,
    bitDepth: null,
    bitrate: null,
    codec: 'Opus',
  );
}

/// MP3：首个有效帧头解析 MPEG 版本 / 层 / 采样率 / 码率。
AudioMeta? _parseMp3(List<int> b) {
  for (int i = 0; i + 4 < b.length; i++) {
    if (b[i] != 0xFF) continue;
    final int f = b[i + 1];
    if ((f & 0xE0) != 0xE0) continue; // 11 位同步
    final int h = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    if ((h >> 21) != 0x7FF) continue; // 同步校验
    final int version = (h >> 19) & 0x03;
    final int layer = (h >> 17) & 0x03;
    final int bitrateIdx = (h >> 12) & 0x0F;
    final int srIdx = (h >> 10) & 0x03;
    if (layer != 1) continue; // 仅 Layer III
    if (bitrateIdx == 0 || bitrateIdx == 15) continue;
    final List<int> srTable = version == 3
        ? const <int>[44100, 48000, 32000]
        : version == 2
            ? const <int>[22050, 24000, 16000]
            : const <int>[11025, 12000, 8000];
    final List<int> brTable = version == 3
        ? const <int>[
            0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320
          ]
        : const <int>[
            0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160
          ];
    final int sampleRate = srTable[srIdx];
    final int bitrate = brTable[bitrateIdx];
    return AudioMeta(
      sampleRate: sampleRate,
      bitDepth: null,
      bitrate: bitrate,
      codec: 'MP3',
    );
  }
  return null;
}
