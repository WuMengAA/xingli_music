# 星璃 UI 重构 · 统一 API 契约（T01 已实现，T02–T05 必须遵守）

> **目的**：统一 T01–T05 的命名与 API 真源，消除并行落地导致的互相覆盖。
> **状态**：本契约 = 磁盘现状（已含双命名兼容别名），为**唯一真源**；凡与磁盘现状冲突者，以磁盘现状为准。
> **裁定**：架构师（高见远）据 `docs/ARCHITECTURE_UI_重构.md` + team-lead 终裁。
> **协作模型 / 版本基线 / 进度**：见 §0。

---

## 0. 协作模型 · 版本基线 · 进度

### 0.1 单一写入者模型（停写令已解除）
- `software-engineer` 与 `software-engineer-3` 两个工程师实例**已下线**。
- `xingli_music/lib/**` 现由 **`software-engineer-2`（寇豆码）单人独占写入**，全局停写令已解除。
- 早期「逐文件认领表」**作废**，不再适用多人认领。
- `app_shell.dart`（157 行契约版，已编译通过）**归入 software-engineer-2 统一维护，保留不动**；不再提「原作者认领」。

### 0.2 版本基线（git）
- 仓库：`D:/Stellara/Music/xingli_music/.git`（**独立仓库**，与祖父级 `D:/Stellara` 仓库隔离）。
- 权威基线提交：`4c19cc8` — `chore: re-establish dedicated repo baseline for xingli_music UI refactor`。
- 跟踪：208 文件，工作区干净。
- ⚠️ 该 `.git` 曾被删除重建一次；早期 `58c4b62` / `459eaa0` 两个提交**已随对象库消失，严禁在文档/提交中引用**。
- 提交须带身份（仓库未配全局身份）：
  `git -c user.name="WorkBuddy" -c user.email="workbuddy@local" commit ...`

### 0.3 命名终裁
- **唯一权威**：`AppColors.neutralXX`（`:31`）+ `AppTextStyles.*`（`:326`）。
- `AppNeutral`（`:420`）/ `AppText`（`:432`）为**零开销 `const` 别名，保留不删**。
- 依据：实际引用 `AppColors` **132 次** : `AppNeutral` **2 次**；反向重写属纯破坏性劳动，**禁止**。
- 新代码统一以 `AppColors.*` / `AppTextStyles.*` 书写；既有别名调用无需改动。

### 0.4 实现进度（对齐用）
- T01 设计基座 ✅
- T02 外壳 ✅（`ContentContainer` + `IndexedStack`(5 页保活) + `MiniPlayer` + `AppDock`(4Tab)）
- T04 设置页 Master-Detail —— **已派发 software-engineer-2 进行中**（承载 R12/R13 一票否决项）
- T03 四页浅色重做 / T05 完整播放页 —— 待排

---

## 1. 设计 Token（`lib/core/theme/light_tokens.dart`）

| 类别 | 规范类 | 关键成员 | 兼容别名（保留不删） |
|---|---|---|---|
| 颜色 | `AppColors` | `neutral0…neutral400`；`bgPage/textPrimary/textSecondary/textTertiary`；`accent/accentPressed/accentSoft/onAccent`；`iconInactive/iconActive/iconOnAccent/iconPrimary`；`borderDefault/borderDock/divider`；`progressTrack`；`danger/dangerSoft/success/warning/scrim` | `AppNeutral.n0…n400` |
| 圆角 | `Radius` | `sm=8 / md=18 / lg=24 / xl=36 / pill=999` + `brSm…brPill` | — |
| 间距 | `AppSpace` | `xs=4 / sm=5 / cardTextInset=10 / md=14 / lg=18 / xl=36 / gridRowGap=16` | — |
| 尺寸 | `AppSize` | `heightSearch=40 / heightMiniPill=72 / heightMiniGroup=80 / heightDock=76 / heightProgress=8 / progressInset=34 / icon=26 / iconSm=20 / tabIndicator=44 / thumb=48 / cover=72 / rail=52 / tileWidth=48 / tileHeight=76 / miniButton* / touchMin=44 / dockRadius / shellEdgeInset=0 / narrowBreakpoint=375 / baseWidth=390` | — |
| 阴影 | `AppShadow` | `cardFaithful`（当前生效）/ `cardSoft` / `card`（唯一切换点）/ `cardList` / `softList` | — |
| 字体 | `AppTextStyles` | `title / subtitle / body / bodyMuted / trackName / artist / caption / tabLabel / tileLabel / hint`（全部 `const TextStyle`，**无需 `BuildContext`**） | `AppText.*` |
| 动效 | `AppMotion` | `fast=150 / tab=200 / normal=240 / slow=400`；`ease=Curves.easeOutCubic` | — |

