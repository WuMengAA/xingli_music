/// 外部流媒体数据源类型
enum SourceType { subsonic, radio }

/// 一个外部连接配置（自建服务器 / 公开电台目录）
///
/// 密码等敏感字段存于 flutter_secure_storage，本对象的其余字段存于
/// shared_preferences。两者通过 [name] 关联。
class ServerConfig {
  final SourceType type;

  /// 配置唯一名（同时作为 sourceId 与本地存储键）
  final String name;

  /// Subsonic：服务器地址，如 http://192.168.1.100:4533
  /// Radio：忽略（用公共 Radio Browser 目录）
  final String baseUrl;

  /// Subsonic：登录用户名
  final String user;

  /// Subsonic：登录密码（明文，运行时由 secure storage 注入）
  final String password;

  /// 是否启用该源参与曲库聚合
  final bool enabled;

  /// 电台筛选标签（ambient / jazz / lo-fi ...），Subsonic 忽略
  final List<String> tags;

  const ServerConfig({
    required this.type,
    required this.name,
    this.baseUrl = '',
    this.user = '',
    this.password = '',
    this.enabled = true,
    this.tags = const ['ambient'],
  });

  ServerConfig copyWith({
    SourceType? type,
    String? name,
    String? baseUrl,
    String? user,
    String? password,
    bool? enabled,
    List<String>? tags,
  }) {
    return ServerConfig(
      type: type ?? this.type,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      user: user ?? this.user,
      password: password ?? this.password,
      enabled: enabled ?? this.enabled,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'name': name,
      'baseUrl': baseUrl,
      'user': user,
      'enabled': enabled,
      'tags': tags,
    };
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      type: SourceType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SourceType.subsonic,
      ),
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String? ?? '',
      user: json['user'] as String? ?? '',
      password: json['password'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      tags: (json['tags'] as List?)?.map((e) => e as String).toList() ??
          const ['ambient'],
    );
  }
}
