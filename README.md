# 星璃音乐 · xingli_music

> 在星光中流淌的真理之光 —— 一个以「体素世界 + 多源音乐」为核心的沉浸式音乐应用：可无限滑动的场景画布、随音乐联动的体素 3D 世界与开放世界游戏、网易云 / B站 / 本地多音源聚合播放。

## 一句话定位

体素 3D 世界 + 多源音乐播放的 Flutter 跨平台应用：场景随音乐和心情变化，强调沉浸体验，并附带可拍摄、可游玩的开放世界。

## 平台

- **Windows（桌面）**：体素 3D 渲染、B站视频场景背景、扫码 / 系统浏览器登录
- **Android（移动）**：原生 WebView 登录 + 扫码登录

（早期规划含 iOS，当前工程聚焦 Windows + Android）

## 核心模块

| 模块 | 说明 |
| ---- | ---- |
| 无限画布 / 场景 | 八向滑动无边界，场景随音乐 / 心情联动，动态配色 |
| 体素 3D 世界 | 体素渲染的开放世界：4 独立动作键、游戏设置合集、世界存档（唯一入口）、存档缩略图 |
| 场景拍摄 | 独立画质 / 效果（与游戏画质解耦）；B站视频可作场景背景（默认静音，**不进游戏**） |
| 多源音乐播放 | 网易云（音乐源）/ 哔哩哔哩（视频源，可作背景）/ 本地（音乐源）聚合搜索与播放 |
| 播放器 | 音乐卡片 / 音乐面板（NowPlayingPage）/ 统一播放器；音量折叠、音质选择（自动识别网易云 VIP / B站大会员） |
| 声音分类 | 音乐 / 背景 / 音效 / 白噪音四类，设备自适应声道预算（桌面 / 移动 / 紧凑端方案） |
| 设置系统 | collection→group→item 注册表，含音频 / 画面 / 游戏 / 场景背景等 |

## 技术选型

- 框架：Flutter 3.x / Riverpod 状态管理
- 音频 / 视频：media_kit（纯音频关视频输出；背景视频走独立 Player + VideoController）
- 多音源抽象：MusicSource（`activeSourcesProvider`：网易云 / B站 / 本地）
- 本地存储：SQLite（sqflite）+ shared_preferences + SecureBox（加密 cookie）

## 设计原则

- **意境优先**：视听结合，沉浸感高于功能数量
- **恰到好处**：明艳、色彩、氛围感、粒子、光影——各元素不堆叠
- **习惯性交互**：不要求用户主动"打卡"，而是通过使用行为自然记录
- **极简克制**：界面元素少，操作靠手势，不靠按钮

## 目录（要点）

```
lib/
├── main.dart / app.dart         # 入口与应用根
├── core/                        # 主题、设置注册表、版本
├── pages/                       # canvas / sources(聚合搜索) / now_playing / voxel 世界 / scene
├── widgets/                     # 卡片、场景背景、音源、设置组件
├── providers/                   # Riverpod（audio / sources / settings / voxel）
└── services/audio/sources/      # 网易云 / B站 / 本地 音源实现
```

## 构建

```bash
flutter pub get

# Windows
flutter build windows --release   # 产物 build/windows/x64/runner/Release/

# Android
flutter build apk --release       # 产物 build/app/outputs/flutter-apk/app-release.apk
```

> Windows 需 Visual Studio 2022 +「使用 C++ 的桌面开发」工作负载；Android 需配置签名 keystore 才能上架。

## 当前版本

- `0.26.8.14_alpha_cl55`（见 `lib/core/app_version.dart`、`android/app/build.gradle`、`pubspec.yaml`）

## 开源与更新

- **开源协议**：MIT（见 `LICENSE`），第三方音源（网易云 / B站）仅供个人学习研究，版权归原平台。
- **OTA 更新**：应用内「设置 → 关于 → 版本更新」通过 GitHub Releases 检测新版本：
  - tag（`cl*` / `v*`）高于当前构建 → 提示更新；
  - `-hotfix` 标记的 Release 直接下载；
  - 下载后校验 SHA-256 哈希，通过才提示安装（见 `.github/workflows/build-release.yml`）。
- **发布流程**：打 tag（如 `cl55`）即触发 Actions 自动构建 APK + 生成校验文件并发布 Release。

## 说明

- 第三方音乐源（网易云 / B站）仅供个人学习研究，版权归原平台，勿商用二次分发。
