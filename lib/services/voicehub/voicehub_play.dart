/// ════════════════════════════════════════════════════════════════════════
/// VoiceHub 播放联动（原生页与网页版共用）
///
/// VoiceHub 的点歌/排期条目只带「平台 + 平台内 id + 可选直链」，要播起来得
/// 按平台转成星璃自己的 [Track] 再交给播放器：
///
/// - 网易云 → `netease://song/<musicId>`（`sourceId: 'netease'`，需网易云登录）
/// - B 站   → `bilibili://video/<bvid>`（`sourceId: 'bilibili'`，需 B 站登录；
///            `musicId` 可能是 `BVxx:cid:page` 复合形式，取首段即 bvid）
/// - 有 `playUrl` → 直链播放（无需任何平台登录）
///
/// 这段逻辑原先只写在 VoiceHub 网页版的 JS 桥回调里；原生页要复用，因此抽到
/// 这里，避免两处各写一份而慢慢走偏。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../providers/sources/netease_provider.dart';
import '../voicehub/voicehub_models.dart';

/// VoiceHub 条目 → 星璃播放器。
abstract final class VoiceHubPlay {
  /// 按平台字段播放一条点歌。
  ///
  /// 返回需要提示给用户的文案；空串表示已成功起播、无需提示。
  static Future<String> playSong(
    WidgetRef ref, {
    required String platform,
    required String musicId,
    String title = '',
    String artist = '',
    String? coverUrl,
    String? playUrl,
    int? durationSeconds,
  }) async {
    final String p = platform.toLowerCase();
    if (p.contains('bilibili') ||
        musicId.startsWith('BV') ||
        musicId.startsWith('av')) {
      if (musicId.isEmpty) return '该条目缺少 B 站视频 id，无法播放';
      if (!ref.read(bilibiliAuthProvider).isLoggedIn) {
        return '播放 B站曲目需先登录哔哩哔哩（设置 → 账号）';
      }
      final String bvid = musicId.split(':').first;
      return _play(
        ref,
        Track(
          title: title,
          artist: artist,
          uri: 'bilibili://video/$bvid',
          source: TrackSource.stream,
          sourceId: 'bilibili',
          coverUrl: coverUrl,
          duration: durationSeconds == null
              ? null
              : Duration(seconds: durationSeconds),
          extras: <String, dynamic>{'bvid': bvid, 'coverUrl': coverUrl},
        ),
      );
    }
    if (p.contains('netease')) {
      if (musicId.isEmpty) return '该条目缺少网易云歌曲 id，无法播放';
      if (!ref.read(neteaseAuthProvider).isLoggedIn) {
        return '播放网易云曲目需先登录网易云（设置 → 账号）';
      }
      return _play(
        ref,
        Track(
          title: title,
          artist: artist,
          uri: 'netease://song/$musicId',
          source: TrackSource.stream,
          sourceId: 'netease',
          coverUrl: coverUrl,
          duration: durationSeconds == null
              ? null
              : Duration(seconds: durationSeconds),
          extras: <String, dynamic>{'coverUrl': coverUrl},
        ),
      );
    }
    // 兜底：后端给了直链就直接播（不依赖任何平台登录）。
    final String? direct = playUrl;
    if (direct != null && direct.isNotEmpty) {
      return _play(
        ref,
        Track(
          title: title,
          artist: artist,
          uri: direct,
          source: TrackSource.stream,
          sourceId: 'voicehub',
          coverUrl: coverUrl,
          duration: durationSeconds == null
              ? null
              : Duration(seconds: durationSeconds),
        ),
      );
    }
    return '暂不支持该平台播放（${platform.isEmpty ? '未知' : platform}）';
  }

  /// 播放一条排期里的歌曲（字段来自 [VoiceHubSchedule]）。
  ///
  /// 注：`schedule.songPlayUrl` 恒为 null——open/schedules 端点的 song 选择
  /// 列不含 playUrl（`schedules.get.ts:77-89`，而 open/songs 的
  /// `songs.get.ts:216` 有）。因此排期里 platform 既非 netease 也非 bilibili
  /// 的歌曲（含 platform 为空）走不到 playSong 的直链兜底分支，会落到
  /// 「暂不支持该平台播放」。要支持需后端在 open/schedules 补 playUrl，
  /// 或客户端按 id 回查 songs 端点补一次——属产品决策，暂不处理。
  static Future<String> playSchedule(
    WidgetRef ref,
    VoiceHubSchedule schedule,
  ) =>
      playSong(
        ref,
        platform: schedule.songPlatform,
        musicId: schedule.songMusicId,
        title: schedule.songTitle,
        artist: schedule.songArtist,
        coverUrl: schedule.songCover,
        playUrl: schedule.songPlayUrl,
        durationSeconds: schedule.songDurationSeconds,
      );

  static Future<String> _play(WidgetRef ref, Track track) =>
      ref.read(playbackActionsProvider).playTrack(track);
}
