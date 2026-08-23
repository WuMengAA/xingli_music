# 星璃音乐 · iOS 原生 UI 风格设计令牌规范稿

> **文档状态**：规范稿（待确认）
> **目标分支**：`net-relay`
> **关联任务**：#607（设计令牌规范）、#608（组件改造对照）
> **决策基线**：明暗双主题 + 纯 iOS 分层灰底（去极光/噪点）+ 大标题导航 + 底部 Tab

---

## 0. 背景与决策

本次改造将星璃音乐的整体观感收敛为**苹果原生 iOS 风格**，核心决策已通过两次 AskUserQuestion 确认：

| 决策项 | 结论 |
|--------|------|
| iOS 化力度 | 调研官方规范后落地（HIG + 实测系统色） |
| 配色基调 | 明暗双主题（Light / Dark 均原生 iOS 语义色） |
| 背景基调 | 纯 iOS 分层灰底——**移除**现有极光渐变 + 噪点纹理 |
| 导航形态 | 大标题（Large Title）+ 底部 Tab |
| 落地方式 | 先出规范稿，用户确认后再改业务代码 |

**本文件仅定义令牌与改造映射，不直接改动任何业务代码。**

---

## 1. 颜色令牌（iOS 系统语义色）

颜色值依据 Apple HIG（Human Interface Guidelines）语义色定义，通过实测系统色值（swiftuicolors.com / colorsift.com / lobehub ios-ui-guidelines）校准。所有值写成 `Color(0x...)` 形式，便于直接替换 `light_tokens.dart` 与 `app_theme_colors.dart`。

### 1.1 浅色主题（Light）

| 语义槽（AppThemeColors 字段） | iOS 系统色名 | 值 | 说明 |
|-------------------------------|--------------|-----|------|
| `bgPage` | systemBackground | `#FFFFFF` | 页面根底 |
| `bgSurface` | secondarySystemBackground | `#F2F2F7` | 内容容器 / 列表分组底 |
| `bgSurfaceSunken` | tertiarySystemBackground | `#E5E5EA` | 凹陷输入区 / 搜索栏底 |
| `bgCard` | secondarySystemBackground | `#F2F2F7` | 卡片底（与 surface 同） |
| `bgRail` | secondarySystemBackground | `#F2F2F7` | 设置左分类栏 |
| `bgTile` | tertiarySystemBackground | `#E5E5EA` | 设置分类 tile |
| `bgDock` | systemThickMaterial / secondarySystemBackground | `#F2F2F7` | 底部 Dock 容器（iOS TabBar 用系统材质，浅色约此值） |
| `bgInput` | tertiarySystemBackground | `#E5E5EA` | 输入框底 |
| `bgControl` | secondarySystemBackground | `#F2F2F7` | 控制按钮底 |
| `bgPlaceholder` | systemGray5 | `#E5E5EA` | 占位 / 骨架屏 |
| `textPrimary` | label | `#000000` | 主文字 |
| `textSecondary` | secondaryLabel | `rgba(60,60,67,0.6)` | 副文字 |
| `textTertiary` | tertiaryLabel | `rgba(60,60,67,0.3)` | 占位 / 辅助 |
| `accent` | systemBlue | `#007AFF` | 强调色（iOS 默认蓝） |
| `accentSoft` | systemBlue + fill | `rgba(0,122,255,0.12)` | 浅蓝底 |
| `accentPressed` | systemBlue (darkened) | `#0062CC` | 按下态 |
| `onAccent` | label (on blue) | `#FFFFFF` | 蓝底上的文字 |
| `iconPrimary` | label | `#000000` | 主图标 |
| `iconInactive` | tertiaryLabel | `rgba(60,60,67,0.3)` | 未选中图标 |
| `border` | separator (opaque variant) | `rgba(60,60,67,0.29)` | 1px 描边 |
| `divider` | separator | `rgba(60,60,67,0.29)` | 列表分割线 |
| `danger` | systemRed | `#FF3B30` | 错误 / 危险 |
| `dangerSoft` | systemRed + fill | `rgba(255,59,48,0.12)` | 浅红底 |
| `success` | systemGreen | `#34C759` | 成功 |
| `warning` | systemOrange | `#FF9500` | 警告 |
| `scrim` | systemFill (dark) | `rgba(0,0,0,0.4)` | 全屏遮罩 |
| `progressTrack` | systemGray5 | `#E5E5EA` | 进度条底轨 |

### 1.2 深色主题（Dark）

