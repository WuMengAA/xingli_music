/// R26i：可见度（视距，区块数）共享 Provider。
///
/// 独立于画质档——用户希望「可见度多少区块」单独可调（默认 4 区块 = 64 格），
/// 与画质（流畅/标准/高清）解耦。3D 视图 `ref.listen` 同步 [_config]，
/// 设置弹层 / 折叠面板直接写此 Provider，天然联动。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 可见度（视距）档位：区块数。默认 4 区块 = 64×64 格。
///
/// 范围约束在 UI 端做（2~10 区块）；渲染端按 [RenderConfig.viewDistanceChunks]
/// 直接消费。数值越大看到越远、面数越多（预算随视距线性扩容）。
final viewDistanceProvider = StateProvider<int>((ref) => 4);
