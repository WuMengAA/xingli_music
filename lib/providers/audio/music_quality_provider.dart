/// ════════════════════════════════════════════════════════════════════
/// 音乐源音质选择（R26skel-b6）
/// ════════════════════════════════════════════════════════════════════
///
/// - 网易云（音乐源）：标准 / 高 / 无损；「无损」需要网易云 VIP；
/// - 哔哩哔哩（视频源）：自动 / 流畅 / 高清 / 超清 / 4K；超清与 4K 需要
///   B站大会员（自动识别 `vipStatus`）。
///
/// VIP 状态自动识别（登录时从账号接口解析），音质档在音乐面板 / 音乐卡片 /
/// 设置里可改。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sources/bilibili_provider.dart';
import '../sources/netease_provider.dart';

/// 网易云音质档。
enum MusicQuality {
  standard('标准'),
  high('高'),
  lossless('无损');

  const MusicQuality(this.label);

  final String label;
}

/// B站清晰度档（cl54-G1：默认 360p；可选 720 / 1080 / 大会员 1080 60fps）。
enum BiliVideoQuality {
  p360('360p', 16),
  p720('720p', 64),
  p1080('1080p', 80),
  p1080p60('大会员 1080 60fps', 116);

  const BiliVideoQuality(this.label, this.dashId);

  final String label;

  /// B站 DASH 视频流清晰度 id（16=360p / 64=720p / 80=1080p / 116=1080p60）。
  final int dashId;
}

/// 网易云音质档（默认「高」；无损需 VIP）。
final musicQualityProvider =
    StateProvider<MusicQuality>((ref) => MusicQuality.high);

/// B站清晰度档（cl54-G1：默认 360p，节省流量、稳定）。
final biliVideoQualityProvider =
    StateProvider<BiliVideoQuality>((ref) => BiliVideoQuality.p360);

/// 网易云 VIP（自动识别；未登录 false）。
final neteaseVipProvider = Provider<bool>(
    (ref) => ref.watch(neteaseAuthProvider).account?.isVip ?? false);

/// B站大会员（自动识别；未登录 false）。
final bilibiliVipProvider = Provider<bool>(
    (ref) => ref.watch(bilibiliAuthProvider).vip);
