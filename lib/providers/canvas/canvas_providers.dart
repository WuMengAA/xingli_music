// 画布相关状态已迁移为场景索引驱动。
//
// 旧设计（InteractiveViewer + 2D 坐标）：
//   - canvasViewportProvider  → 废弃
//   - activeSceneIdProvider   → 废弃
//
// 新设计（PageView + 场景列表索引）：
//   → providers/scene/scene_providers.dart
//     - currentSceneIndexProvider
//     - activeSceneProvider
//
// 此文件预留：未来画布粒子、光效等仍可能在此扩展。
