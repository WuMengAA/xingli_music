# 小空间（封闭 / 室内 / 洞穴 / 地下）剔除方案 · 详细设计

> 目标读者：后续实现者。基于 `lib/widgets/voxel/voxel_renderer.dart` +
> `voxel_camera.dart` 真实代码（R26r17 状态）撰写，非泛泛而谈。
> 与 `LOD_improvement_design.md` **正交**：LOD 管远景保真，本文管封闭时整体砍量。

---

## 0. 现状：与小空间相关的三条剔除链路

| 层级 | 位置 | 机制 | 小空间下的表现 |
|---|---|---|---|
| 区块级视锥 | `voxel_renderer.dart:685-707` | `_chunkInFrustum` 8 角 AABB 测试；**相机所在区块 + 紧邻 3×3 无条件保留**（R26p 补丁，注释写「剔穿墙」） | 补丁掩盖了症状，未除根 |
| 面级遮挡 | `_buildChunkMesh` / `isFaceHidden` (`:1107-1115`) | 邻居 `occludes` → 内部面不发射，相机无关 + 缓存 | ✅ 已正确，实心内部零面 |
| 面级投影近裁剪 | `voxel_camera.dart:23, 330` | `if (viewZ < p.near) return null` → **整面硬丢弃**，`near=0.06` | ❌ **穿墙根因** |
| 远景 LOD | `_emitLodPass` | 两档马赛克，覆盖 32→maxDist | ❌ 封闭时 100% 在墙后仍全额付费 |

---

## 1. 症结（按严重度）

### 症结 1｜贴脸墙面整面丢失 —— 「剔穿墙」根因（P0 正确性）

`projectWith` 对近平面做**硬丢弃**：quad 只要有 1 个顶点 `viewZ < 0.06`，
整个面返回 null 被丢掉。

小空间里墙面沿横向/纵向延伸，**常常跨过眼平面**。举例（1×1 竖井）：

```
眼 (0.5, 1.6, 0.5)，朝向 +Z
+X 墙上某 quad 角点 = (1,1,0) (1,2,0) (1,2,1) (1,1,1)
角点 (1,1,0)：dz = 0 - 0.5 = -0.5  →  viewZ = -0.5 < near
→ 整个 quad 被丢  →  看穿 +X 墙，露出虚空
```

R26p 的 3×3 nearCam 白名单让区块**进入了**渲染流程，但面级依旧被丢
→ 这解释了「打了补丁还偶发穿墙」。

**历史坑（务必别重犯）**：注释 `voxel_camera.dart:326` 记录
「R26o 近裁剪改回硬丢弃 —— R26l 的『夹紧』…」。
说明曾试过 **clamp（把顶点 viewZ 夹到 near）**，失败原因是夹紧会把顶点
沿深度硬拉、屏幕位置错乱 → 产生拉伸三角/糊面。
**正解不是 clamp，而是 clip（插值生成新顶点）**。二者本质不同。

### 症结 2｜封闭空间仍在渲染整个世界（P1 性能）

室内 / 洞穴 / 地下时：
- `kFullBand=2` → 5×5=25 个区块满精度外壳面
- `_emitLodPass` 两档马赛克覆盖 32→maxDist

这些**全部在墙后，可见度 0**，但构建、投影、着色、深度排序全额付费。
本渲染器是 CPU/Canvas 管线，**面数即帧时间** → 这是封闭场景最大浪费。

### 症结 3｜贴面时背面剔除过零噪声（P2）

`:769-773` 背面剔除用「眼→面中心」点积 `>= 0` 判背面。
眼几乎贴在面上时点积趋近 0，浮点噪声会让同一面在帧间抖动 → 墙面闪烁。

### 症结 4｜nearCam 3×3 是白名单而非判据（P2 清理）

无条件保留 9 个区块属于「宁多勿漏」的兜底。根因（AABB 8 角在贴脸时
以极陡角度全落视锥外）应由**膨胀 AABB** 解决，而不是绕过测试。

---

## 2. 方案

### S1 · 近平面多边形裁剪（P0，正确性，必做，独立可交付）

新增到 `VoxelCamera`：

