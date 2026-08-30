# 星璃音乐 · 运营后台前端（admin_web）

前后端分离后的**独立静态前端**：`index.html` 为纯静态单文件（原生 HTML+JS，零构建、零依赖），
可部署在任意能托管静态文件的云端服务器 / 对象存储 / CDN / Pages，通过 `/api/admin/*` REST
调用 relay 后端。

## 对接关系

```
[admin_web 静态前端]  --HTTPS/CORS-->  [relay_server 后端 8092]
        │                                    │
        │  GET/POST/PUT/DELETE /api/admin/*  │ 读写
        │  Bearer: relay_server.secret      │ content/*.json + audit.jsonl
        └────────────────────────────────────┘
```

- 前端**不依赖同源**：后端已加 CORS（`Access-Control-Allow-Origin: *` + OPTIONS 预检），
  前端放在任何域名下都能跨域调用。
- 鉴权用 Bearer 密钥 = `relay_server.secret` 内容（密钥轮转后后台凭据同步变更）。
- App（Flutter）只对接 `/api/*` 与 `/ws`，不受本前端部署位置影响。

## 后端地址配置

三种方式（优先级从高到低）：

1. **URL 参数**：访问时带 `?api=https://relay.xxx.xyz`，一次性指定，不持久化。
2. **登录页输入框**：登录界面「后端地址」栏填写后点进入，自动存到 `localStorage`（键 `xingli_admin_api`）。
3. **留空**：走同源 `/api/admin`（前端与后端同域部署时用）。

> 已保存的地址显示在登录页「已存」提示里；登录后顶栏会显示当前后端地址。

## 部署到其他云端服务器

前端只有一个文件 `index.html`，任选一种即可：

### 1. 任意 VPS / 云服务器（nginx 推荐）
```bash
# 把 index.html 放到站点目录，如 /var/www/admin/index.html
sudo tee /etc/nginx/conf.d/admin.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name admin.yourdomain.com;
    root /var/www/admin;
    index index.html;
}
EOF
sudo nginx -s reload
```
访问 `http://admin.yourdomain.com`，登录页填后端地址 + 密钥。

### 2. 对象存储 + CDN（阿里云 OSS / 腾讯云 COS / Cloudflare R2）
- 新建公开读桶，把 `index.html` 上传为 `index.html`；
- 开启静态网站托管并绑定域名（或直接用桶默认域名）；
- 在登录页填后端地址即可。建议同时开启 CDN 加速。

### 3. GitHub Pages / Cloudflare Pages / Vercel / Netlify
- 新建仓库 / 项目，仅放 `index.html` 一个文件；
- 部署后拿到页面 URL，登录页填 `https://relay.xxx.xyz` 即可。

### 4. 本机 / 内网（临时预览）
```bash
# 任选其一
python -m http.server 8000 --directory admin_web
# 或
npx serve admin_web
```
访问 `http://127.0.0.1:8000`，填后端地址 + 密钥。

## 对接前提（跨云调通需全部满足）

- [ ] relay 后端公网可达（如 `relay.xxx.xyz` 经 Cloudflare 隧道转发 8092）
- [ ] 后端版本含 CORS（`relay_server.dart` 含 cl13 改动并已重新编译部署）
- [ ] 浏览器与后端间走 HTTPS（密钥不过明文传输）；本地调试 http 亦可

## 安全提示

- 后台前端可公开部署，但**不要**把 `relay_server.secret` 写进前端代码 / 页面；
  密钥仅由运营人员登录时输入，存浏览器 `localStorage`。
- 密钥泄露 = 后台可被操作，请定期轮转（停服务 → 删 secret → 重启自动生成）。
- 建议给后台域名加访问控制（IP 白名单 / 基础认证），进一步收敛暴露面。
