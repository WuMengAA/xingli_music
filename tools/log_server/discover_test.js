// 局域网发现自测（模拟手机 App 的 UDP 探测）
// 用法: node discover_test.js [目标IP]   默认广播 255.255.255.255:8766
'use strict';
const dgram = require('dgram');
const PORT = parseInt(process.env.DISCOVERY_PORT || '8766', 10);
const TARGET = process.argv[2] || '255.255.255.255';

const s = dgram.createSocket('udp4');
const timer = setTimeout(() => {
  console.error('未收到日志服务器响应（检查 server.js 是否已启动、是否同网段、防火墙）');
  s.close();
  process.exit(1);
}, 3000);

s.on('message', (msg, rinfo) => {
  console.log(`收到响应: ${msg.toString('utf8')}  (来自 ${rinfo.address}:${rinfo.port})`);
  clearTimeout(timer);
  s.close();
  process.exit(0);
});

s.bind(0, () => {
  console.log(`广播探测 → ${TARGET}:${PORT}`);
  s.send(Buffer.from('STELLARA_LOG_PROBE'), PORT, TARGET);
});
