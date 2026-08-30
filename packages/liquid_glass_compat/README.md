# liquid_glass_compat

Liquid Glass for Flutter —— 移植自 [martin65536/liquid-glass-webgl](https://github.com/martin65536/liquid-glass-webgl)（WebGL 版）与其上游 [Kyant0/AndroidLiquidGlass](https://github.com/Kyant0/AndroidLiquidGlass)（Android 原版）的液态玻璃组件集，为 Xingli Music 提供统一的玻璃质感控件。

> 原则：能用现成库就不手写。本包直接移植上游几何与物理内核，不发明轮子。

## 特性

| 组件 | 说明 | 上游对应 |
| --- | --- | --- |
| `GlassDock` | 底部标签栏（胶囊高亮 + 弹簧滑动） | Dock.kt / build-dock.ts |
| `GlassSlider` | 滑块（弹性 knob，欠阻尼物理） | Slider.kt |
| `GlassButton` | 按钮（按下缩放 + 玻璃面） | Button.kt |
| `GlassToggle` | 开关（临界阻尼拨动 + 缩放） | Toggle.kt |
| `GlassDialog` / `showGlassDialog` | 对话框（玻璃容器 + 动作条） | Dialog.kt |
| `GlassCard` | 卡片（G2 连续圆角 + 高光边缘） | Card content |
| `GlassScrollContainer` / `GlassLazyScrollContainer` | 滚动容器，懒/非懒加载按性能预设 | ScrollContainerContent.kt / lazy 变体 |
| `GlassProgressiveBlur` | 渐进模糊（多档渐变模糊条） | ProgressiveBlur.kt |
| `AdaptiveLuminanceGlass` | 自适应亮度玻璃（随背景亮度调节模糊/高光） | AdaptiveLuminance.kt |
| `ContinuousCurvatureRoundedRectangleCornerBuilder` | G2 连续曲率圆角（三段贝塞尔、曲率连续） | ContinuousCurvatureRoundedRectangleCornerBuilder.kt |
| `chamferSignedDistanceField` / `SdfTexture` | Chamfer SDF 纹理（着色器用，见 `shaders/g2_sdf.frag`） | ContinuousCurvatureSdf.kt |
| `Spring1D` / `SpringCritical1D` | 欠阻尼/临界阻尼弹簧闭式解 | spring.ts |

文字放大镜（Magnifier）按任务清单暂缓，未移植。

## 快速开始

```yaml
# pubspec.yaml
dependencies:
  liquid_glass_compat:
    path: packages/liquid_glass_compat
```

```dart
import 'package:liquid_glass_compat/liquid_glass_compat.dart';

// 底部标签栏
GlassDock(
  items: const [
    GlassDockItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: '首页'),
    GlassDockItem(icon: Icons.explore_outlined, selectedIcon: Icons.explore, label: '探索'),
    GlassDockItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: '我的'),
  ],
  selectedIndex: 0,
  onSelected: (i) => setState(() => _tab = i),
);

// 卡片 + 滑块 + 开关
GlassCard(
  child: Column(children: [
    GlassSlider(value: _v, onChanged: (v) => setState(() => _v = v)),
    GlassToggle(value: _on, onChanged: (v) => setState(() => _on = v)),
  ]),
);

// 对话框
showGlassDialog(
  context,
  title: '确认',
  content: '要清除下载缓存吗？',
  actions: [
    GlassDialogAction('取消'),
    GlassDialogAction('清除', primary: true),
  ],
);

// 滚动容器：懒/非懒由性能预设自动决定
GlassScrollContainer(
  itemCount: items.length,
  itemBuilder: (c, i) => GlassCard(child: Text(items[i])),
  performancePreset: GlassPerformancePreset.balanced,
);
```

## 性能预设

`GlassPerformancePreset` 三档，映射到模糊半径、降采样、SDF 纹理分辨率、懒加载默认策略：

| 预设 | 模糊 | 降采样 | 折射/色差 | SDF | 滚动容器 | 采样间隔 |
| --- | --- | --- | --- | --- | --- | --- |
| `powerSave` | 0.25× | 4 | 关 | 256 | 默认懒加载 | 500ms |
| `balanced`（默认） | 0.6× | 2 | 开 | 512 | 非懒 | 250ms |
| `smooth` | 1.0× | 1 | 开 | 1024 | 非懒 | 150ms |

```dart
final settings = settingsFor(GlassPerformancePreset.smooth);
// settings.blurScale / blurDownsample / sdfMaxSize / lazyScrollByDefault ...
```

## 渲染内核

- **G2 连续圆角**：每个角 3 段三次贝塞尔（20 控制点），曲率在所有接合处连续——与朴素 G1 圆角相比没有可见曲率突变。控制点按 `extendedFraction = 2/3` 越出角点延伸（原版设计，曲线每侧外扩约 `0.4·r`，渲染时由容器裁剪）。
- **SDF 纹理**：`chamferSignedDistanceField` 生成 Chamfer 距离场，`SdfTexture` 打包纹理，着色器 `shaders/g2_sdf.frag` 消费（值域 [-1,1]，`sdfToRgba8` 编码为 RGBA8）。
- **弹簧物理**：`springStepUnderdamped`（ζ=0.5，滑块/拖拽）、`springStepCritical`（ζ=1，开关值/按下）均为常微分方程闭式解，无迭代误差。

## 测试

```bash
flutter test   # 23 项：几何/SDF/弹簧物理/组件 smoke
```

## 许可

Apache License 2.0（与上游一致）。详见 [LICENSE](LICENSE)。