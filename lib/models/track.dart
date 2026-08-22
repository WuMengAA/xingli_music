/// 曲目来源
enum TrackSource { local, stream, soundscape }

/// 一首可播放的曲目
class Track {
  final String title;
  final String artist;

  /// 播放地址：本地文件路径 / http(s) URL
  final String uri;

  final TrackSource source;

  /// 归属数据源 id（'local' / 'demo' / subsonic config name / 'radio'）
  final String sourceId;

  /// 直播流（电台）：无时长、无进度、无「下一首单首」语义
  final bool isLiveStream;

  /// 封面 URL（远程源提供，本地可为 null）
  final String? coverUrl;

  /// 专辑名（本地源经系统媒体库读取，远程源可能为 null）
  final String? album;

  /// 曲目时长（本地源从媒体库读取，电台/流可能为 null）
  final Duration? duration;

  /// 本地封面文件路径（扫描时写入应用文档目录缓存，远程源为 null）
  final String? coverPath;

  /// 数据源私有字段（如本地源的 android 媒体库 id、albumId），供懒加载封面等使用
  final Map<String, dynamic>? extras;

  const Track({
    required this.title,
    required this.artist,
    required this.uri,
    this.source = TrackSource.stream,
    this.sourceId = '',
    this.isLiveStream = false,
    this.coverUrl,
    this.album,
    this.duration,
    this.coverPath,
    this.extras,
  });

  /// 本地文件用 setFilePath，网络地址用 setUrl
  bool get isRemote => uri.startsWith('http');

  /// 序列化为 JSON（用于联机点歌等跨端传递）。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'artist': artist,
        'uri': uri,
        'source': source.index,
        'sourceId': sourceId,
        'isLiveStream': isLiveStream,
        'coverUrl': coverUrl,
        'album': album,
        'duration': duration?.inMilliseconds,
        'coverPath': coverPath,
        'extras': extras,
      };

  /// 从 JSON 反序列化（字段缺省回退，保证旧/部分负载不崩）。
  factory Track.fromJson(Map<String, dynamic> j) => Track(
        title: j['title'] as String? ?? '未知曲目',
        artist: j['artist'] as String? ?? '',
        uri: j['uri'] as String? ?? '',
        source: TrackSource.values[(j['source'] as int?) ?? 1],
        sourceId: j['sourceId'] as String? ?? '',
        isLiveStream: j['isLiveStream'] as bool? ?? false,
        coverUrl: j['coverUrl'] as String?,
        album: j['album'] as String?,
        duration: (j['duration'] as int?) != null
            ? Duration(milliseconds: j['duration'] as int)
            : null,
        coverPath: j['coverPath'] as String?,
        extras: j['extras'] as Map<String, dynamic>?,
      );

  Track copyWith({
    String? title,
    String? artist,
    String? uri,
    TrackSource? source,
    String? sourceId,
    bool? isLiveStream,
    String? coverUrl,
    String? album,
    Duration? duration,
    String? coverPath,
    Map<String, dynamic>? extras,
  }) =>
      Track(
        title: title ?? this.title,
        artist: artist ?? this.artist,
        uri: uri ?? this.uri,
        source: source ?? this.source,
        sourceId: sourceId ?? this.sourceId,
        isLiveStream: isLiveStream ?? this.isLiveStream,
        coverUrl: coverUrl ?? this.coverUrl,
        album: album ?? this.album,
        duration: duration ?? this.duration,
        coverPath: coverPath ?? this.coverPath,
        extras: extras ?? this.extras,
      );
}
