# 星璃音乐 voxel LOD 改进 —— 详细设计（R26r18 提案）

> 范围：仅 `lib/widgets/voxel/voxel_renderer.dart`（`_emitLodPass` / `_buildLodCell` / `_emitLodCell` / `_LodCell` / `RenderConfig` / `VoxelChunkCache`）+ 设置页。
> 不动 `buildFrame` 满精度带（用户要求「渲染视线内所有区块」保留正方形满精度方阵）。
> 状态：**设计稿，未实现、未改码、未构建。**

---

## 0. 现状速记（基线）

- 满精度带：`kFullBand=2`（5×5 区块，`step=1`）。
- LOD 带1：每区块 3×3 单元，`size=chunk/3≈5.33`，`step=5.33` → **每单元仅 1 列采样**（`_buildLodCell` 循环只跑一次）。
- LOD 带2：每区块 1 大块，`size=16`。
- `_emitLodPass` **跳过视锥/背面剔除**（注释称「单元少」）。
- `_LodCell{topY, majority, nTop, eTop, sTop, wTop}`，缓存 `(band,ci,cj)` 上限 64。
- `lodEnabled` 二元：`false` → 全方阵满精度；`true` → 当前两档。

---

## P3 · LOD 通道视锥剔除（推荐首发，纯性能、零风险）

**目标**：第一/三人称下丢弃相机后半球 LOD 单元，面数约减半。

**新增函数**：
```dart
// 复用 _chunkInFrustum 思路，参数化任意 size/topY（替代写死的 chunk/maxY）。
static bool _cellInFrustum(
  ViewBasis b, ProjectionParams proj,
  double x0, double z0, double size, double topY,
) {
  // 8 角 (x0/x1 × z0/z1 × 0/topY) 各 projectWith；任一角非 null → 保留。
}
```

**改动点**（`_emitLodPass` 内层 `for ci/for cj` 起始）：
```dart
if (config.lodFrustumCull && !camera.fullWidth) {
  if (!_cellInFrustum(b, proj, cx0, cz0, size, cell.topY)) continue;
}
```
> 注意：`_emitLodQuad` 内部 `projectWith` 返回 null 已天然丢弃相机后面，故背面剔除仍在线；此处只做**区块级粗剔除**省掉整单元投影。

**性能**：每帧 ~（2·maxDist/size)² 单元 × 8 次 `projectWith`。vd=4、maxDist≈76：带2(size16)≈90 单元、带1(size5.33)≈810 单元 → ~7.2k 次廉价投影/帧，可忽略。
**收益**：FP/TP 下 LOD 面数约减半 → `maxFaces` 预算更易满足 → 远端 `_trimFarthest` 丢弃更少 → popping 减轻。
**配置**：新增 `RenderConfig.lodFrustumCull`（默认 `true`）。

---

## P1 · 多档细 LOD + 迟滞（最大视觉提升）

**目标**：把 2 档离散降级换成连续多档，去「32~80 格外变平板」断崖；移动不闪烁。

**档位表**（由 `viewDistanceChunks` 推导，可配置）：
```dart
// base=4 格，逐档翻倍；ringStart/End 为距相机区块中心距离（格）。
final List<_LodTier> tiers = [
  _LodTier(cell: 4,  ring0: 32, ring1: 48),
  _LodTier(cell: 8,  ring0: 48, ring1: 64),
  _LodTier(cell: 16, ring0: 64, ring1: 96),
  _LodTier(cell: 32, ring0: 96, ring1: maxDist),
];
class _LodTier { final double cell, ring0, ring1; }
```

**`_buildLodCell` 改签名**（加 `subdiv` 超采样）：
```dart
static _LodCell _buildLodCell(
  VoxelWorld world, double cx0, double cz0,
  double size, double step, int subdiv, // subdiv×subdiv 子采样取顶
)
```
- 内部 `(size/subdiv)²` 网格采样，取 max 作 `topY` → 恢复远山起伏（不再单点平板）。
- P1 最小版：仅改 `topY=max(sample)`，保持 1 顶 quad；`subdiv=2`（4 采样）即可明显见效。

**迟滞（防闪烁）**：`_LodCell` 增字段 `int level`；缓存命中时比较「期望档」与 `level`：
```dart
// 越过 1.15× 上限才升档，0.87× 下限才降档；区间内沿用旧 level。
if (desiredLevel > cell.level && cdist > tier[cell.level].ring1 * 1.15) cell.level = desiredLevel;
else if (desiredLevel < cell.level && cdist < tier[cell.level].ring0 * 0.87) cell.level = desiredLevel;
// 用 cell.level 选 tier 的 cell size 重采（或缓存时按 level 存键）。
```
> 简化：缓存键含 `level` → `(band, ci, cj, level)`；迟滞在「是否重建」层面实现（在滞回区内不触发重建，沿用旧 cell）。

