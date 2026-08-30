# 设计文档：2.5D 音乐可视化联动（Module "MusicViz-2.5D"）

> 状态：设计定稿（2026-08-13，R26r22）。用户已确认三项核心决策。
> 作者：ArchitectUX（UserExperienceArchitect 协作）
> 关联：LOD / home_restructure / voxel_world_feedback / small_space_culling 设计 md 同目录。

## 0. 背景与目标
- **核心差异点**：星璃音乐 = 音乐 × 体素。当前 2.5D 音效画布（`VoxelCanvasView`）是静态音景编辑器，不响应音乐；音乐反应层 `VisualizerService` 是**合成假数据**（节拍固定 2Hz、频段按播放进度算，完全不读真实音频），对每首歌动画雷同。
- **本功能目标**：让玩家把 3D 体素世界的"各种东西"**转化**进 2.5D 音效画布，并让画布**真实随音乐联动**（方块随节拍脉冲、高度随频段能量起伏）。

## 1. 已确认的三项决策（用户 2026-08-13「同意」）
1. **转化对象 = 选中区域提取**：玩家在 3D 世界选中某区域/建筑 → 单独提取其体素 → 映射进 2.5D 网格。
2. **驱动表现 = 脉冲 + 高度起伏**：方块随节拍脉冲缩放，整体高度（extrude 厚度）随频段能量起伏，地形/建筑有流动感。
3. **音乐数据 = 离线预分析**：加载曲目时解码分析 → 生成按播放位置采样的「节拍网格 + 多频段能量包络」时间线（`MusicEnvelope`），真实联动。

## 2. 现有代码资产（复用，不重写）
- `lib/widgets/voxel/voxel_canvas_view.dart` — 2.5D 等距 `CustomPaint`，`_VoxelPainter` 画每块（顶面菱形 + 左右侧面，`depth = hh*0.55` 固定厚度）。**改造点：depth 改为随频段能量变化 + 顶面随节拍缩放。**
- `lib/widgets/voxel/voxel_canvas_controller.dart` — `ChangeNotifier`，`blocks`(`"col,row"`→typeId)、`cols/rows`、undo/redo、`load(VoxelSoundScene)`/`toScene()`。
- `lib/models/voxel.dart` — `VoxelBlockType`(rain/wind/fire/bird/water/cricket 音效块) + `VoxelSoundScene`(id/name/cols/rows/blocks)。**改造点：场景加可选 `heights` 映射（每格高度比 0~1）。**
- `lib/widgets/voxel/voxel_world.dart` — `VoxelWorld`：`get(x,y,z)`、`surfaceHeight(x,z)`、`terrainHeightAt(x,z)`、`seed`、`waterLevel`；`Voxel` 枚举(air/grass/stone/sand/water/wood/leaves/snow/...)，`kVoxelSpecs[v].solid`。
- `lib/pages/canvas/voxel_canvas_page.dart` — 2.5D 沉浸画布页（含视图切换 2.5D↔3D）。
- `lib/providers/scene/voxel_scene_providers.dart` — 2.5D 音效场景持久化列表。
- `lib/services/audio/visualizer_service.dart` + `visualizer_providers.dart` — 合成反应层（**保留为无 ffmpeg 时的降级源**）。

## 3. 架构与数据流
```
[曲目加载] → EnvelopeAnalyzer(ffmpeg 解码→PCM→分帧FFT→包络) → MusicEnvelope(时间线, 缓存)
                                        ↓
[播放进度 positionMs] → envelopePlaybackProvider.sampleAt() → {bands[16], beat}
                                        ↓
                          2.5D VoxelCanvasView(_VoxelPainter)
                          - depth = hh*(0.55 + bandEnergy*K)   ← 高度起伏
                          - 顶面缩放 = 1 + beat*0.15            ← 脉冲
                          - 颜色亮度随整体 level（可选）
                                        ↑
[3D 世界 "转化为2.5D"] → WorldToCanvasExporter.exportRegion(world, cx, cz, r)
                         列→分类(Voxel→音效块类型)→2.5D 网格 + heights → VoxelSoundScene
```

