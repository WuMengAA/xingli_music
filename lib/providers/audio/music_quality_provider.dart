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

/// B站清晰度档。
enum BiliVideoQuality {
  auto('自动'),
  smooth('流畅'),
  hd('高清'),
  ultra('超清'),
  uhd4k('4K');

  const BiliVideoQuality(this.label);

  final String label;
}

/// 网易云音质档（默认「高」；无损需 VIP）。
final musicQualityProvider =
    StateProvider<MusicQuality>((ref) => MusicQuality.high);

/// B站清晰度档（默认「自动」= 按登录态取最高可用）。
final biliVideoQualityProvider =
    StateProvider<BiliVideoQuality>((ref) => BiliVideoQuality.auto);

/// 网易云 VIP（自动识别；未登录 false）。
final neteaseVipProvider = Provider<bool>(
    (ref) => ref.watch(neteaseAuthProvider).account?.isVip ?? false);

/// B站大会员（自动识别；未登录 false）。
final bilibiliVipProvider = Provider<bool>(
    (ref) => ref.watch(bilibiliAuthProvider).vip);