| 语义槽 | iOS 系统色名 | 值 | 说明 |
|--------|--------------|-----|------|
| `bgPage` | systemBackground | `#000000` | 页面根底（纯黑） |
| `bgSurface` | secondarySystemBackground | `#1C1C1E` | 内容容器 |
| `bgSurfaceSunken` | tertiarySystemBackground | `#2C2C2E` | 凹陷输入区 |
| `bgCard` | secondarySystemBackground | `#1C1C1E` | 卡片底 |
| `bgRail` | secondarySystemBackground | `#1C1C1E` | 设置左分类栏 |
| `bgTile` | tertiarySystemBackground | `#2C2C2E` | 设置分类 tile |
| `bgDock` | systemThickMaterial / secondarySystemBackground | `#1C1C1E` | 底部 Dock 容器 |
| `bgInput` | tertiarySystemBackground | `#2C2C2E` | 输入框底 |
| `bgControl` | secondarySystemBackground | `#1C1C1E` | 控制按钮底 |
| `bgPlaceholder` | systemGray6 (dark) | `#2C2C2E` | 占位 / 骨架屏 |
| `textPrimary` | label | `#FFFFFF` | 主文字 |
| `textSecondary` | secondaryLabel | `rgba(235,235,245,0.6)` | 副文字 |
| `textTertiary` | tertiaryLabel | `rgba(235,235,245,0.3)` | 占位 / 辅助 |
| `accent` | systemBlue (dark) | `#0A84FF` | 强调色 |
| `accentSoft` | systemBlue + fill | `rgba(10,132,255,0.24)` | 浅蓝底 |
| `accentPressed` | systemBlue (darkened) | `#0060DF` | 按下态 |
| `onAccent` | label (on blue) | `#FFFFFF` | 蓝底上的文字 |
| `iconPrimary` | label | `#FFFFFF` | 主图标 |
| `iconInactive` | tertiaryLabel | `rgba(235,235,245,0.3)` | 未选中图标 |
| `border` | separator (dark) | `rgba(84,84,88,0.6)` | 描边 |
| `divider` | separator (dark) | `rgba(84,84,88,0.6)` | 分割线 |
| `danger` | systemRed (dark) | `#FF453A` | 错误 / 危险 |
| `dangerSoft` | systemRed + fill | `rgba(255,69,58,0.24)` | 浅红底 |
| `success` | systemGreen (dark) | `#30D158` | 成功 |
| `warning` | systemOrange (dark) | `#FF9F0A` | 警告 |
| `scrim` | systemFill (dark) | `rgba(0,0,0,0.6)` | 全屏遮罩 |
| `progressTrack` | systemGray6 (dark) | `#2C2C2E` | 进度条底轨 |

### 1.3 与现有代码的映射关系

现有 `AppThemeColors` 字段名**完全兼容** iOS 语义色，无需重命名字段，只需替换 `light` / `dark` 两组常量的值：

- **浅色组**：`AppThemeColors.light` ← 替换 `AppColors.*` 为 §1.1 的 iOS 值
- **深色组**：`AppDarkColors.palette` ← 替换为 §1.2 的 iOS 值
- **强调色族**：`withSkin()` 当前按皮肤主色（紫 `#7C6BFF`）派生；
  iOS 化后建议**默认 accent 固定为 systemBlue**（或保留皮肤切换但默认蓝），
  `withSkin()` 仅覆盖 accent 族，中性色阶不动 —— 与现结构一致，改动极小。

**不改字段名**的原因：业务组件已全部通过 `context.appColors.xxx` 取色，
令牌值替换后自动全局生效，零业务代码改动。

---

## 2. 字体令牌（SF Pro 文本样式）

iOS 使用 SF Pro 字体族；Flutter 在 iOS 上自动映射系统字体，
**无需引入自定义字体**（与现行 `fontFamilyFallback` 策略一致，仅调整规格）。

以下规格对齐 iOS Dynamic Type 文本样式（iOS 17 基准）。
现行 `AppTextStyles` 字号普遍偏小（如 title 18/w600），iOS 大标题导航需升级。

| 样式名（建议新增/调整） | iOS 文本样式 | 字号(pt) | 字重 | 行高 | 对应现有槽 |
|-------------------------|--------------|----------|------|------|-----------|
| `largeTitle` | Large Title | 31 | Regular (400) | 1.2 | 新增（大标题导航用） |
| `largeTitleBold` | Large Title (nav) | 31 | Semibold (600) | 1.2 | 新增（可选加粗大标题） |
| `title1` | Title 1 | 25 | Regular | 1.2 | 新增 |
| `title2` | Title 2 | 19 | Regular | 1.25 | 新增 |
| `title3` | Title 3 | 17 | Semibold (600) | 1.3 | 对应现有 `title`(18→17) |
| `headline` | Headline | 14 | Semibold (600) | 1.3 | 对应现有 `subtitle` |
| `body` | Body | 17 | Regular | 1.4 | 现有 `body`(14→17) |
| `callout` | Callout | 13 | Regular | 1.4 | 新增 |
| `subhead` | Subhead | 12 | Regular | 1.3 | 新增 |
| `footnote` | Footnote | 12 | Regular | 1.35 | 新增 |
| `caption1` | Caption 1 | 11 | Regular | 1.2 | 现有 `caption` |