**性能**：单 cell 构建成本 ×subdiv²（subdiv=2 → ×4）；仍 << 全精度逐列。构建预算 `budget` 3→6 加速远景填满。
**收益**：细节渐变降级，无 abrupt plate；移动稳定。

---

## P4 · LOD 着色保真（廉价润色）

**目标**：消除「混合区块单色块」。

**改动**（`_buildLodCell` 采样 5 列：4 角 + 中心）：
```dart
// 存 5 个代表列的颜色 + 高度
final List<(Voxel,int)> samples = [
  _sampleAt(cx0, cz0), _sampleAt(cx1, cz0),
  _sampleAt(cx1, cz1), _sampleAt(cx0, cz1),
  _sampleAt(cx0+size/2, cz0+size/2),
];
```
**`_emitLodCell`**：顶 quad 颜色按「面中心最近采样点」取（`majority` 退化为兜底）；有显著高度差时按高度带混色。
**成本**：+4 次 `world.get`，可忽略。

---

## P2 · 保留垂直结构（体素正确性，工作量最大）

**目标**：悬空岛、洞穴口、高墙、桥、建筑侧面在 LOD 带不消失。

**`_buildLodCell` 捕获内部起伏**：
- 采 `subdiv×subdiv`（如 4×4）高度场 `h[i][j]`。
- `topY = max(h)`；同时算单元内「最高陡降」：相邻子样高差 > 1 处记为暴露崖面。
- 存储：`_LodCell` 增 `Float32List relief`（subdiv² 高度）或紧凑的「内部崖面列表」。

**`_emitLodCell` 发射内部崖面**：
```dart
// 对内部相邻子样落差 >1 的边，发一段竖直接面（同边缘台阶逻辑，但内部）。
for (内部相邻对 (a,b) where |h[a]-h[b]|>1)
  _emitLodQuad(... 内部崖面 ...);
```
**`_LodCell` 新字段**：
```dart
class _LodCell {
  final double topY;
  final Voxel majority;
  final double nTop, eTop, sTop, wTop;
  final Float32List? relief; // P2：subdiv² 高度场（null=无起伏）
}
```
**成本**：每 cell 存 16 float（subdiv=4）→ 64 cell 上限 ≈ 1KB，可忽略。
**收益**：远观建筑/悬崖/悬空结构正确。

---

## P5 · 档间无缝过渡

**目标**：消除 80 格处档边界高度接缝、LOD 切换的 snap。

1. **共享边高**：发射 cell 时，其 `topY` 向其跨档邻居的 `topY` 偏置（边界 cell 取两档采样 max）；或相邻档 **重叠 1 cell**。
2. **Geomorph（可选）**：`_LodCell` 增 `double prevTopY`；`_emitLodCell` 每帧把 `topY` 朝目标 lerp（`topY += (target-prevTopY)*0.25`），数帧滑入而非瞬跳。需每帧状态 → 存缓存、在 emit 时更新。

---

## P6 · 配置旋钮

**`RenderConfig` 改动**：
```dart
enum LodQuality { off, balanced, high } // 替代 bool lodEnabled
final LodQuality lodQuality;     // off=全满精度方阵；balanced=当前两档；high=P1 多档细
final bool lodFrustumCull;       // P3 开关，默认 true
```
- `buildFrame`：`lodEnabled` 判定改为 `lodQuality != LodQuality.off`。
- `_emitLodPass`：`lodQuality==high` 用 P1 多档表；`balanced` 用现有 2 档；`off` 不调用。
- 设置页：下拉选 `off/balanced/high` + `lodFrustumCull` 开关。

---

## 性能总估（整体）

| 项 | 现状 | P3 | +P1 | +P2 |
|---|---|---|---|---|
| LOD 面数(FP/TP) | 基线 | ≈×0.5 | ≈×0.5 | ≈×0.5（多内部崖面小幅增） |
| 单 cell 构建成本 | 1 采样 | 同 | ×subdiv²(≈4) | ×subdiv² + relief |
| 总面数上限 | 受 `maxFaces` 限 | 同 | 同（LOD 替满精度，总量有界） | 同 |
| 缓存内存 | 64 cell | 同 | 同（+level 键） | +relief(≈1KB) |

**关键结论**：P1/P2 增的是**构建期**成本（一次性、缓存复用），渲染面数仍由 LOD 覆盖面积决定、不会爆；P3 纯降渲染面数。整体更顺滑、零面数暴涨。

---

## 集成与落地顺序

- 仅改：`_emitLodPass` / `_buildLodCell` / `_emitLodCell` / `_LodCell` / `RenderConfig` / `VoxelChunkCache.maxLodCells` / 设置页。
- `buildFrame` 满精度带（正方形方阵）**不动**。
- 分阶段提交、每阶段 `analyze` 0 error + `build windows --debug` + 复制 `_N`：
  1. **P3**（视锥剔除）—— 独立、零风险
  2. **P1**（多档细 LOD + 迟滞）
  3. **P4**（着色保真）
  4. **P2**（垂直结构）
  5. **P5 / P6**（过渡 + 配置）