```dart
/// 世界空间多边形 → 近平面裁剪 → 投影。
/// [xyz] 顶点流 [x,y,z, x,y,z, ...]（逆时针，通常 4 顶点）。
/// 返回 null = 完全在近平面之后；否则返回 3~5 个屏幕点。
static List<ScreenPoint>? projectPolyClipped(
  Float64List xyz,
  ViewBasis b,
  ProjectionParams p,
);
```

算法（Sutherland–Hodgman，单平面 `viewZ = near`）：

1. 逐顶点算 `viewZ = d·fwd`；
2. **全部 `>= near`** → 走原快路径（逐点 `projectWith`），**零额外成本**；
3. **全部 `< near`** → 返回 null；
4. **混合** → 环状遍历边 `(v0,v1)`：
   - `v0` 在内 → 输出 `v0`
   - 跨界 → 输出交点，`t = (near - z0) / (z1 - z0)`，
     **在世界空间线性插值** `p = v0 + t·(v1 - v0)`（保证透视正确），
   - 再逐点投影裁剪后的多边形。

集成点：`buildFrame` 面投影处（`:767` 起的 `for (final CachedFace cf in mesh.faces)`）
把「4 点逐个 project，任一 null 则 continue」换成 `projectPolyClipped`；
`_emitLodQuad`、`_emitBox` 同样替换（实体贴脸同理）。
着色/AO 需支持 3~5 顶点（顶点色按裁剪 t 插值；Canvas `drawVertices`
用三角扇 fan 展开即可）。

- **成本**：只有跨近平面的少量面走慢路径（实测量级：每帧个位数~几十面）→ 可忽略。
- **收益**：彻底消灭「剔穿墙 / 看到虚空」；且可把 `near` 从 0.06 放大到 0.1
  提升深度排序精度（原本不敢放大就是怕丢面更多）。
- **副作用**：可**删掉** R26p 的 nearCam 3×3 白名单（配合 S5）。

### S2 · 区块连通性 flood-fill 可见集（P1，封闭场景主力）

即 Minecraft 的 **cave culling**。核心：可见性沿**空气连通**传播，
被实心封死的方向不再扩散。

缓存数据（相机无关，随几何缓存同期失效，存 `VoxelChunkCache`）：

```dart
/// 单区块的「面—面空气连通性」摘要。
class ChunkVisibility {
  /// 6 bit：该侧面是否存在空气格（0 = 完全封死，不可能透光）。
  /// bit 0:+X 1:-X 2:+Y(top) 3:-Y 4:+Z 5:-Z
  final int faceOpen;
  /// 15 bit：C(6,2) 面对是否通过区块内空气互相连通。
  final int connMask;
  const ChunkVisibility(this.faceOpen, this.connMask);
}
```

构建（与 `_buildChunkMesh` 同量级，一次性）：
对区块内空气格跑一次并查集/BFS 求连通分量 → 记录每个分量触及了哪些
边界面 → 同分量内任意两面互相置位 `connMask`。

帧内遍历（**替换** `:665-666` 的双层 for）：

```dart
/// 从相机区块出发 BFS，只经「空气连通面」扩散，返回可见区块集。
/// 队列元素编码 (cx, cz, enterFace)；相机所在区块 enterFace = ALL。
static Set<int> _floodVisibleChunks(
  VoxelWorld world,
  VoxelChunkCache? cache,
  int camChunkX, int camChunkZ, int vd,
  ViewBasis b, ProjectionParams proj,
  RenderConfig config,
);
```

出队规则：
1. 相机所在区块无条件可见，`enterFace = ALL`（相机在内部，全向扩散）；
2. 只向 `connMask[enterFace]` 置位的出口面扩散；
3. 出口面 `faceOpen` 为 0 → 不扩散（完全封死）；
4. 邻块需通过 `_chunkInFrustum`（S1 后不再需要 nearCam 豁免）+ 距离上限；
5. 已访问集去重。

效果：
- **室内 / 洞穴 / 地下**：BFS 几步即停 → 渲染区块 25 → 1~4，**远景 LOD
  自然不入集**（连带解决症结 2）。
- **露天山顶**：BFS 铺满整个方阵 → 与现状完全一致，**无视觉回退**。
- 天然覆盖门窗漏光：有孔就连通，就会正确扩散出去，**不会误剔**。