**改造要点**：
1. 新增 `largeTitle`(31pt) 用于页面大标题（替代现有 18pt `title` 作为页眉主标题）。
2. `body` 全局默认从 14 → **17pt**（iOS Body 基准），正文可读性对齐原生。
3. 保留 `trackName`(14/w600) / `artist`(12) / `caption`(11) 等多为列表/迷你播放器内小字，可维持现状或微调。
4. 颜色随主题：浅色 `textPrimary=#000`，深色 `textPrimary=#FFF`（经 `AppTextTheme` 已处理）。

---

## 3. 圆角令牌（iOS 形状规范）

iOS 圆角规则：
- **分组列表 / 卡片**：固定 10pt（分组 inset group）或 12–16pt（卡片）。
- **控件（按钮 / 输入框 / 胶囊）**：高度 / 2（完全圆角）。
- **同心圆角**：子元素圆角 = 父圆角 − 间距 padding。

| 槽（AppRadius） | 现行值 | iOS 建议 | 用途 |
|-----------------|--------|----------|------|
| `sm` | 8 | **10** | 小控件 / 分组列表圆角 |
| `md` | 18 | 12–16 | 设置分类 tile / 卡片（建议 14） |
| `lg` | 24 | 16–20 | 专辑卡 / 设置卡片（建议 16–20） |
| `xl` | 36 | 20–28 | 内容容器（可选收缩） |
| `pill` | 999 | 999 | 搜索栏 / Dock / 进度条（保持） |

**最小触控热区**：保持 `AppSize.touchMin = 44`（iOS 规范 44×44pt，已满足）。

---

## 4. 间距令牌（iOS 基准）

iOS 常用 8pt 栅格（4 / 8 / 12 / 16 / 20 / 24 …）。现行 `AppSpace` 已基本覆盖，
建议微调以贴合原生密度：

| 槽 | 现行 | iOS 建议 | 说明 |
|----|------|----------|------|
| `xs` | 4 | 4 | 保持 |
| `sm` | 5 | **8** | 迷你播放器与 Dock 间距（贴近 8pt 栅格） |
| `cardTextInset` | 10 | **12** | 卡片内文本左边距 |
| `md` | 14 | **16** | 屏幕外边距 |
| `lg` | 18 | **20** | 容器内边距 |
| `xl` | 36 | 36 | 保持 |
| `gridRowGap` | 16 | 16 | 保持 |

---

## 5. 毛玻璃 / 材质参数（iOS Material）

iOS 标准材质仅 4 层（ultra-thin / thin / regular / thick），**无公开模糊半径值**。
Flutter 侧用 `BackdropFilter` 近似；建议参数：

| 材质层 | iOS 名称 | Flutter 建议 `sigmaX/Y` | 透明度(alpha) | 用途 |
|--------|----------|------------------------|---------------|------|
| 薄 | ultraThin / thin | 10–16 | 0.7–0.85 | Dock / Sheet 背景 |
| 标准 | regular（默认） | 20–30 | 0.85–0.92 | 内容容器 / 卡片毛玻璃 |
| 厚 | thick | 30–40 | 0.92–0.97 | 弹层 / 对话框（保对比） |

**原则**：
- 越厚越不透明（保前景对比），越薄越透（保留上下文）。
- 现有 `LiquidGlass` 已是毛玻璃组件，iOS 化主要调整 `sigma` 与 `tint` 跟随 §1 语义色，
  并**移除极光 tint 派生**（`glassTint` 改为中性白/黑薄层而非 accent 紫）。

---

## 6. 组件改造对照（任务 #608）

### 6.1 PageScaffold → iOS 大标题导航

| 现行 | iOS 改造 |
|------|----------|
| 标题行 `context.appText.title` (18/w600)，单行居中省略 | 改为 **Large Title** 31pt Regular，左对齐，可换行；滚动时收缩为紧致标题（iOS 大标题折叠行为） |
| 右上角 `ThemeSwitchButton()` | 保留（非原生但为应用功能），可置于大标题行右侧 |
| 返回箭头 `Icons.arrow_back_rounded` | 改为 `Icons.chevron_left`（iOS 风格返回） |
| 整页 Material 透明 | 保持（根路由透玻璃），但 iOS 化后背景层改为纯灰底，玻璃表面可保留或降级 |

**落点**：`lib/widgets/common/page_scaffold.dart`

### 6.2 AppDock → iOS TabBar 质感

