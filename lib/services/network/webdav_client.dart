import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:http/http.dart' as http;

/// WebDAV 网络音乐库条目（目录 / 文件）。
class WebDavEntry {
  const WebDavEntry({
    required this.href,
    required this.name,
    required this.isDir,
    this.sizeBytes = 0,
    this.modified,
    this.contentType = '',
  });

  /// PROPFIND 返回的 href（服务器相对路径，如 `/music/song.flac`）。
  final String href;

  /// 显示名（displayname 或 href 末段）。
  final String name;

  final bool isDir;
  final int sizeBytes;
  final DateTime? modified;
  final String contentType;

  bool get isAudio =>
      !isDir &&
      RegExp(r'\.(mp3|flac|m4a|aac|wav|ogg|opus|wma)$', caseSensitive: false)
          .hasMatch(name);

  /// 播放用绝对 URL：baseUrl + href（href 为根相对时补 `/`）。
  String absoluteUrl(String baseUrl) {
    final String b = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    if (href.startsWith('http://') || href.startsWith('https://')) return href;
    final String h = href.startsWith('/') ? href : '/$href';
    return '$b$h';
  }
}

/// WebDAV 操作异常（面向 UI 的中文 message）。
class WebDavException implements Exception {
  WebDavException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 最小 WebDAV 客户端（T12）：Basic 认证 + PROPFIND 目录列举。
/// 播放阶段由 [WebDavSource] 附带 Authorization 头直连流地址。
class WebDavClient {
  WebDavClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// 服务器根地址，如 `http://192.168.1.100:5005/dav`
  final String baseUrl;
  final String username;
  final String password;
  final http.Client _http;

  static const String _ua = 'xingli-music/0.26.8 (local music player)';

  /// 供播放器携带的认证头。
  Map<String, String> get authHeaders => <String, String>{
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        'User-Agent': _ua,
      };

  Map<String, String> get _commonHeaders => <String, String>{
        ...authHeaders,
        'Depth': '1',
      };

  /// 列举 [path]（根为空串）下的条目；失败抛 [WebDavException]。
  Future<List<WebDavEntry>> list(String path) async {
    final String p = path.isEmpty ? '' : '/${path.replaceAll(RegExp(r'^/+'), '')}';
    final Uri uri = Uri.parse('$baseUrl$p');
    final http.Request req = http.Request('PROPFIND', uri)
      ..headers.addAll(_commonHeaders);
    final http.StreamedResponse res;
    try {
      res = await _http.send(req).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw WebDavException('连接失败：$e');
    }
    final String body = await res.stream.bytesToString();
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw WebDavException('认证失败（401/403），请检查用户名与密码');
    }
    if (res.statusCode != 207 && res.statusCode != 200) {
      throw WebDavException('服务器返回 ${res.statusCode}：${_safeStatus(body)}');
    }
    try {
      return _parseMultistatus(body, baseUrl);
    } catch (e) {
      throw WebDavException('无法解析服务器响应：$e');
    }
  }

  static String _safeStatus(String body) {
    final String t = body.trim();
    return t.length > 120 ? '${t.substring(0, 120)}…' : t;
  }
}

/// 分段正则解析 PROPFIND multistatus（容忍任意命名空间前缀）。
final RegExp _respTag = RegExp(
  r'<(?:[A-Za-z0-9_-]*:)?response>([\s\S]*?)</(?:[A-Za-z0-9_-]*:)?response>',
);
final RegExp _hrefTag = RegExp(
  r'<(?:[A-Za-z0-9_-]*:)?href>([\s\S]*?)</(?:[A-Za-z0-9_-]*:)?href>',
);
final RegExp _displayTag = RegExp(
  r'<(?:[A-Za-z0-9_-]*:)?displayname>([\s\S]*?)</(?:[A-Za-z0-9_-]*:)?displayname>',
);
final RegExp _lenTag = RegExp(
  r'<(?:[A-Za-z0-9_-]*:)?getcontentlength>([\s\S]*?)</(?:[A-Za-z0-9_-]*:)?getcontentlength>',
);
final RegExp _typeTag = RegExp(
  r'<(?:[A-Za-z0-9_-]*:)?getcontenttype>([\s\S]*?)</(?:[A-Za-z0-9_-]*:)?getcontenttype>',
);
final RegExp _collTag = RegExp(
  r'<(?:[A-Za-z0-9_-]*:)?collection\s*/?>',
);
final RegExp _mtimeTag = RegExp(
  r'<(?:[A-Za-z0-9_-]*:)?getlastmodified>([\s\S]*?)</(?:[A-Za-z0-9_-]*:)?getlastmodified>',
);

List<WebDavEntry> _parseMultistatus(String xml, String baseUrl) {
  final List<WebDavEntry> out = <WebDavEntry>[];
  for (final RegExpMatch m in _respTag.allMatches(xml)) {
    final String block = m.group(1) ?? '';
    final String href = _decodeXml(_first(block, _hrefTag) ?? '');
    if (href.isEmpty || href.endsWith('/favicon.ico')) continue;

    // 便捷文件名：GET 参数剔除 + 尾段解开
    final String clean = href.split('?').first.replaceAll(
          RegExp(r'/+$'),
          '',
        );
    final String rawName = _decodeXml(_first(block, _displayTag) ?? '');
    final String fallback = Uri.decodeComponent(
      clean.split('/').last.isEmpty ? clean : clean.split('/').last,
    );
    final String name = rawName.isNotEmpty ? rawName : fallback;

    final String lenStr = _first(block, _lenTag) ?? '0';
    final int sizeBytes = int.tryParse(lenStr) ?? 0;
    final String ctype = _first(block, _typeTag) ?? '';
    final bool isDir = _collTag.hasMatch(block) ||
        (clean.isNotEmpty && !clean.split('/').last.contains('.'));
    final DateTime? modified = _parseHttpDate(_first(block, _mtimeTag) ?? '');

    out.add(WebDavEntry(
      href: href,
      name: name,
      isDir: isDir,
      sizeBytes: sizeBytes,
      modified: modified,
      contentType: ctype,
    ));
  }
  return out;
}

String? _first(String block, RegExp re) {
  final RegExpMatch? m = re.firstMatch(block);
  return m?.group(1);
}

String _decodeXml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(
      RegExp(r'&#(x[0-9a-fA-F]+|\d+);'),
      (Match m) {
        final String code = m.group(1)!;
        final int cp = code.startsWith('x')
            ? int.parse(code.substring(1), radix: 16)
            : int.parse(code);
        return String.fromCharCode(cp);
      },
    );

DateTime? _parseHttpDate(String s) {
  if (s.isEmpty) return null;
  final DateTime? a = DateTime.tryParse(s);
  if (a != null) return a;
  try {
    return HttpDate.parse(s);
  } catch (_) {
    return null;
  }
}