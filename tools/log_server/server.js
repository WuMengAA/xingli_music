// 星璃 · 云端日志收集器（零依赖 Node 服务）
//
// 用法: node server.js [端口]     （默认 8765，或环境变量 PORT）
//
// 接口:
//   POST /api/logs   请求体为 JSON 数组 [{ts, level, tag, msg}, ...]
//                    → 追加写入 logs/<YYYY-MM-DD>.log（JSONL）
//   GET  /           简易网页查看器（最近 1000 条，按级别着色）
//   GET  /health     健康检查 { ok: true }
//
// 安全提示:
//   - 本服务无鉴权，日志含应用脱敏后的文本，但**不要**在公网裸奔；
//     建议内网使用，或经 nginx 反代 + basic auth / 白名单后再暴露公网。
//   - 单请求 ≤ 256KB / ≤ 500 条；单日文件 ≤ 64MB，超出丢弃（防止刷爆磁盘）。
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.argv[2] || process.env.PORT || '8765', 10);
const LOG_DIR = path.join(__dirname, 'logs');

if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });

const MAX_BODY = 256 * 1024;
const MAX_ENTRIES = 500;
const MAX_TOTAL_BYTES = 64 * 1024 * 1024;

function todayFile() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return path.join(
    LOG_DIR,
    `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}.log`,
  );
}

function append(entries) {
  const file = todayFile();
  try {
    const st = fs.statSync(file);
    if (st.size > MAX_TOTAL_BYTES) return 0;
  } catch (_) {
    /* 文件不存在，正常 */
  }
  const lines = entries.map((e) => JSON.stringify(e)).join('\n') + '\n';
  fs.appendFileSync(file, lines, 'utf8');
  return entries.length;
}

function send(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        reject(new Error('body too large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function serveViewer(res) {
  let lines = [];
  try {
    const files = fs
      .readdirSync(LOG_DIR)
      .filter((f) => f.endsWith('.log'))
      .sort();
    for (const f of files) {
      const content = fs.readFileSync(path.join(LOG_DIR, f), 'utf8');
      for (const l of content.split('\n').filter(Boolean)) {
        try {
          lines.push(JSON.parse(l));
        } catch (_) {
          /* 跳过损坏行 */
        }
      }
    }
  } catch (_) {
    /* 读取失败则展示空 */
  }
  lines = lines.slice(-1000).reverse();
  const rows = lines
    .map(
      (e) =>
        `<tr class="${esc(String(e.level || 'info').toLowerCase())}">` +
        `<td>${esc(e.ts || '')}</td><td>${esc(e.level || '')}</td>` +
        `<td>${esc(e.tag || '')}</td><td>${esc(e.msg || '')}</td></tr>`,
    )
    .join('');
  const html = `<!DOCTYPE html><html lang="zh"><head><meta charset="utf-8">
<title>星璃日志中心</title>
<style>
body{font-family:Consolas,Menlo,monospace;margin:24px;background:#111;color:#ddd}
h2{color:#eee}
table{border-collapse:collapse;width:100%}
td,th{border:1px solid #333;padding:4px 8px;text-align:left;font-size:12px;word-break:break-all;vertical-align:top}
th{position:sticky;top:0;background:#1e1e1e;color:#aaa}
tr.error td{color:#ff7b7b}tr.warn td{color:#ffd479}tr.info td{color:#9adc9a}
tr.summary td{color:#8ab4ff;background:#132238;font-weight:bold}
tr.debug td{color:#9aa4b2}
</style></head><body>
<h2>星璃 · 日志中心（最近 ${lines.length} 条）</h2>
<table><thead><tr><th>时间</th><th>级别</th><th>分类</th><th>消息</th></tr></thead>
<tbody>${rows}</tbody></table></body></html>`;
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(html);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'POST' && url.pathname === '/api/logs') {
    try {
      const body = await readBody(req);
      let entries;
      try {
        entries = JSON.parse(body);
      } catch (_) {
        return send(res, 400, { ok: false, error: 'invalid JSON' });
      }
      if (!Array.isArray(entries) || entries.length === 0) {
        return send(res, 400, { ok: false, error: 'expected non-empty array' });
      }
      const slice = entries.slice(0, MAX_ENTRIES).map((e) => ({
        ts: typeof e.ts === 'string' ? e.ts : String(e.ts ?? ''),
        level: typeof e.level === 'string' ? e.level : 'INFO',
        tag: typeof e.tag === 'string' ? e.tag : '',
        msg: typeof e.msg === 'string' ? e.msg : JSON.stringify(e),
      }));
      const n = append(slice);
      send(res, 200, { ok: true, received: n });
    } catch (e) {
      send(res, 500, { ok: false, error: String((e && e.message) || e) });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/health') {
    return send(res, 200, { ok: true, uptime: process.uptime() });
  }

  if (req.method === 'GET') {
    return serveViewer(res);
  }

  send(res, 404, { ok: false, error: 'not found' });
});

server.listen(PORT, () => {
  console.log(`[log-server] listening on :${PORT}  (POST /api/logs | GET /)`);
});

// ── 局域网自动发现（手机 App 免填地址）────────────────────────
// App 向 255.255.255.255:<DISCOVERY_PORT> 广播 `STELLARA_LOG_PROBE`，
// 本服务收到后回 `STELLARA_LOG_FOUND <PORT>`，App 取响应源 IP 拼出地址。
const dgram = require('dgram');
const DISCOVERY_PORT = parseInt(process.env.DISCOVERY_PORT || '8766', 10);
const udp = dgram.createSocket('udp4');
udp.on('message', (msg, rinfo) => {
  if (msg.toString('utf8').trim() === 'STELLARA_LOG_PROBE') {
    udp.send(Buffer.from(`STELLARA_LOG_FOUND ${PORT}`, 'utf8'), rinfo.port, rinfo.address);
  }
});
udp.bind(DISCOVERY_PORT, () => {
  console.log(`[log-server] discovery udp :${DISCOVERY_PORT}  (STELLARA_LOG_PROBE)`);
});