| 现行 | iOS 改造 |
|------|----------|
| 满宽毛玻璃药丸 r=38 + 5×Expanded | iOS TabBar 为**底部整条**毛玻璃（非药丸），建议改为整条 `thick` 材质条，取消药丸圆角 |
| `_DockTab` Ø44 圆选中指示 | iOS 选中态为**图标 + 文字同色变蓝**（systemBlue），无圆形背景；建议去掉 Ø44 圆底，仅变色 |
| 文字标签 10pt | iOS TabBar 标签 10pt（已接近），保持；颜色未选中 `tertiaryLabel`、选中 `systemBlue` |

**落点**：`lib/widgets/shell/app_dock.dart`

### 6.3 卡片 / 列表 / 按钮 / Sheet / Slider 映射

| 组件 | iOS 规范 | 落点提示 |
|------|----------|----------|
| 分组列表 | inset group，圆角 10pt，底 `secondarySystemBackground`，分割线 `separator` | 现有列表容器改用 `bgSurface` + `AppRadius.sm` |
| 卡片 | 圆角 12–16pt，底 `secondarySystemBackground`，无重阴影（iOS 用层级而非投影） | `AppRadius.lg` 调 16；`AppShadow.card` 可降级为极淡或去阴影 |
| 按钮 | Filled = systemBlue 底白字；文字按钮 = systemBlue 字；圆角 = 高/2 | 现有 FilledButton 强调色改为 `accent`(systemBlue) |
| Sheet（底部弹层） | `thick` 材质，顶部圆角 16pt，抓手条 | 现有底部弹层加 `AppRadius.lg(top)` |
| Slider（进度条） | 轨道 `systemFill`，已播放 `systemBlue`，thumb 圆 | 现有进度条 accent 改 systemBlue |

### 6.4 AppShell 背景层移除（关键改动）

| 现行（`app_shell.dart` 第 330–342 行） | iOS 改造 |
|----------------------------------------|----------|
| `Positioned.fill` → `auroraGradient` 极光渐变背景层 | **删除**（纯分层灰底） |
| `NoiseTexture` 噪点层（第 339–342 行） | **删除**（或仅省电模式保留，默认关） |
| Scaffold `backgroundColor: bgPage` | 保持，但 `bgPage` 改为 iOS `systemBackground`（白/纯黑） |

**落点**：`lib/app_shell.dart` —— 移除极光 `DecoratedBox` 与 `NoiseTexture` 两节点，
背景由 Scaffold `bgPage` 直接承担。

### 6.5 主题接入点总结

| 文件 | 改动 |
|------|------|
| `lib/core/theme/light_tokens.dart` | `AppColors` 中性色阶 + 语义别名替换为 §1.1 值；`AppTextStyles` 增 `largeTitle`、调 `body`/`title`；`AppRadius`/`AppSpace` 微调 |
| `lib/core/theme/app_theme_colors.dart` | `AppThemeColors.light` ← `AppColors`；`AppDarkColors.palette` ← §1.2；`glassTint` 去 accent 紫改为中性；`auroraGradient` 可保留但不再使用（或直接删） |
| `lib/widgets/common/page_scaffold.dart` | 大标题导航（§6.1） |
| `lib/widgets/shell/app_dock.dart` | iOS TabBar 质感（§6.2） |
| `lib/app_shell.dart` | 移除极光 + 噪点（§6.4） |

---

## 7. 待确认事项

1. **强调色**：默认用 iOS `systemBlue`（推荐，最贴近原生），还是保留现有紫色皮肤体系但换令牌值？
2. **毛玻璃去留**：Apple 风格下 Dock / 内容容器是否保留毛玻璃（iOS 原生有大量材质使用），还是全部降级为纯色分层？
3. **大标题折叠**：是否实现 iOS 式「大标题→滚动收缩为小标题」交互（需额外滚动监听），还是固定大标题？
4. **球体/画布孤岛**：CanvasPage 等暗色画布页是否同步 iOS 化，还是保持现状（独立于全局主题）？
5. **字体回归**：`body` 14→17pt 的放大是否影响现有密集布局（迷你播放器 / 列表行高），需真机验证。

---

## 8. 落地顺序建议（确认后执行）

1. 替换 `AppColors` / `AppDarkColors.palette` 颜色值（§1）。
2. 调整 `AppTextStyles` / `AppRadius` / `AppSpace`（§2–4）。
3. 移除 `app_shell.dart` 极光 + 噪点（§6.4）。
4. 改造 `PageScaffold` 大标题（§6.1）。
5. 改造 `AppDock` 为 iOS TabBar（§6.2）。
6. 卡片 / 列表 / 按钮 / Sheet / Slider 令牌对齐（§6.3）。
7. `flutter analyze lib` 验证（维持 0 error）+ 双端构建（规则 D）+ 提交。

---

*本规范稿基于 Apple HIG 官方规范与实测系统色值（2026-08）整理，待用户确认后进入代码落地阶段。*
