/// 主页 · 合并原场景页内容（场景卡堆 + 操作条 + 音乐卡）。
///
/// 去掉独立「场景页」路由后，场景内容作为主页直接呈现（R26skel）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../scene/scene_page.dart';

/// 主页（底部 Dock「主页」Tab，默认页）。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const HomeSceneContent();
  }
}
