import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lyrics/lyrics_view.dart';
import '../../core/utils/app_motion.dart';
import 'unified_player.dart';
import '../../pages/now_playing/now_playing_page.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 独立可复用的「音乐卡」UI（#419）
/// ════════════════════════════════════════════════════════════════════════
///
/// 把原先分散在 [UnifiedPlayer] 调用点的「播放面板 + 内嵌歌词」收敛为一个
/// 自包含组件，供主页场景区、AppShell 底部等多处统一复用。
///
/// ### 为什么独立成卡（用户需求）
/// - **跨页共享播放状态、不重载**：播放状态本就全局化（Riverpod 各类 Provider）
///   + [IndexedStack] 保活，因此切 Tab / 切场景都不会重建播放器。「独立成卡」
///   只是把这套复用约定固化下来，避免每处手写 `UnifiedPlayer(lyricsSlot: ...)`。
/// - **歌词融入音乐卡**：默认把 [LyricsView] 作为 [UnifiedPlayer.lyricsSlot]
///   传入，全屏播放态自动显示、紧凑态自动隐藏（由 [UnifiedPlayer] 控制）。
///
/// ### 不改动 [UnifiedPlayer]（零回归风险）
/// 游戏内 HUD（voxel_world_view3d）仍直接持有 [UnifiedPlayer]，故本卡仅做
/// 轻量包装，不触碰 1219 行的单体组件，游戏内接入完全不受影响。
class MusicCard extends ConsumerWidget {
  const MusicCard({super.key, this.onOpenNowPlaying});

  /// 透传「点击信息区（封面 + 曲名）」回调。
  ///
  /// 默认 null → [MusicCard] 自行 `Navigator.push` 至整页 [NowPlayingPage]
  /// （#549，取代 [UnifiedPlayer] 的透明 Overlay）；传入则优先走外部回调
  /// （兼容游戏内 HUD 等旧接入）。
  final VoidCallback? onOpenNowPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 独立 UI 卡片（R27 原生极简）：**不做任何容器边界装饰**——
    // 去除此前 24dp 圆角裁切与细描边，让 [UnifiedPlayer] 直接浮在场景背景上，
    // 靠留白与排版层级与页面其它内容区分，不引入卡片/边框/玻璃等边界元素。
    // #549：默认点击信息区 → 打开整页播放器（[NowPlayingPage]），而非
    // [UnifiedPlayer] 的透明 Overlay。外部显式传入 onOpenNowPlaying 时仍
    // 走外部回调（兼容游戏内 HUD  & 等旧接入，保持零回归）。
    final VoidCallback openNowPlaying = onOpenNowPlaying ??
        () => Navigator.of(context).push(
              NowPlayingRoute(page: const NowPlayingPage()),
            );
    return UnifiedPlayer(
      onOpenNowPlaying: openNowPlaying,
      // R32 批2：共享元素转场——折叠态封面/曲名作为 Hero 起点。
      heroTag: NpHeroTags.cover,
      // 歌词内嵌：LyricsView 自行跟随 audio_providers 的当前曲目与播放进度。
      lyricsSlot: const LyricsView(),
    );
  }
}
