# 星璃 · 无限音乐画布 —— 项目初始化与依赖配置步骤

> 目标：在 Flutter 3.x 上从零初始化 `xingli_music` 项目，支持 Android 5.0+ 与 iOS 10.0+（✏️ C-4 对齐：以 PROJECT_STATE 平台决策为准；iOS 当前无工程，数值待定），使用 Riverpod 状态管理，按功能模块组织目录。

---

## 一、环境准备

### 1. 安装 Flutter SDK（3.x 稳定版）

- 当前最新稳定版为 **3.44.8**（本机已安装于 `D:\flutter`）
- 国内网络环境推荐使用镜像下载（官方 Google 存储经常不可达）：

```powershell
# 腾讯云镜像（实测可达，约 1.8GB）
curl.exe -L -o "$HOME\Downloads\flutter_3.44.8.zip" `
  "https://mirrors.cloud.tencent.com/flutter/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.8-stable.zip"

# 解压到 D:\flutter
Expand-Archive -Path "$HOME\Downloads\flutter_3.44.8.zip" -DestinationPath "D:\" -Force
```

- 备用镜像（可达性经实测）：上海交大 `https://mirror.sjtu.edu.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.8-stable.zip`

### 2. 配置国内镜像源（必须，否则 `pub get` / 引擎下载会卡住）

```powershell
[Environment]::SetEnvironmentVariable("FLUTTER_STORAGE_BASE_URL", "https://mirrors.cloud.tencent.com/flutter", "User")
[Environment]::SetEnvironmentVariable("PUB_HOSTED_URL", "https://mirrors.cloud.tencent.com/dart-pub", "User")
# 将 D:\flutter\bin 加入用户 PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", "$userPath;D:\flutter\bin", "User")
```

重开终端后验证：

```powershell
flutter --version
flutter doctor
```

> 本项目目录（`lib/`、`pubspec.yaml`、`android/`、`ios/`）已按标准模板就绪，
> 且已通过 `flutter analyze` / `flutter test` 验证。

### 2. 安装 Android 工具链（构建 Android 包）

- **JDK 17**（Flutter 3.x 要求）：<https://adoptium.net/temurin/releases/>
- **Android Studio**（自带 Android SDK）：<https://developer.android.com/studio>
  - SDK Manager 中安装：Android SDK Platform、Build-Tools
  - 勾选一个 Android 5.0（API 21）以上的模拟器镜像
- 在 Android Studio 中设置好 `ANDROID_HOME`（通常为 `%LOCALAPPDATA%\Android\Sdk`）

### 3. 安装 iOS 工具链（构建 iOS 包，需 macOS）

- Xcode 15+（App Store 安装）
- 安装 Command Line Tools：`xcode-select --install`
- 安装 CocoaPods：`sudo gem install cocoapods`

---

## 二、初始化项目

```powershell
# 1) 在父目录创建/进入项目
cd d:\Stellara\Music
# 如果 SDK 已安装且想全新生成，也可执行：
# flutter create xingli_music --platforms=android,ios --org com.stelarith --project-name xingli_music

cd xingli_music

# 2) 补齐平台工程资源（重要）
#    本仓库已含源码与主要平台配置，此命令会补齐缺失的二进制资源：
#    gradle wrapper jar / iOS 图标 / Xcode 工程文件(Runner.xcodeproj) 等
#    它不会覆盖已有的 lib/ 代码与配置。
#    （本机已执行过，SDK 已就绪时可直接从第 3 步开始）
flutter create . --org com.stelarith --project-name xingli_music --platforms=android,ios

# 3) 拉取依赖
flutter pub get

# 4) 运行测试验证
flutter test

# 5) 运行到设备 / 模拟器
flutter run
```

> 说明：本机已安装 Flutter SDK（`D:\flutter`，3.44.8）并完成 `flutter create .` 补齐，
> `flutter analyze`（0 问题）与 `flutter test`（全部通过）已验证通过。
> 在其他机器上只需重复上述步骤即可复现。

---

## 三、依赖配置说明（pubspec.yaml）

```yaml
dependencies:
  flutter_riverpod: ^2.6.1    # 状态管理（必须）
  audioplayers: ^6.1.0        # 音频播放（音乐模块）
  just_audio: ^0.9.42         # 音频引擎（音乐模块）
  sqflite: ^2.4.1             # SQLite 本地库
  path: ^1.9.0
  path_provider: ^2.1.5       # 访问本地目录（音乐文件索引）
  shared_preferences: ^2.3.3  # 轻量偏好（心情 / 配色偏好）
```

