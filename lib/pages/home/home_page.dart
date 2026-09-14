/// 主页 · 合并原场景页内容（场景卡堆 + 操作条 + 音乐卡）。
///
/// 去掉独立「场景页」路由后，场景内容作为主页直接呈现（R26skel）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/playback/home_player_view.dart';

/// 主页（底部 Dock「主页」Tab，默认页）。
///
/// 2026-09-14 重构：主页主体改为沉浸播放器 [HomeImmersivePlayer]
/// （封面背景 + 唱片封面 + 歌词 + 完整控制栏）；场景选择降级为右上角入口。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const HomeImmersivePlayer();
  }
}
