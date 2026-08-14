import 'dart:io';

import 'envelope_analyzer.dart';
import 'music_envelope.dart';

/// 包络磁盘缓存：按「路径 + 大小 + 修改时间」哈希存二进制，跨会话复用，避免重复分析。
///
/// 缓存目录：`<应用文档>/envelopes/<hash>.env`。命中直接解码；未命中调用
/// [EnvelopeAnalyzer] 分析并写回（写回失败不致命）。
class EnvelopeCache {
  EnvelopeCache(this._dir);
  final Directory _dir;

  String _keyFor(String filePath) {
    final FileStat stat = File(filePath).statSync();
    final String raw = '$filePath|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    return raw.hashCode.toRadixString(16);
  }

  File _fileFor(String key) => File('${_dir.path}/envelopes/$key.env');

  /// 取缓存；未命中则分析并写回。抛 [EnvelopeUnavailable]（无 ffmpeg 等）向上传播。
  Future<MusicEnvelope> getOrAnalyze(String filePath,
      {EnvelopeAnalyzer? analyzer}) async {
    final EnvelopeAnalyzer a = analyzer ?? const EnvelopeAnalyzer();
    final String key = _keyFor(filePath);
    final File f = _fileFor(key);
    if (f.existsSync()) {
      final MusicEnvelope? cached = MusicEnvelope.decode(await f.readAsBytes());
      if (cached != null) return cached;
    }
    final MusicEnvelope env = await a.analyze(filePath);
    try {
      await f.create(recursive: true);
      await f.writeAsBytes(env.encode());
    } catch (_) {
      // 缓存写入失败不致命
    }
    return env;
  }
}
