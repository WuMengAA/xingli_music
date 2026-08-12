/// R26p2：云层区块视距共享 Provider（区块数）。
///
/// 独立于地形视距（viewDistanceChunksProvider）——云场以相机为中心重定心，
/// 覆盖半径 = 区块数 × 16 格。默认 3 区块 = 48 格半径（与渲染端 cloudY=64
/// 高度云场默认一致）。首页「游戏画面」页直接写此 Provider，天然联动。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 云层区块视距：区块数。默认 3 区块 = 48 格半径。
///
/// 范围约束在 UI 端做（1~8 区块）；渲染端按 [RenderConfig.cloudViewDistanceChunks]
/// 直接消费。数值越大云铺得越远、云胞越多（性能随半径平方增长）。
final cloudViewDistanceProvider = StateProvider<int>((ref) => 3);
