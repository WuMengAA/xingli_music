'use strict';
/**
 * ═══════════════════════════════════════════════════════════════════════════
 * 星璃音乐 · 中转服务器（relay）
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 设计目标：
 *   - 让处于 NAT / 防火墙后的「房主」与「加入者」能够跨公网互联，无需房主暴露
 *     端口、无需端口转发。
 *   - 服务器**零游戏逻辑**：不理解任何业务消息，只做「房间感知的 WebSocket 扇出」。
 *   - 客户端侧已有完整的「主机-客户端」协议（NetMessage JSON 信封），本服务器
 *     完全复用之——所有游戏帧原样转发，仅按 `to` 字段定向或按房间广播。
 *
 * 控制帧（仅客户端 ↔ 中转，JSON）：
 *   客户端→中转： { "ctl": "join", "room": "ROOM", "name": "昵称", "host": bool }
 *   中转→客户端： { "ctl": "ready", "id": "peerId", "room": "ROOM" }
 *   中转→客户端： { "ctl": "peerJoin", "id": "peerId", "name": "昵称" }
 *   中转→客户端： { "ctl": "peerLeave", "id": "peerId" }
 *   中转→客户端： { "ctl": "error", "msg": "..." }
 *   中转→客户端： { "ctl": "pong" }   （回应客户端 ping）
 *
 * 游戏帧（无 `ctl` 字段、含 `t`/`f`/`p` 的 JSON）：
 *   - 带 `to` 字段 → 仅投递给该 peerId（如 welcome / editSnapshot）。
 *   - 不带 `to`    → 广播给同一房间内除发送者外的所有成员（如 transform/edit/
 *                    vitals/chat/listenState）。
 *
 * 部署：
 *   node index.js            # 默认监听 0.0.0.0:8765
 *   或 PORT=9001 HOST=0.0.0.0 node index.js
 *   Docker: docker build -t xingli-relay . && docker run -p 8765:8765 xingli-relay
 *
 * 健康探针： GET /healthz → { ok, rooms, peers, uptime }
 * ═══════════════════════════════════════════════════════════════════════════
 */

const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT) || 8765;
const HOST = process.env.HOST || '0.0.0.0';
const MAX_PEERS = Number(process.env.MAX_PEERS) || 32; // 单房间上限，防滥用
const PING_INTERVAL = Number(process.env.PING_INTERVAL) || 30000;
const MAX_ROOM_LEN = 64;
const MAX_NAME_LEN = 32;

/** room → Map<peerId, { ws, name, host }> */
const rooms = new Map();
/** ws → { room, peerId } */
const peerMeta = new Map();

function genId() {
  return (
    Math.random().toString(36).slice(2, 10) +
    Math.random().toString(36).slice(2, 10)
  );
}

function sendCtrl(ws, obj) {
  if (ws.readyState === ws.OPEN) {
    try {
      ws.send(JSON.stringify(obj));
    } catch (_) {
      /* ignore */
    }
  }
}

// ── HTTP 健康探针（便于容器/K8s 探活）────────────────────────
const server = http.createServer((req, res) => {
  if (req.url === '/healthz' || req.url === '/') {
    let peers = 0;
    for (const m of rooms.values()) peers += m.size;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        ok: true,
        rooms: rooms.size,
        peers,
        uptime: Math.floor(process.uptime()),
      }),
    );
    return;
  }
  res.writeHead(404);
  res.end('not found');
});

const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.on('pong', () => {
    ws.isAlive = true;
  });

  ws.on('message', (data, isBinary) => {
    if (isBinary) return;
    let obj;
    try {
      obj = JSON.parse(data.toString());
    } catch (_) {
      return; // 非法包忽略
    }
    if (!obj || typeof obj !== 'object') return;

    if (obj.ctl === 'join') {
      handleJoin(ws, obj);
      return;
    }
    if (obj.ctl === 'ping') {
      sendCtrl(ws, { ctl: 'pong' });
      return;
    }
    // 其余均视为游戏帧 → 路由
    routeGame(ws, data.toString(), obj);
  });

  ws.on('close', () => handleLeave(ws));
  ws.on('error', () => handleLeave(ws));
});

function handleJoin(ws, obj) {
  const room =
    typeof obj.room === 'string' && obj.room.trim()
      ? obj.room.trim().slice(0, MAX_ROOM_LEN)
      : '';
  const name =
    typeof obj.name === 'string'
      ? obj.name.slice(0, MAX_NAME_LEN)
      : '玩家';
  const host = obj.host === true;
  if (!room) {
    sendCtrl(ws, { ctl: 'error', msg: 'room required' });
    return;
  }
  let members = rooms.get(room);
  if (!members) {
    members = new Map();
    rooms.set(room, members);
  }
  if (members.size >= MAX_PEERS) {
    sendCtrl(ws, { ctl: 'error', msg: 'room full' });
    return;
  }
  const peerId = genId();
  members.set(peerId, { ws, name, host });
  peerMeta.set(ws, { room, peerId });

  // 告知新成员自身 id
  sendCtrl(ws, { ctl: 'ready', id: peerId, room });
  // 通知房间内已有成员「有新成员」
  for (const [id, m] of members) {
    if (id === peerId) continue;
    sendCtrl(m.ws, { ctl: 'peerJoin', id: peerId, name });
  }
  // 把房间内已有成员告知新成员
  for (const [id, m] of members) {
    if (id === peerId) continue;
    sendCtrl(ws, { ctl: 'peerJoin', id, name: m.name });
  }
}

function routeGame(ws, raw, obj) {
  const meta = peerMeta.get(ws);
  if (!meta) return; // 尚未 join，丢弃
  const members = rooms.get(meta.room);
  if (!members) return;
  const to = typeof obj.to === 'string' && obj.to ? obj.to : null;
  if (to) {
    const target = members.get(to);
    if (target) target.ws.send(raw);
    return;
  }
  for (const [id, m] of members) {
    if (id === meta.peerId) continue; // 不回送发送者
    m.ws.send(raw);
  }
}

function handleLeave(ws) {
  const meta = peerMeta.get(ws);
  if (!meta) return;
  peerMeta.delete(ws);
  const members = rooms.get(meta.room);
  if (!members) return;
  members.delete(meta.peerId);
  for (const m of members.values()) {
    sendCtrl(m.ws, { ctl: 'peerLeave', id: meta.peerId });
  }
  if (members.size === 0) rooms.delete(meta.room);
}

// 心跳：清理掉线连接
const interval = setInterval(() => {
  for (const ws of wss.clients) {
    if (ws.isAlive === false) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    try {
      ws.ping();
    } catch (_) {
      /* ignore */
    }
  }
}, PING_INTERVAL);
wss.on('close', () => clearInterval(interval));

server.listen(PORT, HOST, () => {
  // eslint-disable-next-line no-console
  console.log(`[xingli-relay] listening on ws://${HOST}:${PORT}/ws`);
});
