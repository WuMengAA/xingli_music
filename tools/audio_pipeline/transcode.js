// 星璃 · 内置音频统一转码管线（Node，依赖 ffmpeg）
//
// 目标规范（用户 2026-08-10 定版）：
//   - 容器：M4A（AAC-LC）
//   - 码率：128 kbps
//   - 采样率：44.1 kHz
//   - 声道：stereo（素材是单声道也可保留 mono，统一用 stereo 兼容）
//   - 优化：+faststart（边下边播）
//
// 用法：
//   node transcode.js <输入目录|文件> [输出目录]
//     输入目录：递归找常见音频（mp3/wav/flac/ogg/m4a/aac）
//     输出目录：默认 ./out/<原名>.m4a
//   示例：
//   node transcode.js "D:/my_music_pool" "D:/星璃素材/out"
//
// 也可只检查不转码： node transcode.js <输入> --check
//   （用 ffprobe 打印每个文件的码率/采样率/时长，判断是否已达标）
//
// 需要本机安装 ffmpeg（含 ffprobe）：https://ffmpeg.org/download.html
'use strict';

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const AUDIO_EXT = new Set(['.mp3', '.wav', '.flac', '.ogg', '.m4a', '.aac', '.opus', '.wma']);

const CHECK = process.argv.includes('--check');
const IN = process.argv[2];
const OUT = process.argv[3] || 'out';

if (!IN) {
  console.error('用法: node transcode.js <输入目录|文件> [输出目录] [--check]');
  process.exit(1);
}

function probe(file) {
  try {
    const raw = execFileSync('ffprobe', [
      '-v', 'error',
      '-show_entries', 'format=duration:stream=codec_name,sample_rate,channels,bit_rate',
      '-of', 'json',
      file,
    ], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
    return JSON.parse(raw);
  } catch (e) {
    return { error: String(e && e.message || e) };
  }
}

function transcode(src, dst) {
  // -c:a aac -b:a 128k -ar 44100 -ac 2 +faststart；超过时长的裁剪安全起见不做
  execFileSync('ffmpeg', [
    '-y', '-i', src,
    '-c:a', 'aac', '-b:a', '128k', '-ar', '44100', '-ac', '2',
    '-movflags', '+faststart',
    dst,
  ], { encoding: 'utf8', stdio: ['ignore', 'ignore', 'pipe'], maxBuffer: 4 * 1024 * 1024 });
}

function collect(files, target) {
  const st = fs.statSync(target);
  if (st.isFile()) {
    if (AUDIO_EXT.has(path.extname(target).toLowerCase())) files.push(target);
    return;
  }
  for (const name of fs.readdirSync(target)) {
    collect(files, path.join(target, name));
  }
}

const files = [];
collect(files, IN);
if (files.length === 0) {
  console.error('未找到音频文件');
  process.exit(1);
}
console.log(`找到 ${files.length} 个音频文件`);

if (CHECK) {
  let pass = 0, fail = 0;
  for (const f of files) {
    const info = probe(f);
    const fmt = info && info.format ? info.format : {};
    const st = info && info.streams ? info.streams[0] : {};
    const dur = Number(fmt.duration || 0).toFixed(1);
    const ok = Number(st.bit_rate || 0) >= 120000 && Number(st.sample_rate || 0) === 44100;
    console.log(`${ok ? 'PASS' : '----'} ${path.basename(f)}  ${dur}s  ${st.codec_name || '?'}  ${st.bit_rate ? (st.bit_rate / 1000).toFixed(0) + 'k' : '?'}bps  ${st.sample_rate || '?'}Hz`);
    ok ? pass++ : fail++;
  }
  console.log(`\n达标 ${pass}/${files.length}，未达标 ${fail}。转码请去掉 --check 重跑。`);
  process.exit(0);
}

if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });
let done = 0;
for (const f of files) {
  const base = path.basename(f, path.extname(f));
  const dst = path.join(OUT, `${base}.m4a`);
  try {
    transcode(f, dst);
    done++;
    console.log(`OK  ${path.basename(f)} -> ${dst}`);
  } catch (e) {
    console.error(`FAIL ${path.basename(f)}: ${e && e.message || e}`);
  }
}
console.log(`\n完成 ${done}/${files.length}。输出目录：${path.resolve(OUT)}`);