LOD 通道也按可见集过滤：`_emitLodPass` 的单元先查所属区块是否在
`visible` 内（跨档单元取任一覆盖区块可见即保留）。

### S3 · 眼周封闭检测 → 跳过 LOD 通道（P1，S2 的廉价先行版）

```dart
/// 眼睛是否被实心封闭：6 轴向 + 4 水平斜向射线，每向最多 maxStep 格，
/// 全部命中 occludes 才判封闭。
static bool _eyeEnclosed(VoxelWorld w,
    double ex, double ey, double ez, {int maxStep = 6});
```

判定为封闭时：
- **整段跳过 `_emitLodPass`**（远景全在墙后）；
- `kFullBand` 2 → 1（9 个区块足够覆盖一个房间/洞窟）；
- 跳过天空/雾着色。

- 成本 ≈ 30 次 `get()` / 帧 → 完全可忽略。
- 定位：**S2 的 30 行先行版**，当天可见效；S2 上线后 S3 变冗余（可保留作兜底）。
- 风险控制：误判（门窗漏光但射线全被挡）**只影响远景 LOD**，
  近景 5×5 满精度带仍在 → 代价远小于误剔近景。故**不要**用 S3 去砍近景。

### S4 · 背面剔除 epsilon（P2）

`:773` `if (... >= 0) continue;` → `>= -1e-4`（或按面对角尺寸缩放），
消除眼贴墙时点积过零抖动导致的墙面闪烁。

### S5 · 膨胀 AABB 取代 nearCam 白名单（P2 清理，依赖 S1）

`_chunkInFrustum` 加参数：

```dart
static bool _chunkInFrustum(ViewBasis b, ProjectionParams p,
    int x0, int z0, int cs, int maxY, {double inflate = 0});
```

8 角坐标各向外扩 `inflate = math.max(p.near, 0.8)` 后测试 →
贴脸区块**凭判据合法通过**，而非白名单绕过。
随后把 `:699-700` 的 `nearCam` 从 3×3 收缩为「仅相机所在区块」→ 省 8 个区块。

---

## 3. 落地顺序与收益预估

| 阶段 | 工作量 | 风险 | 收益 |
|---|---|---|---|
| **S1** 近平面裁剪 | 中（投影+着色需支持 3~5 顶点） | 低（有快路径回退） | **P0 正确性**：根除穿墙；可放大 near 提精度 |
| **S3** 封闭检测 | 极小（~30 行） | 低（只关远景） | 封闭时立省全部 LOD 面 |
| **S2** flood-fill | 中大（连通性构建 + BFS 遍历重构） | 中（需验证露天无回退） | 室内/地下区块数 25→1~4，**主力** |
| **S4/S5** 清理 | 小 | 低 | 去闪烁、去白名单、省 8 区块 |

推荐：**S1 → S3 → S2 → S4/S5**。
S1 与 S3 互不依赖，可同一版交付；S5 依赖 S1 先落地。

---

## 4. 与 LOD 方案的关系

- `LOD_improvement_design.md` 的 P1~P6 提升**远景保真**（多档细分、垂直结构、着色）。
- 本文 S1~S5 解决**封闭时整体砍量**与**贴脸正确性**。
- 交汇点：S2 的可见区块集应同时作为 `_emitLodPass` 的过滤器 →
  「远景更细 + 室内更省」可叠加，互不冲突。
- 满精度正方形带（`kFullBand`）语义保持不变，仅在 S3 封闭态下临时收窄。

---

## 5. 验收清单

- [ ] 站进 1×1 竖井 / 2×2 小屋，360° 旋转 + 贴墙推进：**任何角度不透墙、不见虚空**
- [ ] 地下深处：帧时间应显著下降（LOD 面数 → 0），HUD 面数计数可验证
- [ ] 露天山顶 / 平原：面数与视觉**与改动前一致**（无回退）
- [ ] 房间开一扇门/窗：从门外能看到室内、从室内能看到门外景（flood-fill 正确扩散）
- [ ] 眼贴墙静止：墙面**无闪烁**（S4）
- [ ] 第三人称贴墙：玩家模型与墙面均不闪、不穿
