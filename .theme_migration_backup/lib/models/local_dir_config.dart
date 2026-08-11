/// 自定义本地目录曲库配置
class LocalDirConfig {
  /// 音乐文件夹绝对路径（桌面：Windows 路径；移动端：设备内路径）
  final String path;

  /// 是否参与曲库聚合
  final bool enabled;

  const LocalDirConfig({required this.path, this.enabled = true});

  LocalDirConfig copyWith({String? path, bool? enabled}) {
    return LocalDirConfig(
      path: path ?? this.path,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {'path': path, 'enabled': enabled};

  factory LocalDirConfig.fromJson(Map<String, dynamic> json) {
    return LocalDirConfig(
      path: json['path'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
