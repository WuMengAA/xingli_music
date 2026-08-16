'use strict';
/**
 * 中转服务器协议级验证（无需 Flutter 构建）。
 * 模拟：房主 + 2 客户端，覆盖控制帧(ready/peerJoin/peerLeave) 与游戏帧(广播/定向/自环过滤)。
 */

const { spawn } = require('child_process');
const WebSocket = require('ws');

const PORT = 8799;
const URL = `ws://127.0.0.1:${PORT}/ws`;
const ROOM = 'TEST01';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(pred, timeout = 3000, label = 'condition') {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (pred()) return true;
    await sleep(20);
  }
  throw new Error(`timeout waiting for ${label}`);
}

function makeClient(name) {
  return new Promise((resolve) => {
    const ws = new WebSocket(URL);
    const c = {
      name,
      ws,
      id: null,
      ready: false,
      peerJoins: [],
      peerLeaves: [],
      recv: [],
      error: null,
    };
    c.send = (obj) => ws.send(JSON.stringify(obj));
    ws.on('message', (data) => {
      const m = JSON.parse(data.toString());
      if (m.ctl === 'ready') {
        c.id = m.id;
        c.ready = true;
      } else if (m.ctl === 'peerJoin') {
        c.peerJoins.push(m.id);
      } else if (m.ctl === 'peerLeave') {
        c.peerLeaves.push(m.id);
      } else if (m.ctl === 'error') {
        c.error = m.msg;
      } else {
        c.recv.push(m); // 游戏帧
      }
    });
    ws.on('open', () => resolve(c));
  });
}

function join(c, room, isHost) {
  c.ws.send(JSON.stringify({ ctl: 'join', room, name: c.name, host: isHost }));
}

let pass = 0;
let fail = 0;
function check(label, cond) {
  if (cond) {
    pass++;
    console.log(`  ✓ ${label}`);
  } else {
    fail++;
    console.log(`  ✗ ${label}`);
  }
}

async function main() {
  const server = spawn('node', ['index.js'], {
    cwd: __dirname,
    env: { ...process.env, PORT: String(PORT) },
  });
  server.stderr.on('data', (d) => process.stderr.write(`[relay] ${d}`));
  let started = false;
  await new Promise((resolve) => {
    const to = setTimeout(resolve, 3000);
    server.stdout.on('data', (d) => {
      if (!started && d.toString().includes('listening')) {
        started = true;
        clearTimeout(to);
        resolve();
      }
    });
  });
  if (!started) throw new Error('relay server did not start');

  try {
    // ── 建立连接 ──
    const host = await makeClient('host');
    const a = await makeClient('clientA');
    const b = await makeClient('clientB');

    join(host, ROOM, true);
    await until(() => host.ready, 3000, 'host ready');
    check('房主收到 ready 并分配 id', !!host.id);

    join(a, ROOM, false);
    await until(() => a.ready, 3000, 'clientA ready');
    await until(() => host.peerJoins.includes(a.id), 3000, 'host sees peerJoin(A)');
    await until(() => a.peerJoins.includes(host.id), 3000, 'clientA sees peerJoin(host)');
    check('房主收到 clientA 的 peerJoin', host.peerJoins.includes(a.id));
    check('clientA 收到房主的 peerJoin', a.peerJoins.includes(host.id));
    check('clientA 未收到自身 peerJoin（自环过滤）', !a.peerJoins.includes(a.id));

    join(b, ROOM, false);
    await until(() => b.ready, 3000, 'clientB ready');
    await until(() => host.peerJoins.includes(b.id), 3000, 'host sees peerJoin(B)');
    await until(() => a.peerJoins.includes(b.id), 3000, 'A sees peerJoin(B)');
    check('房主收到 clientB 的 peerJoin', host.peerJoins.includes(b.id));
    check('clientA 收到 clientB 的 peerJoin', a.peerJoins.includes(b.id));
    check('clientB 收到房主 + A 的 peerJoin', b.peerJoins.length === 2);

    // ── 房主广播游戏帧 ──
    const beforeHost = host.recv.length;
    const beforeA = a.recv.length;
    const beforeB = b.recv.length;
    host.send({ t: 5, f: host.id, p: { x: 1, y: 2, z: 3 } });
    await until(() => a.recv.length > beforeA && b.recv.length > beforeB, 3000, 'broadcast delivered');
    check('广播：clientA 收到游戏帧', a.recv.some((m) => m.t === 5));
    check('广播：clientB 收到游戏帧', b.recv.some((m) => m.t === 5));
    check('广播：房主不回送自身（自环过滤）', host.recv.length === beforeHost);

    // ── 房主定向投递给 A ──
    const beforeATo = a.recv.length;
    const beforeBTo = b.recv.length;
    host.send({ t: 24, f: host.id, to: a.id, p: { edits: [] } });
    await until(() => a.recv.length > beforeATo, 3000, 'targeted delivered');
    check('定向：仅 clientA 收到 to 帧', a.recv.some((m) => m.t === 24 && m.to === a.id));
    check('定向：clientB 未收到 to 帧', !b.recv.some((m) => m.t === 24));
    check('定向：房主未收到自身 to 帧', !host.recv.some((m) => m.t === 24));

    // ── 客户端广播到房主 ──
    const beforeHost2 = host.recv.length;
    b.send({ t: 17, f: b.id, p: { text: 'hi' } });
    await until(() => host.recv.length > beforeHost2, 3000, 'client broadcast to host');
    check('客户端广播：房主收到', host.recv.some((m) => m.t === 17 && m.f === b.id));

    // ── 断开 A → 房主与 B 收到 peerLeave ──
    a.ws.close();
    await until(() => host.peerLeaves.includes(a.id) && b.peerLeaves.includes(a.id), 3000, 'peerLeave on disconnect');
    check('断开：房主收到 A 的 peerLeave', host.peerLeaves.includes(a.id));
    check('断开：clientB 收到 A 的 peerLeave', b.peerLeaves.includes(a.id));

    // ── 房间满（MAX_PEERS=32，这里只验证错误通道存在）──
    // 结束
  } finally {
    server.kill('SIGTERM');
  }

  console.log(`\n结果：通过 ${pass} / 失败 ${fail}`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('测试异常：', e);
  process.exit(1);
});
