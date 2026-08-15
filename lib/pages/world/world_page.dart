/// 世界 Tab · 星璃世界入口（体素世界主菜单）。
///
/// 复用 [VoxelMainMenuPage]：世界存档 / 开放世界 / 游戏设置。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../voxel/voxel_main_menu_page.dart';

/// 世界页（底部 Dock「世界」Tab）。
class WorldPage extends ConsumerWidget {
  const WorldPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const VoxelMainMenuPage();
  }
}