## 4. 模块设计

### A. MusicEnvelope（真实离线分析）— 数据层根依赖
- **`lib/services/audio/music_envelope.dart`**
  - `class MusicEnvelope { final double durationMs; final int fps; final int bandCount; final Float32List bands; /* frames×bandCount, 0~1 */ final Float32List beat; /* frames, 0~1 */ }`
  - `List<double> sampleBands(double ms)` / `double sampleBeat(double ms)`：按位置线性插值取帧。
- **`lib/services/audio/envelope_analyzer.dart`**
  - `Future<MusicEnvelope> analyze(String filePath, {int bandCount=16, int fps=24})`
  - ffmpeg 解码：`ffmpeg -i <file> -f s16le -ac 1 -ar 22050 -` → raw Int16 PCM（stdout 字节流）。
  - Dart 侧：`Int16List` 解析 → 分帧（hop = 22050/24 ≈ 919 samples）→ 每帧 radix-2 FFT(1024) → 对数分布 16 频段能量（低频权重高）；节拍 = 低频能量通量 + 峰值拾取（onset detection）。
  - 体积极致：4min@24fps = 5760 帧 ×16 ≈ 92k float ≈ 368KB；按需用 `Float32List` 存盘（`.envelope` 二进制，按路径 hash 缓存于 app docs）。
  - **平台**：Windows 走 ffmpeg（解析 `where ffmpeg`/WinGet Links 路径）；无 ffmpeg → 抛 `EnvelopeUnavailable` → 调用方降级到合成 `VisualizerService`。
  - **性能**：分析在 isolate/`compute` 跑，避免加载卡 UI。
- **`lib/providers/audio/envelope_providers.dart`**
  - `envelopeProvider`（当前曲目 → `MusicEnvelope`，异步 + 缓存）。
  - `envelopePlaybackProvider`（监听播放进度，输出当前 `bands`+`beat`，驱动 2.5D 重绘的 Ticker 源）。

### B. WorldToCanvasExporter（3D→2.5D 区域提取）
- **`lib/services/voxel/world_to_canvas_exporter.dart`**
  - `({VoxelSoundScene scene, Map<String,double> heights}) exportRegion(VoxelWorld world, int cx, int cz, int radius)`
  - 遍历 `(dx,dz)∈[−r,r]²`：
    - `h = world.surfaceHeight(cx+dx, cz+dz)`；`top = world.get(cx+dx, cz+dz, h)`。
    - 分类 `top`/材质 → `VoxelBlockType.id`（映射表见下）。
    - 放置到 2.5D 格 `(col=dx+r, row=dz+r)`；`heights[key] = (h - waterLevel).clamp(0,1)`（或相对该区域 maxH 归一化）。
  - **Voxel→音效块映射**：water/sand(临水)→`water`；leaves/wood(树)→`bird`；snow/高山→`wind`；lava/fire→`fire`；grass/平原→`cricket`；stone/峭壁→`rain`；默认→`rain`。
- **接入点 `voxel_world_view3d.dart`**：折叠菜单加「转化为 2.5D 音效画布」→ 取玩家世界坐标 `(px,pz)` → `exportRegion(world, px, pz, r=7)` → 存 `voxel_scene_providers` → `Navigator` 推 `VoxelCanvasPage`（viz 模式）。

### C. 2.5D 音乐可视化渲染
- **`voxel_canvas_controller.dart`**：新增 viz 状态
  - `Map<String,int> cellBand`：每格绑定频段索引（默认按 `kVoxelBlockTypes.indexOf(type) % bandCount`，或按到中心径向距离做"涟漪"）。
  - `void applyEnvelope(List<double> bands, double beat)`：存当前帧值，`notifyListeners()` 触发重绘。
