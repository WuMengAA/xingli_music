import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../lyrics/lyrics_view.dart';
import 'unified_player.dart';

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
  /// 默认 null → 由 [UnifiedPlayer] 打开全屏播放卡片（R23j）；
  /// 传入则优先走外部回调（兼容旧接入）。
  final VoidCallback? onOpenNowPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    // 独立 UI 卡片：不透明实底 + 细描边 + 轻投影（低特效）。
    // 内部紧凑面板本就是 transparent 毛玻璃，透出本容器实色后不再有玻璃
    // 扭曲观感；播放控制与歌词逻辑完全保留（不改动 UnifiedPlayer）。
    return Container(
      // 仅保留实底 + 细描边，移除背景外的额外遮罩（scrim 投影）。
      // 背景（bgSurface）保留，符合「不要背景外的遮罩、不是不要背景」的要求。
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: c.border.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: UnifiedPlayer(
          onOpenNowPlaying: onOpenNowPlaying,
          // 歌词内嵌：LyricsView 自行跟随 audio_providers 的当前曲目与播放进度。
          lyricsSlot: const LyricsView(),
        ),
      ),
    );
  }
}
