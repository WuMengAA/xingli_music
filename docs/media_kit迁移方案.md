# media_kit 高性能解码器迁移方案（用户已拍板 C 方案）

> 目标：全平台统一换用 media_kit（基于 libmpv），一次性解决「多格式兼容 / Hi-Res / 无缝播放 / 硬件解码」等主流播放器标配能力。
> 状态：方案待确认后单独轮次实施（不混入本轮性能体系改动，避免回归面叠加）。

## 一、为什么选 media_kit

| 维度 | 现状（just_audio + audioplayers） | media_kit（libmpv） |
|---|---|---|
| 格式兼容 | 依赖平台引擎，仅常见格式 | **几乎所有**：MP3/AAC/FLAC/WAV/OGG/Opus/WMA/M4A/APE/DSD/TAK/ALAC + 视频容器 + HLS/DASH/RTSP 流 |
| Hi-Res 输出 | ❌ | ✅ 高位深/高采样率直通 |
| 无缝播放 gapless | ❌（逐曲加载有间隙） | ✅ mpv 原生 |
| 硬件解码 | 平台默认 | ✅ 硬解（dxva2/d3d11va/mediacodec） |
| 交叉淡入 | 自研 fade | ✅ |
| 跨平台 | 两套插件两套坑 | **一套引擎四端统一** |
| 已知问题 | audioplayers_windows 事件流坏消息（启动 1 次 FormatException，R20 抓到） | 无此问题 |

## 二、影响范围（替换清单）

| 现有 | 替换为 |
|---|---|
| `AudioService._music`（just_audio `AudioPlayer`） | `Player`（media_kit） |
| `AudioService._scA/_scB`（audioplayers 音景 ×2） | `Player`（低优先级，`PlayerConfiguration` 音量/缓冲定制） |
| `AudioService._sfx`（audioplayers 音效） | 按需短音频（可保留 audioplayers 音效位，音效短促无状态流问题） |
| EQ（Android `AndroidEqualizer`，audio_service pipeline） | media_kit 无内置 EQ → 保留 audioplayers 链路做 EQ 或 mpv 的 `af` 滤镜（volume/equalizer） |
| `audio_service` 后台媒体通知 | `media_kit_audio_service`（官方桥接包，维持锁屏/通知栏控件） |
| `StreamResolver`/headers 播放 | media_kit 支持 headers（`PlayerConfiguration`/`Media` 带 http 头）→ 网易云 CDN 链路保持 |

## 三、实施阶段（每阶段独立可验证）

- **S1 依赖引入**：`media_kit` + `media_kit_libs_windows_audio` + `media_kit_libs_android_video` + `media_kit_audio_service`；示例工程跑通双端播放。
- **S2 音乐播放器替换**：`_music` 换 `Player`；`AudioService` 公开 API（play/pause/seek/volume/position/state 流）适配层不动，调用方零改动；`StreamResolver` 接入。
- **S3 音景/白噪音/音效迁移**：`_scA/_scB` 换 Player（多实例 + 声像/隔音在 Dart 层控制）；短音效保留 audioplayers。
- **S4 EQ 与后台服务**：EQ 走 mpv `af` 滤镜或保留 Android 原生；`media_kit_audio_service` 接通知栏；Windows 后台播放语义。
- **S5 全量验证**：128 基线测试 + 网易云全链路 + 真机双端实跑。

## 四、风险与对策

| 风险 | 对策 |
|---|---|
| media_kit Windows 版仍处 beta | S1 先出可运行 demo 验证双端稳定性再推进 |
| EQ 从原生管线换 mpv af 滤镜，频段/参数映射需重做 | S4 单独一轮，EQ 预设映射表先行 |
| 后台服务（audio_service）桥接配置复杂 | 官方 `media_kit_audio_service` 最小化接入，先保通知栏控件 |
| APK 体积增大（libmpv） | 已启用 R8/shrink，控制在可接受范围 |

## 五、前置依赖（与本方案无关但建议顺带）

- 音效素材 128k 重转（等 ffmpeg）——与解码器无关，但影响音质基线。
