# 星璃 · 内置音频素材管线

统一规范（用户 2026-08-10 定版）：

| 项 | 值 |
|---|---|
| 容器 | M4A（AAC-LC） |
| 码率 | **128 kbps** |
| 采样率 | 44.1 kHz |
| 声道 | stereo |
| 优化 | `+faststart`（边下边播） |

## 现状

- `assets/audio/` 已内置 **21 个精选压缩素材**（ambience / bamboo_wind / beach_waves /
  birds / campfire / leaves_rustle / rainforest_birds / rain_432hz / summer_ambience /
  wind_chimes，各含 `_a/_b` 双变体），供场景音景与「我的世界」环境音使用。
- 体积约 4.2MB（素材管线 566MB → 4.2MB 压缩）。

## 新增素材流程

1. 把原始音频丢进任意目录（支持 mp3/wav/flac/ogg/m4a/aac/opus/wma）；
2. 检查是否已达标：

   ```bash
   node tools/audio_pipeline/transcode.js "D:/我的素材" --check
   ```

3. 统一转码到 `assets/audio/`：

   ```bash
   node tools/audio_pipeline/transcode.js "D:/我的素材" assets/audio
   ```

4. 命名规范：`<语义名>_<变体>.m4a`（如 `campfire_a.m4a`、`rain_432hz_b.m4a`），
   然后到 `lib/services/audio/` 里按需引用（AmbientSoundscapeService / 空间音效预设）。

## 依赖

需要本机安装 [ffmpeg](https://ffmpeg.org/download.html)（含 ffprobe），并加入 PATH。

## 音乐背景乐补充

想"添加更多素材背景音乐"时：
- 免版权来源建议：CC0 / 网易云音乐人上传的原创素材（注意授权）、
  freesound.org（CC0/CC-BY）、Incompetech 等；
- 放进来跑上面脚本统一为 128k m4a 即可，不用手工逐条处理。
