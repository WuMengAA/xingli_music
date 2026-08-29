/// WebDAV 网络音乐库配置（T12）。
class WebDavConfig {
  const WebDavConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.username = '',
    this.password = '',
  });

  /// 唯一 id（sourceId 后缀，时间戳生成）。
  final String id;

  /// 显示名（用户自定义）。
  final String name;

  /// 服务器根地址，如 http://192.168.1.100:5005/dav
  final String baseUrl;

  final String username;
  final String password;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
      };

  factory WebDavConfig.fromJson(Map<String, dynamic> j) => WebDavConfig(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '未命名库',
        baseUrl: j['baseUrl'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
      );

  WebDavConfig copyWith({
    String? name,
    String? baseUrl,
    String? username,
    String? password,
  }) =>
      WebDavConfig(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        username: username ?? this.username,
        password: password ?? this.password,
      );
}