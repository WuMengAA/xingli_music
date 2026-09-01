# 记忆 · 2026-09-02 · R32 四项新需求 + VoiceHub 侦查

> 本文件按约定长期持续维护（用户要求必须长期写记忆）。Hindsight 未配置 token 时以本 docs 为记忆兜底。

## 一、用户新指令（2026-09-02，必须长期记忆）

用户原话（R32 四项）：
1. **所有液态玻璃样式改成流畅档位的效果，这样效果最佳** —— 即全部玻璃统一为「流畅」档（liquid_glass_compat 的 `GlassPerformancePreset.smooth`），效果最佳。
2. **底部导航栏需要悬浮在底部之上，可参考 iOS26 应用的设计标准**。
3. **把账号等后端做全**。
4. **电台尽量还原 voicehub 的功能和界面体验；点歌可在底部音乐媒体栏中以悬浮窗形式显示**。
5. 补充强调：**VoiceHub 用的 WebGL 就是「Web 液态玻璃」，正是我一直要求的**；**必须、一定长期写记忆**。

## 二、VoiceHub 侦查（github.com/laoshuikaixue/VoiceHub，已克隆到 D:\Stellara\Music\_voicehub_ref）

- 技术栈：**Nuxt 4 全栈** + Vue + TypeScript + Drizzle ORM + PostgreSQL/Redis（docker-compose / fnos / vercel / netlify 多部署）。
- **WebGL**：依赖 **Pixi.js**（@pixi/app 7.x、@pixi/core、@pixi/filter-blur、@pixi/filter-color-matrix、@pixi/filter-bulge-pinch、@pixi/sprite）——即用户所指的 Web 液态玻璃渲染层。
- 音源：网易云 `@neteasecloudmusicapienhanced/api`、QQ `@sansenjian/qq-music-api`、Bilibili；歌词用 `@applemusic-like-lyrics/*`。
- 账号：bcrypt 密码、OAuth（GitHub/Casdoor）、**WebAuthn**（Passkey/Windows Hello/生物识别/YubiKey）、**2FA（TOTP+邮箱）**、账号锁定、身份关联多平台绑定。
- 核心功能（README）：
  - 智能点歌系统：点歌或投票、网易云/QQ/B站搜索、可选择期望播出时段。
  - 多平台登录：OAuth 快捷注册/绑定、WebAuthn、2FA。
  - 网易云扫码登录：搜个人歌单/收藏/播客电台、一键加入歌单、从歌单/最近播放投票、播客电台投票。
  - 投票限额管理：按时间段+用户角色配置投票额度，控制系统负载。
  - 歌曲去重、歌曲管理（热度排序、防重复播放、动态 URL 防过期、黑名单）。
  - 音乐播放器：内置播放器、进度控制、音质实时切换（标准/HQ/无损/Hi-Res）、动态获取最新播放链接。
  - 歌曲下载（管理员）、歌曲重播申请（用户发起/查看/撤回）。
  - 用户管理：多角色权限（普通/管理员/超级管理员）、按年级班级分类、账号创建方式多样。
  - **排期管理**：拖拽排期、排期草稿（不影响公开展示，可随时修改发布）、播出时段（多时段）、排期复制到另一日期、打印排期（自定义纸张/PDF）、学期管理、公开展示按日期分组。
  - 通知系统：实时通知（歌曲被选中/投票/系统）、通知偏好独立页、批量通知、社交账号绑定同步（如 NeoW）、验证码验证（动态样式反馈）。
  - 数据管理：备份、数据分析、数据库管理、API Key 管理。
- 前端结构：`app/components/`（Account/Admin/AMLL/Player/Songs/UI...）、`app/pages/`（dashboard/login/account/year-review...）。
- 版本 v1.5.9.8；README 含项目截图（B 站宣传视频 BV1B9ArzMEkA）。

## 三、对照星璃音乐现状的差距（电台还原 VoiceHub 的落点）

星璃现有电台：relay_server（房间/点歌 orderSubmit→orderQueue→orderDecision）+ station_lobby/station_room/order_queue 页面 + 聚合搜索。

VoiceHub 可借鉴项（按价值排序）：
- 点歌悬浮窗显示在底部媒体栏（本需求 ④ 明确）。
- 排期管理：拖拽排期 + 草稿 + 播出时段 + 公开按日分组展示（星璃 M4 定时排歌可对齐此交互）。
- 音质实时切换 + 动态获取最新播放链接（星璃已有音质选择，链接防过期可借鉴）。
- 多角色权限 + 投票限额（校园广播场景：按角色/时段限投）。
- 歌曲去重 / 黑名单 / 重播申请。
- 账号体系做全（需求 ③）：bcrypt + 2FA + WebAuthn 太重，星璃可取 bcrypt 密码（当前 relay 已有）+ 完整 profile（改密/资料/头像）。

## 四、R32 玻璃档位落点（已确认）

- `packages/liquid_glass_compat/lib/src/core/performance.dart`：`GlassPerformancePreset`（powerSave/balanced/smooth）+ `kDefaultPerformancePreset`。**已改为 smooth**（R32 定版：所有液态玻璃统一流畅档，效果最佳）。
- `lib/widgets/liquid_glass.dart`：LiquidGlass 构造默认 `GlassQuality.standard`，liquid 走 `premium`；blur 由 performanceModeProvider 决定（quality=16/performance=0）。
- `lib/providers/settings/performance_providers.dart`：PicturePreset 四档（省电/流畅/标准/高质），smooth.blur=4.0、standard=8.0、high=14.0。
- 用户要求「所有液态玻璃样式改成流畅档位」→ 统一走 smooth（blurScale 1.0、SDF 1024、折射色差全开、不降采样）。

## 五、R32 四项落地进度（2026-09-02 已提交，待推送）

1. **玻璃流畅档**：compat 默认改 smooth —— commit 93d47ff ✓
2. **Dock iOS26 悬浮**：ResponsiveFloatingLayer 加 `bottomGap`（AppSize.dockFloatGap=12），AppShell 预留同步 —— commit 93d47ff ✓
3. **账号后端做全**：relay 加 `/api/auth/change-password`（校验旧密码→重加盐）+ profile 支持 `displayName`（昵称≤32）/`avatar`（≤512）；客户端 AuthUser 加 name 派生 + changePassword/updateUserProfile + 账号页资料编辑/改密码 UI —— commit 19bb7e3 ✓
4. **电台还原 VoiceHub + 点歌悬浮窗**：
   - 点歌悬浮窗 `lib/widgets/social/order_floating_card.dart`：挂 AppShell 底部媒体栏上方，DJ 新 pending 自动浮出（通过/拒绝/推入播放），听众显示自己点歌状态，收起为角标 —— commit 79b8e03 ✓
   - 电台房内联点歌队列（待审批/待播放分组可见，VoiceHub 排队体验）—— commit fbf941e ✓

## 六、用户强调（长期记忆硬要求）

- **WebGL 液态玻璃 = 用户一直要求的核心**：VoiceHub 用 Pixi.js/WebGL 做 Web 液态玻璃渲染层。星璃的 `liquid_glass_compat`（WebGL 移植）正是对齐此方向，Dock 已用 WebGL 玻璃，R32 起全站玻璃统一流畅档。
- **必须长期写记忆**：Hindsight 未配置 token（401）时，记忆走 `docs/MEMORY_*.md` 兜底，持续追加。用户已多次批评「不记忆日常 md」，务必坚持。