**取色铁律（约定 C1）**：业务代码一律从 `AppColors.*` 取色，禁止散落 `Color(0x...)` 字面量（暗色画布孤岛与 `Scene.bgTop` 类场景数据默认值除外）。

---

## 2. 主题（`lib/core/theme/light_theme.dart`）

- `kLightTheme`：`final ThemeData`，**顶层一次性构建，不依赖任何 Provider**（主题已脱离 `effectivePrimaryProvider`）。
- `kLightColorScheme`：`const ColorScheme`（禁止 `fromSeed`）；`surfaceContainer*` 五档承接中性色阶。
- `buildLightTheme()`：构建函数；`textTheme` 已映射到 `AppTextStyles` 七档。
- `kLightOverlayStyle`：浅色状态栏（透明底 + 深色图标）。
- `MaterialApp` 应使用 `theme: kLightTheme`、`darkTheme: kLightTheme`（防御）、`themeMode: ThemeMode.light`。

---

## 3. 外壳导航状态（`lib/providers/shell/shell_providers.dart`）

- `ShellPage`：`abstract final class`，**`int` 常量（非 Dart `enum`）**：
  `scene=0, explore=1, library=2, settings=3, home=4`；`count=5`；`tabCount=4`；方法 `isTab(int)`。
  - ⚠️ **没有 `.values`**。需要遍历时用显式列表 `[ShellPage.scene, … ShellPage.home]`。
- `shellPageIndexProvider`：`StateProvider<int>` —— **唯一真源**，驱动 `IndexedStack.index`，冷启动默认 `ShellPage.scene`。
- `selectedTabIndexProvider`：`Provider<int?>` —— 派生自上者：`isTab(page) ? page : null`。
  **Dock 必须读它**；返回 `null` = 首页激活 = 4 个 Tab 全部灰色。
- `setShellPage(WidgetRef ref, int pageIndex)`：切页唯一写入入口（含越界保护）。
- `searchQueryProvider`：`StateProvider.family<String, int>`（按页索引隔离搜索词）。

> 与架构文档的差异：`ARCHITECTURE_UI_重构.md §1.5` 曾用名 `shellPageProvider`，**以本契约的 `shellPageIndexProvider` 为准**（架构师将回填修正）。

---

## 4. 设置页 UI（`lib/providers/settings/settings_ui_providers.dart`）

- `SettingsSection`：真实 `enum`（`playback / source / scene / notification / about`），**有 `.values`**；
  extension `SettingsSectionX`：`label / title / icon / keywords / matches(String)`。
- `settingsSectionProvider`：`StateProvider<SettingsSection>`（默认 `playback`）。
- `settingsSectionMatchesProvider`：`Provider<List<SettingsSection>>`（按 `searchQueryProvider(ShellPage.settings)` 过滤；无命中退回全量）。

---

## 5. Dock 高亮铁律

- 读 `selectedTabIndexProvider`（`int?`）。
  - `null` → 4 个 Tab 全灰（首页激活）；
  - `0..3` → 对应 Tab 紫圆（`#7C6BFF` Ø44）高亮，200ms 缓动。
- **禁止**直接读 `shellPageIndexProvider` 判等 `home` 来决定高亮；必须经派生 provider。

---

## 6. `library;` 指令位置（已核查：合法，无需改动）

4 个 T01 文件（`light_tokens.dart` / `light_theme.dart` / `shell_providers.dart` / `settings_ui_providers.dart`）的 `library;` **均正确位于 `import` 之前**（如 `light_tokens.dart` 第 17 行 `library;` 先于第 19 行 `import`），符合 Dart 规范。

实跑 `flutter analyze` / `dart analyze` 结果：**No issues found**。

> ⚠️ **更正记录**：早期曾误报「4 error: library directive must appear before all other directives」，据此要求删除 `library;`。该诊断不成立——`library;` 实为合法位置，**切勿删除**。删除只会失去文件级 doc-comment 挂载点，无任何收益。

---

## 7. 收敛方向（命名终裁）

- **命名终裁**：规范名 = `AppColors.*` / `AppTextStyles.*`；`AppNeutral` / `AppText` 为零开销 `const` 别名，**保留不删**（依引用比 132:2，反向重写纯属破坏性劳动，禁止）。
- 新代码一律以 `AppColors.*` / `AppTextStyles.*` 书写；既有别名调用不动。
- 命名冲突一律以**本契约 + 磁盘现状**为准，不另起一套。

## 8. 维度字面量（补充裁定）
- 约定 C1 仅禁止 `Color(0x...)` **颜色**字面量；尺寸 / 间距 / 圆角等**维度字面量不在禁区**。
- 契约 Token 表未覆盖的局部尺寸（如 `dockMinBottom=2`、`circleButton=40`）：可在本文件内用 `const double` 或内联数值；如需多页共享，提升到 `AppSize`（属 `light_tokens.dart`，由写入者 software-engineer-2 统一处理）。
