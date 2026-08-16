# 星璃音乐 · 中转服务器（relay）

让「一起听」与 P2P 联机**跨公网 / 跨 NAT** 互联：房主与好友无需暴露端口、无需端口转发，
全部流量经本中转服务器以**房间**为单位扇出。

> 客户端已有完整的「主机-客户端」联机协议（WebSocket + JSON 信封）。本服务器**不理解任何
> 业务消息**，只做两件事：维护「房间 → 成员」映射，把游戏帧按 `to` 定向投递、否则广播给同房其他成员。

---

## 运行

```bash
cd relay-server
npm install        # 仅依赖 ws
npm start          # 默认 0.0.0.0:8765
# 自定义：
PORT=9001 HOST=0.0.0.0 MAX_PEERS=64 node index.js
```

环境变量：

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | `8765` | 监听端口（与客户端默认一致） |
| `HOST` | `0.0.0.0` | 绑定地址 |
| `MAX_PEERS` | `32` | 单房间成员上限（防滥用） |
| `PING_INTERVAL` | `30000` | 心跳间隔(ms) |

健康探针：`GET /healthz` → `{ ok, rooms, peers, uptime }`

---

## 协议（仅客户端 ↔ 中转）

**控制帧**（JSON，带 `ctl` 字段；否则视为游戏帧）

| 方向 | 帧 | 说明 |
|---|---|---|
| C→S | `{ "ctl":"join", "room":"ROOM", "name":"昵称", "host":true\|false }` | 登记进入房间 |
| S→C | `{ "ctl":"ready", "id":"peerId", "room":"ROOM" }` | 登记成功，分配 peerId |
| S→C | `{ "ctl":"peerJoin", "id":"peerId", "name":"昵称" }` | 房间内有成员加入 |
| S→C | `{ "ctl":"peerLeave", "id":"peerId" }` | 房间内成员离开 |
| S→C | `{ "ctl":"error", "msg":"..." }` | 错误（房间满 / 缺字段） |
| C→S / S→C | `{ "ctl":"ping" }` / `{ "ctl":"pong" }` | 心跳 |

**游戏帧**（无 `ctl`，含业务 `t`/`f`/`p` 字段的 JSON 信封，由客户端 `NetMessage` 定义）

- 带 `to` 字段 → 仅投递给该 peerId（如 `welcome` / `editSnapshot`）。
- 不带 `to` → 广播给同一房间内除发送者外的所有成员（`transform`/`edit`/`vitals`/`chat`/`listenState` 等）。

---

## 部署

### Docker

```bash
cd relay-server
docker build -t xingli-relay .
docker run -d --name xingli-relay -p 8765:8765 --restart=unless-stopped xingli-relay
```

### systemd（裸机 / VPS）

将 `relay.service` 复制到 `/etc/systemd/system/`，并放置 `index.js` 到 `/opt/xingli-relay/`：

```bash
cp relay.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now xingli-relay
```

### 反向代理（Nginx，可选，用于 wss + 域名 + TLS）

```nginx
location /ws {
    proxy_pass http://127.0.0.1:8765;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 3600s;
}
```

客户端连接地址填 `wss://your.domain/ws`。

---

## 公网部署（wss，推荐 · 2026-08-17 cl79 补充）

> 现状：`index.js` 本身是**纯 ws**（无 TLS 代码）；App 大厅默认中转地址是
> `wss://relay.xingli.app/ws`（wss 需域名证书）。因此公网开箱即用 = 在域名
> 前置一层 TLS 终止（nginx / caddy 反向代理 + Let's Encrypt 证书），把
> `wss://relay.xingli.app/ws` 映射到本机 `ws://127.0.0.1:8765/ws`。

### 方案 A：Nginx + certbot（推荐，服务器资源占用低）

```nginx
# /etc/nginx/sites-available/relay.xingli.app
server {
    listen 80;
    server_name relay.xingli.app;
    # certbot 验证用（首次签发后会自动加 443 配置）
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    server_name relay.xingli.app;
    ssl_certificate     /etc/letsencrypt/live/relay.xingli.app/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/relay.xingli.app/privkey.pem;

    # WebSocket 升级必须放行
    location /ws {
        proxy_pass http://127.0.0.1:8765;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # 健康探针（可选暴露）
    location = /healthz { proxy_pass http://127.0.0.1:8765; }
}
```

```bash
# 首次签发证书（certbot 自动改 nginx 配置，也可用上面手写配置）
sudo certbot --nginx -d relay.xingli.app
sudo systemctl reload nginx
```

### 方案 B：Caddy（自动 HTTPS，零配置证书）

```caddyfile
relay.xingli.app {
    reverse_proxy /ws 127.0.0.1:8765
    reverse_proxy /healthz 127.0.0.1:8765
}
```

Caddy 会自动申请并续期 Let's Encrypt 证书，无需手动 certbot。

### 验证

```bash
# 1) 本机直连（纯 ws，自检服务器存活）
curl http://127.0.0.1:8765/healthz

# 2) 经域名（wss 握手 + 健康探针）
curl https://relay.xingli.app/healthz

# 3) 客户端：大厅「中转服务器」→ 地址填 wss://relay.xingli.app/ws →
#    房主建房得 6 位房间号 → 好友填同地址+房间号加入（跨公网即通）。
```

部署完成后，App 内置默认地址 `wss://relay.xingli.app/ws` **开箱即用**，
用户无需改地址。若暂不部署 TLS，也可在客户端把地址改为明文
`ws://relay.xingli.app/ws`（仅限信任网络，明文可被嗅探）。

---

## 客户端对接

App 大厅「连接方式」选择**中转服务器**，填入中转地址（如 `wss://your.domain/ws`）：

- 房主：生成 6 位房间号（或自定义），点「创建并开始」→ 把房间号发给好友。
- 好友：填房间号 + 中转地址 → 加入。

「一起听」随会话自动生效（房主即 DJ，好友跟随曲目 / 进度 / 播放态）。
