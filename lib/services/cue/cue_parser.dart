/// CUE 分轨解析器（纯 Dart，零依赖）。
///
/// 解析常见 CD 整轨 CUE 文件，产出 [CueSheet]：
/// - `FILE "xxx.flac" WAVE` → 关联音频文件
/// - `TRACK 01 AUDIO` → 曲目骨架
/// - `TITLE / PERFORMER`（TRACK 内 → 轨级；外 → 专辑级）
/// - `INDEX 00 mm:ss:ff` → 前奏起点（pregap，通常不播）
/// - `INDEX 01 mm:ss:ff` → 曲目实际起点
///
/// 时间格式 `mins:secs:frames`（75 帧/秒）→ [Duration]。
/// 分轨起止毫秒由 [CueSheet.withEnds] 按「下一轨起点」推导。
library;

/// 单曲目。
class CueTrack {
  CueTrack({required this.number});

  /// 轨号（1 起）。
  final int number;

  String title = '';
  String performer = '';

  /// INDEX 01 起点；缺失时为 null。
  Duration? start;

  /// INDEX 00 前奏起点；缺失时为 null。
  Duration? pregap;

  /// 所属音频文件（`FILE` 行路径）；缺失时为 null。
  String? file;

  /// 结束点（下一轨起点）；由 [CueSheet.withEnds] 填充（最后轨为 null）。
  Duration? end;

  /// 结束毫秒（null 表示未知/整轨尾）。
  int? get endMs => end?.inMilliseconds;

  /// 起始毫秒（无起点默认 0）。
  int get startMs => start?.inMilliseconds ?? 0;
}

/// 整张 CUE 表。
class CueSheet {
  CueSheet({required this.sourceText});

  final String sourceText;

  /// 专辑级艺术家 / 专辑名（TRACK 外出现），轨级缺省时回退。
  String albumPerformer = '';
  String albumTitle = '';

  /// FILE 行按出现顺序。
  final List<String> files = <String>[];

  final List<CueTrack> tracks = <CueTrack>[];

  /// 按下一轨起点推导每轨 [CueTrack.end]。
  CueSheet withEnds() {
    for (int i = 0; i < tracks.length - 1; i++) {
      final Duration? next = tracks[i + 1].start;
      if (next != null) tracks[i].end = next;
    }
    return this;
  }
}

/// 解析 CUE 文本；失败返回 null（非容错输入）。
CueSheet? parseCue(String content) {
  if (content.trim().isEmpty) return null;
  final CueSheet sheet = CueSheet(sourceText: content);
  CueTrack? current;

  for (final String raw in content.split('\n')) {
    final String line = raw.trim();
    if (line.isEmpty || line.startsWith('REM')) continue;
    final List<String> parts = _tokenize(line);
    if (parts.isEmpty) continue;
    final String kw = parts[0].toUpperCase();
    switch (kw) {
      case 'PERFORMER':
        final String? v = _quoted(line);
        if (current != null && v != null) {
          current.performer = v;
        } else if (v != null) {
          sheet.albumPerformer = v;
        }
        break;
      case 'TITLE':
        final String? v = _quoted(line);
        if (current != null && v != null && current.title.isEmpty) {
          current.title = v;
        } else if (v != null) {
          sheet.albumTitle = v;
        }
        break;
      case 'FILE':
        final String? v = _quoted(line);
        if (v != null) sheet.files.add(v);
        break;
      case 'TRACK':
        final int? num = parts.length > 1 ? int.tryParse(parts[1]) : null;
        current = CueTrack(number: num ?? (sheet.tracks.length + 1));
        sheet.tracks.add(current);
        break;
      case 'INDEX':
        if (current == null) break;
        if (parts.length < 3) break;
        final Duration? t = _parseTime(parts[2]);
        if (t == null) break;
        if (parts[1] == '00' && current.pregap == null) {
          current.pregap = t;
        } else if (parts[1] == '01' && current.start == null) {
          current.start = t;
        }
        break;
    }
  }

  // 轨级缺省回退专辑级。
  for (final CueTrack t in sheet.tracks) {
    if (t.title.isEmpty) t.title = sheet.albumTitle;
    if (t.performer.isEmpty) t.performer = sheet.albumPerformer;
    // FILE 归属：按轨顺序寻找非空
    if (t.file == null && sheet.files.isNotEmpty) {
      t.file = sheet.files.first;
    }
  }
  if (sheet.tracks.isEmpty) return null;
  return sheet.withEnds();
}

/// 提取行内第一个引号内容（`"..."` 或 `'...'`）。
String? _quoted(String line) {
  final int a = line.indexOf('"');
  final int b = line.indexOf('"', a + 1);
  if (a >= 0 && b > a) return line.substring(a + 1, b);
  final int c = line.indexOf("'");
  final int d = line.indexOf("'", c + 1);
  if (c >= 0 && d > c) return line.substring(c + 1, d);
  return null;
}

/// 拆空白 token（兼容多个连续空格 / tab）。
List<String> _tokenize(String line) {
  final List<String> out = <String>[];
  line
      .split(RegExp(r'\s+'))
      .where((String s) => s.isNotEmpty)
      .forEach(out.add);
  return out;
}

/// `mm:ss:ff` → Duration（ff 为 75 帧/秒）。
Duration? _parseTime(String s) {
  final RegExpMatch? m = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})$').firstMatch(s);
  if (m == null) return null;
  final int mins = int.parse(m.group(1)!);
  final int secs = int.parse(m.group(2)!);
  final int frames = int.parse(m.group(3)!);
  final int ms =
      ((mins * 60 + secs) * 1000) + ((frames * 1000) / 75).round();
  return Duration(milliseconds: ms);
}