| 依赖 | 用途 | 是否必须 |
| ---- | ---- | ---- |
| `flutter_riverpod` | 状态管理（ProviderScope / ConsumerWidget） | 必须 |
| `audioplayers` | 播放本地音乐（与场景联动） | 后续模块 |
| `just_audio` | 更细粒度的音频控制（进度 / 变速） | 后续模块 |
| `sqflite` | 音乐索引、播放记录、使用行为存储 | 后续模块 |
| `shared_preferences` | 心情、配色、上次浏览位置等轻量状态 | 后续模块 |

新增依赖后执行：

```powershell
flutter pub add <package>
# 或
flutter pub get
```

---

## 四、最低系统版本配置

### Android（最低 Android 5.0 = API 21）

文件：`android/app/build.gradle`

```groovy
defaultConfig {
    applicationId = "com.stelarith.xingli_music"
    minSdk = 21                 // Android 5.0 (Lollipop) 起
    targetSdk = flutter.targetSdkVersion
    ...
}
```

> Flutter 3.x 默认 `minSdk` 即 21（`flutter.minSdkVersion`），此处显式写出便于维护。
> 若后续引入需要更高 minSdk 的插件，按需上调。

### iOS（最低 iOS 10.0）

> ✏️ **C-4 回填**：原 12.0 为 `flutter create` 默认值；平台决策（`PROJECT_STATE.md` 三）：iOS 最低 **10 / 目标 26**，当前无 iOS 工程（待定）。以 PROJECT_STATE 为准。

文件：`ios/Flutter/AppFrameworkInfo.plist`

```xml
<key>MinimumOSVersion</key>
<string>10.0</string>
```

另外在 Xcode 中确认 Runner Target 的 **Deployment Target = 10.0**（`flutter create .` 生成的 `project.pbxproj` 中为 `IPHONEOS_DEPLOYMENT_TARGET`，若需保持 10.0 可在 Xcode 中修改后重新生成）。

---

## 五、目录结构（按功能模块划分）

```
lib/
├── main.dart                       # 入口：ProviderScope + StelarithMusicApp
├── app.dart                        # 应用根组件（MaterialApp、主题、主页）
├── core/                           # 核心基础
│   └── theme/
│       └── app_theme.dart          # Material 3 主题 + 星璃五色板
├── pages/                          # 页面（每个功能一个子目录）
│   └── canvas/
│       └── canvas_page.dart        # 主页面：无限画布
├── widgets/                        # 可复用组件（粒子、卡片、场景元素等）
├── models/                         # 数据模型（MusicTrack / Scene / Mood 等）
├── providers/                      # Riverpod 状态
│   └── canvas/
│       └── canvas_providers.dart   # 画布视口、激活场景
├── services/                       # 业务服务（MusicService / SceneService / StorageService）
└── utils/                          # 工具（颜色插值、时间格式化等）
```

新增功能模块时遵循同一模式，例如音乐模块：

```
lib/
├── pages/player/player_page.dart
├── providers/player/player_providers.dart
├── services/audio/music_service.dart
└── models/music_track.dart
```

---

## 六、Material 3 说明

- 项目已在 `app_theme.dart` 中启用 `useMaterial3: true`
- 使用 `ColorScheme.fromSeed(seedColor: 琉璃紫 #9B7BFF)` 生成整套配色
- 星璃品牌色板：

| 颜色 | 值 | 用途 |
| ---- | ---- | ---- |
| 深空紫 | `#1A103C` | 主背景 |
| 暮光蓝 | `#2B2D6B` | 场景渐变 |
| 琉璃紫 | `#9B7BFF` | 主题种子色 |
| 星光金 | `#F5D98F` | 点缀 / 高亮 |
| 奶白 | `#F8F4ED` | 浅色模式背景 |

---

## 七、运行验证清单

```powershell
flutter doctor                 # 环境健康检查（0 项严重问题）
flutter analyze                # 静态检查（无 error）
flutter test                   # widget 测试通过
flutter run                    # 真机 / 模拟器启动，看到星空画布主页
flutter build apk --debug      # Android 产物验证
```

---

## 八、常见问题

| 问题 | 解决 |
| ---- | ---- |
| `flutter: 不是内部或外部命令` | 将 Flutter SDK 的 `bin` 目录加入 PATH 后重开终端 |
| `flutter.sdk not set in local.properties` | 运行 `flutter pub get` 或 `flutter create .` 自动生成 `android/local.properties` |
| `gradle-wrapper.jar 缺失` | 运行 `flutter create .` 补齐（或复制任意 Gradle 项目的 wrapper） |
| iOS 没有 `Runner.xcodeproj` | 在 macOS 上运行 `flutter create .` 生成 |
| `minSdk 21` 相关警告 | Flutter 3.x 默认就是 21，保持 `minSdk = 21` 即可 |
| 中文应用名乱码 | 已分别配置 `android:label="星璃音乐"` 与 `CFBundleDisplayName=星璃音乐` |
