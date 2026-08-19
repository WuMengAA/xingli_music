import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../lyrics/lyrics_view.dart';
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
    final AppThemeColors c = context.appColors;
    // 独立 UI 卡片：不透明实底 + 细描边 + 轻投影（低特效）。
    // 内部紧凑面板本就是 transparent 毛玻璃，透出本容器实色后不再有玻璃
    // 扭曲观感；播放控制与歌词逻辑完全保留（不改动 UnifiedPlayer）。
    // #549：默认点击信息区 → 打开整页播放器（[NowPlayingPage]），而非
    // [UnifiedPlayer] 的透明 Overlay。外部显式传入 onOpenNowPlaying 时仍
    // 走外部回调（兼容游戏内 HUD 等旧接入，保持零回归）。
    final VoidCallback openNowPlaying = onOpenNowPlaying ??
        () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NowPlayingPage(),
              ),
            );
    // 独立 UI 卡片：**透明背景**（无 c.bgSurface 实底白），透出下层
    // ContentContainer 的 frosted 玻璃（全 Tab 常驻在玻璃容器上）。
    // 仅保留细描边 + 圆角界定卡片范围；内部 UnifiedPlayer 紧凑面板自带
    // 极淡 tint 玻璃，叠加后无白底、无重影。播放控制与歌词逻辑完全保留。
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: c.border.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: UnifiedPlayer(
          onOpenNowPlaying: openNowPlaying,
          // 歌词内嵌：LyricsView 自行跟随 audio_providers 的当前曲目与播放进度。
          lyricsSlot: const LyricsView(),
        ),
      ),
    );
  }
}