- **`voxel_canvas_view.dart` / `_VoxelPainter`**：
  - `depth = hh * (0.55 + bands[cellBand[key]] * 0.9)`（高度起伏，幅度可调）。
  - 顶面菱形按 `beat` 缩放：`_diamond(c, scale: 1 + beat*0.15)`。
  - 顶面亮度随 `bands` 均值轻微提升（可选，保 WCAG 对比）。
  - Repaint 由 `envelopePlaybackProvider` 的 Ticker 驱动（~30–60fps）。
- **性能预算**：15×15=225 格，每格 ~3 path，远低于 2ms/帧；最大支持 32×32。低端机可降 fps 到 30。

### D. 数据模型扩展
- `VoxelSoundScene` 加可选 `Map<String,double> heights`（向后兼容：旧场景 heights 为空 → 默认 0.5）。`toJson/fromJson` 同步。

## 5. 文件变更清单
| 文件 | 动作 | 内容 |
|---|---|---|
| `lib/services/audio/music_envelope.dart` | 新建 | MusicEnvelope 模型 + 采样 |
| `lib/services/audio/envelope_analyzer.dart` | 新建 | ffmpeg 解码 + Dart FFT + 节拍检测 + 缓存 |
| `lib/providers/audio/envelope_providers.dart` | 新建 | riverpod：曲目→envelope、播放进度→bands/beat |
| `lib/services/voxel/world_to_canvas_exporter.dart` | 新建 | 3D 区域→2.5D 场景 + heights |
| `lib/models/voxel.dart` | 改 | VoxelSoundScene 加可选 `heights` |
| `lib/widgets/voxel/voxel_canvas_controller.dart` | 改 | viz 状态（cellBand + applyEnvelope） |
| `lib/widgets/voxel/voxel_canvas_view.dart` | 改 | 脉冲 + 高度起伏 painter |
| `lib/widgets/voxel/voxel_world_view3d.dart` | 改 | 「转化为 2.5D」动作 + 导航 |
| `lib/pages/canvas/voxel_canvas_page.dart` | 改 | viz 模式开关 + 载入 envelope |
| `lib/providers/scene/voxel_scene_providers.dart` | 改 | 存导出场景 |
| 测试 | 新建 | `test/music_envelope_test.dart`、`test/world_to_canvas_exporter_test.dart` |

## 6. 验收标准
- 在 3D 世界触发「转化为 2.5D」→ 生成 N×N 音景场景 → 进入 2.5D 画布。
- 播放任意曲目 → 2.5D 方块随节拍脉冲、高度随频段起伏（真数据，非每首雷同）。
- 无 ffmpeg 时优雅降级（合成源 + 提示），不崩溃。
- `flutter analyze` 0 error；viewport 2/2；新单元测试过。
- 性能：2.5D 重绘 < 2ms/帧（低端机 30fps）。

## 7. 分阶段实现
- **Phase 1（本期交付 cl16）**：A 全量（MusicEnvelope + analyzer + providers）+ B 全量（exporter + 动作 + 导航）+ C 全量（脉冲+高度起伏）+ D + 测试 + 构建交付。
- **Phase 2（后续）**：cellBand 分配 refined（按音高/位置涟漪）、viz 编辑态持久化、场景分享/导出、画质档、非 Windows 降级打磨、真实频谱条（若需）。

## 8. 关键技术风险
- **ffmpeg 子进程路径**：WinGet Links 符号链接在 subprocess env 可能不解析 → 运行时 `where ffmpeg` + 常见路径兜底；找不到则降级。
- **PCM 解析**：`-f s16le -ac 1` → Int16 LE 单声道。
- **Dart FFT**：实现最小 radix-2 FFT（帧长 1024 幂次）。
- **大曲目**：envelope 二进制 ~370KB/4min，缓存可控。
- **UI 卡顿**：分析放 isolate/`compute`。
- **可访问性**：毛玻璃 + 脉冲动画注意对比度（WCAG AA），亮度调制有下限。
