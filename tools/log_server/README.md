# 星璃 · 云端日志收集器（log_server）

配套 app「日志上报」功能的**自建服务端**，零依赖 Node 服务。
代码随项目开源托管在 GitHub（`WuMengAA/xingli_music` → `tools/log_server/`），
可部署到任意公网服务器 / VPS / 云主机，或经 Cloudflare Tunnel 内网穿透暴露公网。

## 公网部署总览（G8）

```
App（任意网络） ──HTTPS──▶ logs.example.com ──▶ Cloudflare 隧道 / nginx ──▶ node server.js :8765 ──▶ logs/*.log
```

- **代码**：本目录（GitHub 仓库内），`git clone` 后即可部署；
- **公网入口**：推荐 Cloudflare Tunnel（无需公网 IP、无需改 A 记录，见下）或 nginx + 域名；
- **安全**：日志已脱敏，但公网务必加一层鉴权（Cloudflare Access / nginx basic auth，见下）。

## 启动

```bash
node server.js            # 默认 8765
node server.js 9000       # 指定端口
PORT=9000 node server.js
```

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/logs` | body 为 JSON 数组 `[{ts, level, tag, msg}, ...]`，落盘 `logs/<日期>.log`（JSONL） |
| GET | `/` | 网页查看器：最近 1000 条日志，按级别着色 |
| GET | `/health` | 健康检查 |

限制：单请求 ≤ 256KB / 500 条；单日日志文件 ≤ 64MB（超出丢弃，防刷爆磁盘）。

## 接入 app

1. 把服务部署到你的服务器，域名（如 `logs.example.com`）指向它；
2. app 内：设置 → 关于 → 日志上报 → 填 `https://logs.example.com`（不带 `/api/logs` 后缀），打开开关；
3. 日志会在 app 内脱敏后批量（20 条 / 5 秒）POST 上报。

## 内网穿透：Cloudflare Tunnel（无需公网 IP / 无需改 A 记录）

本仓库提供 `cloudflared.yml` 模板。步骤：

1. Cloudflare 控制台 → Zero Trust → Networks → Tunnels → **Create a tunnel**，
   得到 `<TUNNEL_ID>` 与连接凭据（域名用你提供的，如 `logs.example.com`）；
2. 编辑 `cloudflared.yml`：填入 `<TUNNEL_ID>` 与凭据文件路径；
3. 安装 cloudflared（[官方下载](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)）后运行：

```bash
cloudflared tunnel --config cloudflared.yml run
```

4. 隧道会把 `logs.example.com` 的请求转发到本机 `127.0.0.1:8765`（即日志服务）。
   域名解析由 Cloudflare 自动完成；本机无需公网 IP、无需路由器端口映射。

## 部署建议（nginx 反代示例）

```nginx
server {
    listen 80;
    server_name logs.example.com;
    location / {
        proxy_pass http://127.0.0.1:8765;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

⚠️ **安全**：服务本身无鉴权。日志虽已脱敏，仍建议：
- 仅内网使用；或
- nginx 加 `auth_basic` / 来源 IP 白名单；或
- Cloudflare Access（Zero Trust → Access → Applications）给 `logs.example.com` 加一层登录页。

（systemd 示例：`[Unit]` + `ExecStart=/usr/bin/node /opt/log_server/server.js` + `Restart=always` 即可。）
