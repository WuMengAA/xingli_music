/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 版本规范（R18/R19/R20）
/// ════════════════════════════════════════════════════════════════════════
///
/// 规则（用户 2026-08-09 定版）：
///   `0.26.8.9_alpha_cl01`
///    └┬─┘└┬┘└┬┘└┬┘ └┬┘ └┬┘
///    大版本 年 月 日 阶段 构建次数
///
///  - 大版本：0（早期）
///  - 年/月/日：当日日期（YY.MM.DD）
///  - 阶段：alpha = 阿尔法/早期内测；beta = 内测；rc = 候选；release = 正式
///  - clNN：当日构建次数（01 起，同日每次构建 +1）
///  - 版本代号 [codename]：发版命名（如「星辉」），未定稿为「待定」
///
/// pubspec 的 `version` 字段仍是合法语义版本 `0.YY.MM+DD`，
/// 展示串由本文件统一生成，设置页「关于」展示完整串。
library;

/// 版本阶段。
enum AppStage {
  alpha('alpha', '阿尔法（早期内测）'),
  beta('beta', '贝塔（内测）'),
  rc('rc', '候选发布'),
  release('release', '正式版');

  const AppStage(this.tag, this.label);
  final String tag;
  final String label;
}

/// 版本信息（编译期常量，发版时手动维护）。
abstract final class AppVersion {
  // ── 编辑时手动维护（每次发版更新）──────────────
  // 版本代号演进表（用户 2026-08-11 定版；随阶段推进逐级升级，
  // 只需改 [codename] 一处）：
  //   星尘初聚 —— 星尘开始凝聚，尚未成型
  //   星轨初现 —— 轨迹逐渐清晰，方向显现
  //   星河流转 —— 星河开始流动，状态稳定
  //   星光满照 —— 星光充盈，感知生效
  //   星河静默 —— 星河流动放缓，不再扩展
  //   星尘余响 —— 星尘散去，余响犹在
  // 展示格式：星璃音乐·<代号>

  /// 大版本。
  static const int major = 0;

  /// 年份（两位）。
  static const int year = 26;

  /// 月份。
  static const int month = 8;

  /// 日期。
  /// R26r21：过 00:00 进下一天（按真实日期推进）；次日 cl 清零。
  static const int day = 15;

  /// 阶段。
  static const AppStage stage = AppStage.alpha;

  /// 当日构建次数（01 起；同日每次构建 +1，发版时手动递增，次日清零）。
  /// cl36：安卓切歌防闪退补丁 + 通知系统重做(rootOverlay/多实例堆叠) +
  /// 水面默认关闭(高画质外) + 游戏中返回键(提醒/双击保存退出) +
  /// 存档最近保存时间 + 崩溃界面兜底(ErrorWidget.builder→CrashScreen)。
  /// cl37：生存模式 bug 修复——新建/读档作弊关强制生存(禁创造)、
  /// 饥饿衰减提速至分钟级、进生存保留存档数值(不再 respawn 覆盖)、
  /// 新建存档作弊/浮空岛默认关。
  /// cl38：开放世界地基 P0+P1——编辑层坐标从打包 key(x*65536+z*256+y，
  /// z 锁 0-255/x±32767) 改为 chunk 分桶(cx,cz)+局部编码(任意坐标/负坐标/
  /// 大范围生效，序列化 schema:2、旧档安全跳过)；玩家生存状态抽离为
  /// playerVitalsProvider 单例真相源(Riverpod)，跨系统共享、避免双重 dispose。
  /// cl39：安卓运行时 4 连崩修复——①播放易卡死（占位符解析无超时→加 20s
  /// 超时，loading 不再无限期挂起）；②歌名/曲名对不上（选曲即写 nowPlaying
  /// 与引擎加载成功才写双真源错位→新增 currentTrackProvider+nowPlayingBridge
  /// 桥接统一到引擎真源）；③播网易云源崩溃（resolver 兜底 catch(_) 回落
  /// openPath 打开非法 URI 原生崩→改抛 StreamResolveException，并在 open 分支
  /// 加本地文件护栏，占位符失败绝不 openPath）；④进世界/进存档卡死崩溃
  /// （VoxelMusicEngine().init().then 缺 .catchError→未处理异步错误安卓原生
  /// 崩，与 WorldAudioEngine 路径对称加兜底；_enter 写盘无保护→加 try/catch）。
  /// cl40：安卓「仍卡死」真凶修复——全局播放/进世界 toast（global_notification_toast）
  /// 的 build() 返回 IgnorePointer(child: Positioned(...))，Positioned 被单子组件包裹，
  /// 父用基类 ParentData，强转 StackParentData 失败 → WidgetsBinding.drawFrame 持续抛
  /// _CastError → 主线程重建死循环 → 系统判 ANR（只能强关）；对调层级为
  /// Positioned(child: IgnorePointer(AnimatedBuilder(...))) 修复。另 release 资源压缩
  /// (shrinkResources) 把仅 Dart 引用的 drawable/ic_notification 剥除致通知栏崩溃，
  /// 新增 res/raw/keep.xml 强制保留。
  /// cl41：修复「播 1 秒后静音、须拖主音量条才恢复」。根因=切歌时 playMusic 在
  /// line 350 启动旧曲淡出（_fadeMusic 操作共享 _music 播放器、末步 setVolume(0)），
  /// 但新曲路径（line 369）直接 setVolume 不走 _fadeMusic，_fadeSeq 守卫从未被触发，
  /// 旧淡出在 ~1.5s 后台跑完把新曲音量压成 0。新增 _cancelFades() 在
  /// playMusic/续播/resume 直接 setVolume 前显式作废在途淡出修复。
  /// cl42：体素渲染/UX 大修（10 项用户反馈 #382-#391）。①LOD 默认开启
  /// （lodQualityProvider off→balanced，tiers 非空才采样减面）+ 裙边裂口修复
  /// （-0.5 死区→0.0 闭合微缝）；③④⑤云视距/太阳无极过渡+泛光/向下平行面剔除
  /// 复核；⑥背包物品改为居中 3×9 表格；⑦退出按钮移到背包/合成标签左侧；
  /// ⑧搜索+音质并入底部音乐卡片；⑨游戏内顶部居中液态玻璃播放器（删
  /// _WorldMusicConsole、封存纯色全屏 NowPlayingPage）；⑩音源搜索改弹出式
  /// 底部卡片（全局可调、无风险）。
  /// cl43：②描边视距严重不符根因修复——原硬编码 kEdgeMaxDepth=15.0 二值截断，
  /// 描边在 15 格一刀切、且不论视距 2/4/6/8 都纹丝不动（用户反馈「环绕自身 5 格
  /// 立方圆」）。改为随 camera.far*0.5 派生（夹 [16,72] 面数护栏）+ 末段 30%
  /// 距离 alpha 线性淡出，硬边界环变察觉不到的渐隐；⑨顶部播放器改为顶栏 Column
  /// 子项（防窄屏折行 chips 重叠，旧固定 top:92 同型坑）+ 清孤儿 import。
  /// cl44：④ AudioService 双后端（just_audio + media_kit）并存并按曲源
  /// requiresMediaKit 路由——网易云/B站 CDN 流改走 media_kit（libmpv），
  /// 修复 just_audio 无法解码致无声/进度条空转；②通知栏歌名加载即更新 + 失败
  /// 回退上一首；①关于页更新日志展示。
  /// cl45：①描边只描玩家 5 格内（实描）+5~12 格极淡渐隐、设置可关；②视距不
  /// 硬剔除——相机 far/雾/加载推到 LOD 地平线，LOD 近 2→远 16（可 32）区块
  /// 少面大体积替身、看得更远更流畅，可选边界雾（与 LOD 互斥）；③设置「画面」
  /// 改名「个性」+ 游戏高级画质并入 + 机制并入游戏；④UI 编辑器大补（撤销/重做、
  /// 复制粘贴+多选、对齐/分布/吸附/微调、层级树、预览动画、可点击反馈）；
  /// ⑤均衡器应用失败自动关闭 + 补应用兜底（修复开启后无声/播放失败）。
  /// cl47：cl46-E 组件纠正后重新构建（场景卡片 16:9/长按/去搜索音质由误改的
  /// UnifiedPlayer 迁回真正的 SceneCardStack）+ 修复「视听结合」B站背景视频
  /// 无法播放（open 缺 Referer+UA → CDN 403，已补 httpHeaders 并 video 控制器
  /// 提前创建、_stop 改用 stop()）。
  /// cl48：底部导航重做（主页/曲库/世界/探索/设置 5 Tab）+ 场景页合并进主页
  /// （去掉独立场景路由，HomePage 复用场景内容组件）+ 新增 WorldPage
  /// 复用体素世界主菜单作星璃世界入口。
  /// cl46：①全局数据层——听歌总时长/单曲播放次数（收录进歌曲卡片）、
  /// 全局收藏 + 全局歌单（自定义名/相册背景图/排序）、听歌历史自动收录
  /// （相似歌名/歌手询问归并、与歌单联动）；②自动播放（默认开）+ 曲末 5 秒
  /// 淡出淡入过渡 + 后台播放；③场景中间卡片 16:9 + 长按开场景个性 + 去搜索/
  /// 音质 + B站视听结合（歌名自动匹配视频背景，白噪音旁快捷开关）；④设置重组
  /// （游戏画面/机制统统迁入游戏：画质卡片预设/分辨率/帧率 3~60+无限制/阴影
  /// + 机制存档/世界/自定义世界偏移率）；⑤渲染修复——分辨率缩放 buildFrame
  /// 与 paint 同步（修只显示左上角）、可见集洪泛半径收敛（低视距不再 17×17）、
  /// LOD 默认扩到 32 区块。
  /// cl49：游戏页竖屏布局修复——①HUD 控件随屏幕自适应（新增 hudResponsiveScale，
  /// 摇杆/动作键/顶栏按钮按视口短边缩放、加不透明命中区）；②底部物品栏按可用宽度
  /// 自适应槽位尺寸，竖屏窄屏不再横向溢出；③2.5D 音效画布按约束反推瓦片尺寸，
  /// 整张等距网格在竖屏/横屏都完整显示（不再左右裁切）。
  /// cl50：场景卡片体验——①场景卡片背景浓度可调（新增 sceneCardOpacityProvider，
  /// 默认 0.25、设置「个性→场景→场景卡片透明度」滑块自调，越低越通透露出视频
  /// 背景）；②歌词移入场景卡片右半区（占 1/2 宽），无歌词时右半区折叠、整卡居中。
  /// cl51：播放记录系统——①重播直链重匹配（新增 playback_relink_provider：
  /// 已解析直链缓存 resolved_links 表，再次播放优先用缓存近似链接，未过期
  /// 直接播；过期则按来源重新解析；源失败再按 近似名称+时长+歌手 聚合搜索
  /// 网易云/B站自动匹配最优曲目）；②上下歌切换考虑播放记录（新增
  /// recordPlayOrderProvider：按最近播放推导顺序，顺序/倒序模式下下一首按
  /// 播放记录走而不是字母序，场景默认曲目未命中时优先取最近播过的曲目）。
  /// cl52：音乐卡片重构 + 界面统一①——①音乐卡片按钮重排：歌词钮移到
  /// 音量右、上一首左；收藏移到循环模式右；白噪音+视听+均衡器并入底部
  /// 操作行（音质右边，均衡器为图标形式）；header 只保留放大+折叠；
  /// 歌词可点钮在卡片内展开（不再只存在于全屏）。②主页视频背景顶部圆角。
  /// cl53：①四宫格去 3D——移除主页 grid_view 入口弹层，3D 世界从「世界」
  /// Tab 进入；配色面板迁入「长按场景卡→编辑场景」页。②游戏误排的全局
  /// 个性归位「个性→画面特效」（图形后端/噪点/玻璃模糊/背景动画/液态玻璃/
  /// 全局画面预设）。③动效系统：全局页面过渡（淡入+轻上滑，浅/深主题统一）。
  /// ④视频背景跟随音乐播放状态（暂停/播放同步）+ 四角圆角。
  /// ⑤报错通知统一走全局通知（多并行竖向）。⑥非主页内容区底部圆角衔接
  /// 音乐卡。
  /// cl54：①B站视频画质默认 360p，可选 720/1080/大会员 1080 60fps（DASH
  /// 按清晰度 id 精确选档）；②修复播放顺序无法应用（recordPlayOrderProvider
  /// 首帧 .valueOrNull 为 null 导致回退字母序，改 await future）；
  /// ③全局画面预设重构四档（省电/流畅/标准/高质，含简介与省电提醒、帧率联动）；
  /// ④设置-关于-存储（软件占用空间统计）。
  /// cl55：设置-关于 新增「版本日志」（自动获取最新，changelog 倒序首条即最新）
  /// +「版本更新」（OTA 入口，G7 接入 GitHub/官网检查→下载→哈希校验→提醒）。
  /// cl56：G7 开源 + OTA——新增 OtaService（检查 GitHub Releases→比对构建号→
  /// hotfix 直下→SHA-256 校验），版本更新面板接入真实链路；开源配套
  /// LICENSE(MIT) + GitHub Actions 发布工作流（tag cl*/v* 自动构建 APK+校验
  /// 文件并发布 Release）。
  /// cl57：G8 公网日志服务器（服务端 Node + Cloudflare 公网隧道，代码托管
  /// GitHub）+ F4 OOBE 重做（10 步初始化：欢迎/界面介绍/个性化/游戏画质/
  /// 隐私安全/通知权限/实验性功能/版本日志/更新检查/用户协议+完成；版本升级
  /// 弹询问重走；数据保护「合并且不清除数据」提示；设置-关于-初始化流程入口）。
  /// cl58：OOBE 升级——每步配**简单示意图**（底部导航/预设档/画质档/盾/铃/试管/
  /// 日志/更新/协议等纯 Flutter 图示）；「个性化」直接选全局画面预设四档、
  /// 「游戏画质」直接选游戏画质档（即时写入 provider）；**老用户不再反复打扰**
  /// ——无完成版本记录或已处理过当前版本都不再弹升级询问。
  /// cl59：OOBE 交互细化——隐私/安全【索要权限】、通知【索要通知权限】、
  /// 实验性功能【同意/不同意】、版本日志【拉取本地日志前 3 条】、版本检查
  /// 【按流程检查，有更新提示/超时提示继续】、用户协议【贴 GitHub 仓库与
  /// LICENSE 链接】；设置-关于 加 GitHub 仓库行（含分支标注 main）。
  /// cl60：GitHub 开源 + OTA 发布链路打通——代码推送 github.com/WuMengAA/xingli_music
  /// main 分支，打 tag（cl*/v*）触发 GitHub Actions 自动构建 APK + sha256 并发布
  /// Release；应用内「设置→关于→版本更新」即可检测 / 下载 / 哈希校验 / 安装新版本。
  /// cl61：OTA 下载体验升级 + 版本号进入 0.26.8.15——①下载显示实时进度（进度条/
  /// 百分比/已下载-总量/实时网速）；②**挂后台下载**（全局 otaDownloadProvider 单例，
  /// 关闭更新页下载继续，完成/失败由 AppShell 常驻监听弹全局通知）；③版本号按日期
  /// 推进 day 14→15、buildCount 60→61（0.26.8.15_alpha_cl61），从此版起 OTA 可自动更新。
  /// cl62：G9 多人联机地基——①零依赖 P2P 网络层（dart:io WebSocket 传输 + UDP 局域网
  /// 发现，无第三方库）；②大厅页（创建主机 / 输入 IP 加入 / 局域网扫描）；③VoxelWorldView3D
  /// 接入联机：同步方块编辑 + 玩家机位（位置/朝向/视角模式）；一起听（主机为 DJ）架构就位，
  /// 待下一版接通；buildCount 61→62（0.26.8.15_alpha_cl62）。
  /// cl63：G9 多人联机功能打通——①修复静止快照下远端编辑/玩家不重绘（清 _staticPicture
  /// + 新增 _forceRebuild 并入重建门控，本地相机静止也能即时重绘）；②世界内联机 HUD
  /// （角色/房主地址/同伴列表/一起听状态 + 一键离开）；③断线覆盖层（status==error 居中
  /// 提示 + 返回大厅）；一起听（主机为 DJ）客户端跟随播放随地基接通；buildCount 62→63
  /// （0.26.8.15_alpha_cl63）。
  /// cl64：G9 多人联机增强——体素世界内为联机同伴方块人头顶渲染浮动名字标签
  /// （按同伴名字区分多人；半透明胶囊 + 实体主色描边；与太阳月亮同坐标系，
  /// 转视角/远端移动实时跟随；静态快照下也始终可见）；buildCount 63→64
  /// （0.26.8.15_alpha_cl64）。
  /// cl66：G9 多人联机·编辑层快照同步——新/(重)加入玩家加入即看到他人已建结构。
  /// 主机在成员接入(NetPeerConnected)时主动下发权威编辑层快照（已变方块+发光方块，
  /// 地形由 seed 确定性复现不同步），客户端收到后 loadJson 应用到本地世界并强制整帧
  /// 重建；客户端 world 视图注册 onEditSnapshot 后主动 requestEditSnapshot，规避
  /// 「welcome/Snapshot 早于视图回调注册」竞态，与主机主动下发幂等互不影响；
  /// 重连沿用同一通道（主机视重连为全新连接，快照再次下发）。buildCount 65→66
  /// （0.26.8.15_alpha_cl66）。
  /// cl75：OOBE 初始化流程重做·六支柱（内容/展示/选择/询问/意见采纳/合同）——
  /// ①结构重构：欢迎 + 内容（核心价值）+ 展示（能力卡片）+ 选择（音质/外观/皮肤/
  ///   画质即时落库）+ 询问（常听场景多选 + 匿名体验改进同意）+ 意见采纳（选择
  ///   汇总可回改）+ 合同（条款可展开 + 真链接可点 + 必勾同意）+ 完成，共 8 页；
  /// ②全程去除内部标识：欢迎与各步骤不再出现版本号、构建号、changelog 等自报内容；
  /// ③协议链接真正可点开：新增 open_url 原生通道（零新依赖，呼应 cl74 ota_install
  ///   思路），合同页链接经 Intent.ACTION_VIEW 调系统浏览器，非 Android 回退复制；
  /// ④新增 OOBE 选择/询问持久化：audioQuality / analyticsConsent / listenSources
  ///   三字段落 SettingsRepository，冷启动 restoreSettings 灌回、运行期 settingsSync
  ///   写回；选择即时写入对应 provider（非摆设）；
  /// ⑤修复完成页不可达（原 off-by-one：完成页被错当协议页直接结束）；权限申请
  ///   移入完成流程末尾静默请求（requestEssentialOnStartup）；buildCount 74→75
  ///   （0.26.8.15_alpha_cl75）。
  /// cl74：OTA 端到端打通·启动自动检查 + 下载后真安装——
  /// ①自动检查：AppShell.initState 启动后自动查一次 GitHub Releases（仅已完
  /// 成 OOBE 的老用户），有新版本弹全局提示引导去 设置→关于→版本更新；
  /// ②checkForUpdate 健壮性：原只取列表第一个非 draft Release、依赖 GitHub
  /// 返回顺序，改为遍历所有非 draft Release 取**最大构建号**（hotfix 预发布
  /// 仍纳入、语义版本 tag 解析为 -1 跳过），顺序变化不再取错版本；
  /// ③安装链路补齐（此前整条缺失）：新增 REQUEST_INSTALL_PACKAGES 权限 +
  /// FileProvider(res/xml/file_paths.xml) + MainActivity 的 ota_install
  /// MethodChannel（FileProvider.getUriForFile → ACTION_VIEW + 授权 URI
  /// 权限）+ Dart 侧 OtaInstall.install；版本更新页下载完成后按钮变为可点的
  /// 「安装更新」，AppShell 下载完成通知带「安装」动作。Android 8+ 真正能装；
  /// buildCount 73→74（0.26.8.15_alpha_cl74）。
  /// cl73：UI 流畅度优化·消除 UnifiedPlayer 进度/音量拖动整树重建——
  /// UnifiedPlayer 是 1219 行 ConsumerStatefulWidget，原进度条/音量拖动都放在
  /// 父级 setState 中执行 → 拖动时每帧重建整棵小部件树（含 3D 场景背景、歌词、
  /// 列表等无关子树），是播放器交互卡顿主因。最低风险隔离：①进度条抽成自包含
  /// _ProgressSlider（ConsumerStatefulWidget），进度/时长 watch 与拖动态内移、
  /// 只重建自身，onSeek 回调执行实际 seek；两处调用点（紧凑态/全屏态）改为
  /// _ProgressSlider(onSeek: (double v) => unawaited(ref.read(audioServiceProvider)
  /// .seek(...)))；从两个 State 移除 _seeking/_seekMs、删除 _buildProgressSlider
  /// 中转函数；②音量面板两处调用点外包 Consumer，使 8 个音量 provider watch 下沉
  /// 到廉价子树、音量拖动只重建小面板而非整树（_VolRow 滑块逻辑字节级不变）。
  /// 两者均不改 UI/交互、回归风险近零；buildCount 72→73（0.26.8.15_alpha_cl73）。
  /// cl72：UI 流畅度优化·液态玻璃模糊层 RepaintBoundary 隔离——
  /// LiquidGlass(frosted) 的 BackdropFilter 此前未做任何图层隔离：内容区内的
  /// 逐帧重绘（歌词滚动 / 进度条 tick / Dock 指示器 AnimatedContainer / 页面
  /// 滚动）会污染其所在图层，迫使每帧对整片背景重新采样 + 高斯模糊（ContentContainer
  /// 的毛玻璃铺满整屏、影响最大，是中低端机 UI 卡顿主因之一）。在唯一一处
  /// BackdropFilter（liquid_glass.dart）的 child 外包 RepaintBoundary，使模糊层
  /// 只在背景（AppShell 玻璃层 / 场景背景，二者本身已各自 RepaintBoundary 化）
  /// 变化时重算、内容动画不再连累模糊；一次性覆盖全部 7 个调用点（ContentContainer
  /// / AppDock / ThemeSwitchButton / UnifiedPlayer×2 / AlbumCard / CardStack），
  /// 视觉零变化；buildCount 71→72（0.26.8.15_alpha_cl72）。
  /// cl71：渲染性能优化·消除云层 _cloudQuad 每帧堆分配（cl68-O4/cl69/cl70 同源收尾）——
  /// 云层每帧约 100 面（默认 cloudChunks=3 → ±48 格 / 7 格间距，噪声筛掉约半数），
  /// 原每云面经 `<double>[12]`（4 角世界坐标）+ `Float32List(8)`（投影缓冲）两次堆分配，
  /// 每帧约 200 次小分配（GC 压力，虽小于地形/实体但属同序列残留）。改为复用模块级
  /// 单例 scratch（_cloudQuadScratch / _cloudXyScratch），发射路径零堆分配。
  /// _cloudQuad 同步消费两缓冲（projectWith 投影 → pushFace 首行即取标量拷贝入批量缓冲、
  /// 不持有引用；_emitClouds 顺序调用、每面同步消费完才返回），复用安全、视觉零变化；
  /// 至此地形 / LOD / 实体 / 云四类每帧发射路径的每帧堆分配已全部清零；
  /// buildCount 70→71（0.26.8.15_alpha_cl71）。
  /// cl70：渲染性能优化·消除实体 _emitBox / _skinUV 每帧堆分配（cl68-O4/cl69 同源收尾）——
  /// 实体（玩家/同伴/掉落物）每个 _emitBox 原每 box 分配 8 角 list + 6 个 12 元素
  /// quad list + faceOrder list + 每面 Float32List(8) 投影缓冲；_skinUV 每皮肤面
  /// 再分配 record list + Float32List(8)。改为复用模块级单例 scratch（_boxCorners
  /// 24 槽 / _boxXyScratch / _skinUvScratch）+ 常量查表（_boxQuadIdx / _boxFaceOrder
  /// / _skinUvLocal：原始 (x0-x0)/dx 等恒为 0/1 → 全 face 同一 UV 模式），发射路径零堆分配。
  /// _emitBox 同步写入并消费各缓冲（pushFace 首行即取标量拷贝入批量缓冲、不持有引用；
  /// _skinUV 返回 _skinUvScratch 仅同步传给 pushFace），复用安全、视觉零变化；
  /// buildCount 69→70（0.26.8.15_alpha_cl70）。
  /// cl69：渲染性能优化·消除 LOD 发射路径每帧堆分配（cl68-O4 同源收尾）——
  /// LOD 马赛克从满精度带外覆盖到地平线，单元数可达数千，原每单元每面经
  /// `_emitLodQuad(Float64List.fromList(...))` 堆分配 12 元组 + 内部
  /// `Float32List(8)` 投影缓冲，每帧数万次分配（GC 压力）。改为复用模块级
  /// 单例 scratch（_lodQuadScratch / _lodXyScratch）+ _fillLodQuad 填充辅助，
  /// 发射路径零堆分配；`_emitLodQuad` 同步消费两缓冲（pushFace 首行即取标量
  /// 拷贝入批量缓冲、不持有引用），复用安全、视觉零变化；buildCount 68→69
  /// （0.26.8.15_alpha_cl69）。
  /// cl68：渲染性能优化·消除每帧冗余 RenderFace 分配与扫描浪费——
  /// 体素渲染统一走 8 深度桶批量提交（GPU drawVertices），移除每帧为回退路径
  /// 分配的万级 RenderFace 对象及其 O(n) 排序/裁剪（回退仅在桶全空时触发，
  /// 视觉零变化）；场景背景画家同步迁移到桶路径。LOD 开启时满精度扫描半径
  /// 收紧到 kFullBand（带外由 LOD 马赛克覆盖、循环守卫已限制），消除
  /// (vd²-kFullBand²) 区块空遍历；buildCount 67→68（0.26.8.15_alpha_cl68）。
  /// cl67：G9 多人联机·编辑层按玩家位置范围同步——在 cl66 全量快照基础上细化
  /// 为「只同步自身周围 N 格区块」：主机按请求者机位就近裁剪回发，客户端加入/
  /// 重连/机位跨 chunk 时按需拉取与卸载，大世界不再全量淹没；新增
  /// [VoxelWorld.editLayerJsonNear]（Chebyshev 距离裁剪）+ [mergeEditLayer]
  /// （合并式应用，不清空本地远处编辑）；主机不再于接入时全量下发，改由客户端
  /// 按机位 requestEditSnapshot；buildCount 66→67（0.26.8.15_alpha_cl67）。
  /// cl65：G9 多人联机·断线重连——客户端掉线/切后台/锁屏后自动重试连接并恢复
  /// 会话（指数退避，1.5s 起、封顶 8s、最多 12 次；重连期间世界全程继续渲染，
  /// 非致命「重连中…」覆盖层取代原致命「连接已断开」）；重连成功后重写远端玩家
  /// 缓存（清旧连接 id，避免重连后出现重复方块人）；主动离开/超上限转致命错误
  /// 引导返回大厅；buildCount 64→65（0.26.8.15_alpha_cl65）。
  static const int buildCount = 75;

  /// 版本代号（见上方演进表；当前阶段「星尘初聚」）。
  static const String codename = '星尘初聚';

  // ── 派生 ────────────────────────────────────────
  /// 语义版本（pubspec version 的展示版）：`0.26.8+11`。
  static String get semver => '$major.$year.$month+$day';

  /// 完整展示串：`0.26.8.11_alpha_cl01`。
  static String get display =>
      '$major.$_yy.$_mm.$_dd${_stageSuffix}_cl${buildCount.toString().padLeft(2, '0')}';

  /// 品牌式展示：`星璃音乐·星尘初聚`。
  static String get brand => '星璃音乐·$codename';

  /// 设置页/关于页短展示（无 cl）：`0.26.8.10_alpha`。
  static String get displayShort => '$major.$_yy.$_mm.$_dd$_stageSuffix';

  static String get _yy => year.toString().padLeft(2, '0');
  static String get _mm => month.toString().padLeft(2, '0');
  static String get _dd => day.toString().padLeft(2, '0');
  static String get _stageSuffix => stage == AppStage.release ? '' : '_${stage.tag}';
}

/// ════════════════════════════════════════════════════════════════════════
/// 更新日志（用户 2026-08-15 要求：关于页展示）
/// ════════════════════════════════════════════════════════════════════════
///
/// 每条记录一次构建的核心变更；按时间倒序（最新在前）。详情用要点列出，
/// 避免长段落。版本串与 [AppVersion.display] 同源（大版本.年.月.日_阶段_clNN）。

/// 单条更新日志。
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.cl,
    required this.title,
    required this.details,
  });

  /// 版本串（如 `0.26.8.14`）。
  final String version;

  /// 构建号（如 `cl43`）。
  final String cl;

  /// 一句话标题。
  final String title;

  /// 变更要点（2~5 条）。
  final List<String> details;
}

/// 更新日志（倒序，最新在前）。
const List<ChangelogEntry> changelog = <ChangelogEntry>[
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl75',
    title: 'OOBE 初始化流程重做：内容·展示·选择·询问·意见采纳·合同',
    details: <String>[
      '六支柱重构：欢迎 + 内容（核心价值）+ 展示（能力卡片）+ 选择（音质/外观/皮肤/画质即时落库）+ 询问（常听场景多选 + 匿名体验改进同意）+ 意见采纳（选择汇总可回改）+ 合同（条款可展开 + 真链接可点 + 必勾同意）+ 完成，共 8 页',
      '全程去除内部标识：欢迎与各步骤不再出现版本号、构建号、changelog 等自报内容',
      '协议链接真正可点开：新增 open_url 原生通道（零新依赖，呼应 cl74 ota_install），合同页链接经 Intent.ACTION_VIEW 调系统浏览器，非 Android 复制兜底',
      '新增 OOBE 选择/询问持久化：audioQuality / analyticsConsent / listenSources 三字段落 SettingsRepository，冷启动 restoreSettings 灌回、运行期 settingsSync 写回；选择即时写 provider（非摆设）',
      '修复完成页不可达（原 off-by-one：完成页被错当协议页直接结束）；权限申请移入完成流程末尾静默请求；buildCount 74→75（0.26.8.15_alpha_cl75）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl74',
    title: 'OTA 端到端打通：启动自动检查 + 下载后真安装',
    details: <String>[
      '启动自动检查：AppShell 启动后自动查一次 GitHub Releases（仅老用户），有新版本弹全局提示引导去 设置→关于→版本更新',
      'checkForUpdate 健壮性：遍历所有非 draft Release 取最大构建号，不再依赖 GitHub 返回顺序（hotfix 预发布仍纳入）',
      '安装链路补齐（此前整条缺失）：REQUEST_INSTALL_PACKAGES 权限 + FileProvider + MainActivity ota_install 通道 + Dart 侧 OtaInstall.install',
      '下载完成后版本更新页按钮变为可点「安装更新」，AppShell 下载完成通知带「安装」动作，Android 8+ 真正能装；buildCount 73→74（0.26.8.15_alpha_cl74）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl73',
    title: 'UI 流畅度优化：消除播放器进度/音量拖动整树重建',
    details: <String>[
      'UnifiedPlayer 是 1219 行 ConsumerStatefulWidget，原进度条/音量拖动都在父级 setState 中执行 → 拖动时每帧重建整棵小部件树（含 3D 场景背景、歌词、列表等无关子树），是播放器交互卡顿主因',
      '进度条抽成自包含 _ProgressSlider（ConsumerStatefulWidget）：进度/时长 watch 与拖动态内移、只重建自身，onSeek 回调执行实际 seek；两处调用点（紧凑态/全屏态）改用 _ProgressSlider，删除原 _buildProgressSlider 中转函数与两个 State 的 _seeking/_seekMs',
      '音量面板两处调用点外包 Consumer，使 8 个音量 provider watch 下沉到廉价子树、音量拖动只重建小面板而非整树（_VolRow 滑块逻辑字节级不变）',
      '两者均不改 UI/交互、回归风险近零；buildCount 72→73（0.26.8.15_alpha_cl73）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl72',
    title: 'UI 流畅度优化：液态玻璃模糊层 RepaintBoundary 隔离',
    details: <String>[
      'LiquidGlass(frosted) 的 BackdropFilter 此前未做任何图层隔离：内容区内的逐帧重绘（歌词滚动 / 进度条 tick / Dock 指示器 AnimatedContainer / 页面滚动）会污染其所在图层，迫使每帧对整片背景重新采样 + 高斯模糊',
      '在唯一一处 BackdropFilter（liquid_glass.dart）的 child 外包 RepaintBoundary，使模糊层只在背景变化时重算；一次性覆盖全部 7 个调用点（ContentContainer 全屏 / AppDock / ThemeSwitchButton / UnifiedPlayer×2 / AlbumCard / CardStack），视觉零变化',
      'ContentContainer 的毛玻璃铺满整屏、影响最大，隔离后滚动歌词 / 拖动进度条不再每帧触发全屏重模糊，中低端机 UI 卡顿主因之一消除',
      'buildCount 71→72（0.26.8.15_alpha_cl72）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl71',
    title: '渲染性能优化：消除云层 _cloudQuad 每帧堆分配',
    details: <String>[
      '云层每帧约 100 面（默认 cloudChunks=3 → ±48 格 / 7 格间距，噪声筛掉约半数），原每云面经 <double>[12]（4 角世界坐标）+ Float32List(8)（投影缓冲）两次堆分配，每帧约 200 次小分配',
      '改为复用模块级单例 scratch（_cloudQuadScratch / _cloudXyScratch），发射路径零堆分配',
      '_cloudQuad 同步消费两缓冲（projectWith 投影 → pushFace 首行即取标量拷贝入批量缓冲、不持有引用；_emitClouds 顺序调用、每面同步消费完才返回），复用安全、视觉零变化（cl68-O4/cl69/cl70 同源收尾）',
      '至此地形 / LOD / 实体 / 云四类每帧发射路径的每帧堆分配已全部清零；buildCount 70→71（0.26.8.15_alpha_cl71）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl70',
    title: '渲染性能优化：消除实体 _emitBox / _skinUV 每帧堆分配',
    details: <String>[
      '实体（玩家/同伴/掉落物）每个 _emitBox 原每 box 分配 8 角 list + 6 个 12 元素 quad list + faceOrder list + 每面 Float32List(8) 投影缓冲；_skinUV 每皮肤面再分配 record list + Float32List(8)',
      '改为复用模块级单例 scratch（_boxCorners 24 槽 / _boxXyScratch / _skinUvScratch）+ 常量查表（_boxQuadIdx / _boxFaceOrder / _skinUvLocal：原始 (x0-x0)/dx 等恒为 0/1 → 全 face 同一 UV 模式），发射路径零堆分配',
      '_emitBox 同步写入并消费各缓冲（pushFace 首行即取标量拷贝入批量缓冲、不持有引用；_skinUV 返回缓冲仅同步传给 pushFace），复用安全、视觉零变化（cl68-O4/cl69 同源收尾）',
      'buildCount 69→70（0.26.8.15_alpha_cl70）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl69',
    title: '渲染性能优化：消除 LOD 发射路径每帧堆分配',
    details: <String>[
      'LOD 马赛克（满精度带外→地平线，单元数可达数千）原每单元每面经 Float64List.fromList 堆分配 12 元组 + _emitLodQuad 内部 Float32List(8) 投影缓冲，每帧数万次分配（GC 压力）',
      '改为复用模块级单例 scratch（_lodQuadScratch / _lodXyScratch）+ _fillLodQuad 填充辅助，发射路径零堆分配',
      '_emitLodQuad 同步消费两缓冲（投影→着色→pushFace 首行即取标量拷贝入批量缓冲、不持有引用），复用安全、视觉零变化（cl68-O4 同源收尾）',
      'buildCount 68→69（0.26.8.15_alpha_cl69）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl68',
    title: '渲染性能优化：消除每帧冗余 RenderFace 分配与扫描浪费',
    details: <String>[
      '体素渲染统一走 8 深度桶批量提交（GPU drawVertices）；移除每帧为回退路径分配的万级 RenderFace 对象与其 O(n) 排序/裁剪（回退仅在桶全空时触发，视觉零变化）',
      '场景背景（音乐播放器体素场景）画家同步迁移到桶路径，与原顶点色平涂视觉一致',
      'LOD 开启时满精度扫描半径收紧到 kFullBand：带外由 LOD 马赛克覆盖、循环守卫已限制在内，消除 (vd²-kFullBand²) 区块空遍历',
      'buildCount 67→68（0.26.8.15_alpha_cl68）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl67',
    title: 'G9 多人联机·编辑层按玩家位置范围同步：只同步周围区块',
    details: <String>[
      '在 cl66 全量快照基础上细化：不再全量下发，只同步本地玩家周围 N 格区块的编辑（主机按请求者机位裁剪）',
      '客户端加入 / 重连 / 机位跨 chunk 时按需拉取与卸载，离开原范围后远端新区块编辑补齐，大世界不再全量淹没网络与内存',
      '新增 editLayerJsonNear（Chebyshev 距离裁剪）+ mergeEditLayer（合并式应用，保留本地远处编辑）；主机不再接入时全量下发，改由客户端按机位请求',
      'buildCount 66→67（0.26.8.15_alpha_cl67）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl66',
    title: 'G9 多人联机·编辑层快照同步：加入即见他人已建结构',
    details: <String>[
      '新/(重)加入玩家加入即看到他人已建造的结构（此前只收到 seed 基础地形，看不到他人编辑）',
      '主机在成员接入时主动下发权威编辑层快照（已变方块 + 发光方块；地形由 seed 确定性复现，仅不同步编辑层）',
      '客户端收到快照后 loadJson 应用到本地世界并强制整帧重建，与实时 edit 增量广播无缝衔接',
      '客户端注册回调后主动 requestEditSnapshot，规避「welcome/Snapshot 早于 world 视图注册」竞态；buildCount 65→66（0.26.8.15_alpha_cl66）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl65',
    title: 'G9 多人联机·断线重连：掉线自动恢复会话',
    details: <String>[
      '客户端掉线 / 切后台 / 锁屏后自动重试连接并恢复联机会话（指数退避，1.5s 起、封顶 8s、最多 12 次）',
      '重连期间世界全程继续渲染，非致命「重连中…」覆盖层（带进度圈 + 第 N 次尝试）替代原致命「连接已断开」',
      '重连成功后重写远端玩家缓存（清旧连接 id，避免重连后出现重复方块人）',
      '主动离开 / 超过重连上限转致命错误，引导返回大厅；buildCount 64→65（0.26.8.15_alpha_cl65）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl64',
    title: 'G9 多人联机增强：世界内远端玩家名字标签',
    details: <String>[
      '体素世界内为联机同伴方块人头顶渲染浮动名字标签，按同伴名字区分多人',
      '半透明胶囊 + 实体主色描边，白字高对比，任意背景（天空/地形/水下）清晰可读',
      '标签与太阳月亮同坐标系（相机投影），转视角 / 远端移动实时跟随',
      '静态快照模式下仍始终可见（HUD 不随场景冻结）；buildCount 63→64（0.26.8.15_alpha_cl64）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl63',
    title: 'G9 多人联机功能打通：即时重绘 + 联机 HUD + 断线处理',
    details: <String>[
      '修复静止快照下远端方块编辑/玩家移动不重绘（清 _staticPicture + 强制重建门控 _forceRebuild）',
      '世界内联机 HUD：角色 / 房主地址 / 同伴列表 / 一起听状态 + 一键离开',
      '断线覆盖层：连接丢失（status==error）时居中提示并引导返回大厅',
      '一起听（主机为 DJ）客户端跟随播放随地基接通，无需人工操作',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl62',
    title: 'G9 多人联机地基：P2P 网络层 + 大厅 + 世界视图接入',
    details: <String>[
      '零依赖联网：dart:io WebSocket 传输 + RawDatagramSocket UDP 局域网发现（无第三方库）',
      '大厅页：创建主机（种子 + 世界选项 + 生存/创造）/ 输入 IP 端口加入 / 局域网扫描列表',
      'VoxelWorldView3D 接入联机：同步方块编辑 + 玩家机位（位置/朝向/视角模式）',
      '一起听（主机为 DJ）架构就位，下一版接通播放同步',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.15',
    cl: 'cl61',
    title: 'OTA 下载体验升级：实时进度 / 网速 + 挂后台下载（版本进入 0.26.8.15）',
    details: <String>[
      '更新下载显示实时进度：进度条 + 百分比 + 已下载/总量 + 实时网速（MB/s）',
      '支持后台下载：关闭「版本更新」页后下载继续，完成/失败由全局通知提示（可并行处理其他事）',
      'SHA-256 哈希校验通过才提示安装，防篡改',
      '版本号按日期推进：0.26.8.14 → 0.26.8.15（cl60 → cl61）；从此版起 OTA 自动更新可用',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl60',
    title: 'GitHub 开源 + OTA 自动更新链路打通',
    details: <String>[
      '代码已推送开源仓库 github.com/WuMengAA/xingli_music（main 分支，MIT 协议）',
      '打 tag（cl*/v*）自动触发 GitHub Actions 构建 APK + SHA-256 校验文件并发布 Release',
      '应用内「设置 → 关于 → 版本更新」接入 OTA：自动检查 GitHub Releases，发现新版本可下载',
      '下载后校验 SHA-256 哈希，防篡改；hotfix 版本（tag 含 -hotfix）免确认直接下载',
      '本机 git 凭据已自动配置（Windows 凭据管理器 OAuth token），推送无需手动输密码',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl59',
    title: 'OOBE 交互细化：权限 / 实验 / 更新检查 / 协议链接 + 关于页 GitHub 入口',
    details: <String>[
      '隐私与安全步骤可「索要权限」；通知步骤可「索要通知权限」',
      '实验性功能步骤可选择「同意 / 不同意」（持久化，可随时在设置实验管理改）',
      '版本日志步骤拉取本地更新日志（展示最近 3 条）',
      '版本检查步骤按流程走一遍：有更新提示更新，超时/无更新提示继续初始化',
      '用户协议步骤贴 GitHub 仓库与开源协议链接',
      '设置 → 关于 新增 GitHub 仓库行（含主分支 main 标注）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl58',
    title: 'OOBE 升级：示意图 + 引导中直接选配置，老用户不再反复打扰',
    details: <String>[
      '初始化流程每步配简单示意图（底部导航 / 预设档 / 画质档 / 隐私 / 通知 / 实验 / 日志 / 更新 / 协议）',
      '「个性化」步骤可直接选择全局画面预设四档（省电 / 流畅 / 标准 / 高质），即时生效',
      '「游戏画质」步骤可直接选择游戏画质档（极低 / 低 / 中 / 高）',
      '已过一遍的老用户不再被反复打扰：无完成版本记录或已处理过当前版本都不再弹升级询问',
      '弹过升级询问后（无论跳过还是重走）记录当前版本，避免每次启动重复弹窗',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl57',
    title: '公网日志服务器 + OOBE 初始化流程重做（10 步）',
    details: <String>[
      '日志上报服务端开源托管（tools/log_server）：零依赖 Node 服务 + 网页查看器 + Cloudflare Tunnel 公网部署模板',
      'OOBE 重做为 10 步初始化：欢迎 / 界面介绍 / 个性化 / 游戏画质 / 隐私与安全 / 通知权限 / 实验性功能 / 版本日志 / 更新检查 / 用户协议+完成',
      '版本升级检测：检测到构建号升级后弹窗询问是否重新走初始化流程',
      '数据保护：检测到已有数据时醒目提示「合并且不清除数据」，重走流程绝不清理数据',
      '设置 → 关于 → 初始化流程：可随时重新体验引导',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl56',
    title: 'GitHub 开源 + OTA 更新：自动检查 / 下载 / 哈希校验',
    details: <String>[
      '项目开源（MIT）：GitHub Actions 发布工作流——打 tag（cl*/v*）自动构建 APK + 生成 SHA-256 校验文件并发布 Release',
      '新增 OTA 更新服务：连接 GitHub Releases 自动检查新版本（比对构建号）',
      'hotfix 标记的版本直接下载；下载后校验 SHA-256 哈希，通过才提示安装',
      '设置 → 关于 → 版本更新 接入真实检查链路（确认 → 下载 → 校验 → 提醒）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl55',
    title: '关于页新增版本日志 + 版本更新入口',
    details: <String>[
      '设置 → 关于 → 版本日志：自动获取最新日志（changelog 倒序，最新在顶部），展示全部历史更新',
      '设置 → 关于 → 版本更新：检查更新入口（当前版本展示；G7 接入 GitHub / 官网 OTA 检查、下载、哈希校验与提醒）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl54',
    title: '视频画质档扩展 + 播放顺序修复 + 全局预设四档 + 存储统计',
    details: <String>[
      'B站背景视频画质默认 360p，可选 720 / 1080 / 大会员 1080 60fps（DASH 按清晰度 id 精确选档，未命中自动回退最接近高档）',
      '修复「播放顺序无法应用」：播放记录顺序首帧读取为 null 导致回退字母序，改为等待真实记录顺序',
      '全局画面预设重构为四档：省电（关动效/帧率 24fps/提醒省电）、流畅（无特效+低模糊）、标准（标准特效+毛玻璃）、高质（全特效+液态玻璃），切换时展示档位简介',
      '设置 → 关于 → 存储：查看软件占用空间（数据 / 日志 / 临时文件分类统计）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl53',
    title: '界面整理：四宫格去 3D + 全局个性归位 + 动效系统 + 视频跟随播放',
    details: <String>[
      '主页移除四宫格（3D 世界 + 配色面板）入口弹层；3D 世界从「世界」Tab 进入',
      '配色面板迁入「长按场景卡 → 编辑场景」页，可自定义主色/强调色/背景渐变',
      '游戏里误排的全局个性归位到「设置 → 个性 → 画面特效」：图形后端 / 噪点纹理 / 玻璃模糊 / 背景动画 / 液态玻璃 / 全局画面预设',
      '新增动效系统：全局页面过渡（淡入 + 轻微上滑），浅色/深色主题统一',
      '背景视频跟随音乐播放状态（暂停/播放同步）+ 四角圆角与玻璃表面一致',
      '「曲库中找不到该曲目」等报错通知统一走全局通知（多并行竖向排布）',
      '非主页内容区底部圆角，与音乐卡片衔接（与主页视频背景效果一致）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl52',
    title: '音乐卡片重构 + 界面统一：按钮重排 / 歌词内嵌 / 视频背景圆角',
    details: <String>[
      '音乐卡片按钮重排：歌词钮移到音量右边、上一首左边；收藏移到循环模式右边',
      '白噪音 + 视听 + 均衡器并入底部操作行（音质右边，均衡器为图标形式）；header 只保留放大 + 折叠',
      '歌词可点钮在卡片内展开（不再只存在于全屏 Overlay），全屏与紧凑卡片行为一致',
      '主页视频背景加顶部圆角（与其它页面玻璃表面一致）',
      '背景视频保持默认静音，不影响主音乐播放',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl51',
    title: '播放记录系统：直链缓存重播 + 失效自动重匹配 + 按记录切歌',
    details: <String>[
      '保存解析直链缓存：新增 resolved_links 表，记录每首曲最近成功解析的可播放链接与失效时间',
      '再次播放优先用缓存近似链接（未过期直接播，更快更省流量）；过期则按来源重新解析',
      '源解析失败自动按 近似名称+时长+歌手 聚合搜索（网易云/B站）并匹配最优曲目播放',
      '上下歌切换考虑播放记录：新增按最近播放推导的播放顺序，顺序/倒序模式下下一首按播放记录走',
      '开始播放优先取场景默认曲目，其次取最近播过的曲目（不再无脑字母序第一首）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl50',
    title: '场景卡片：背景透明度可调 + 歌词移入右半区',
    details: <String>[
      '场景卡片背景浓度可调：新增 sceneCardOpacityProvider（0.1~0.9，默认 0.25），设置「个性→场景→场景卡片透明度」滑块自调，越低越通透、露出视频背景',
      '歌词移入场景卡片右半区（占 1/2 宽），与左侧场景信息并列',
      '无歌词时右半区自动折叠，场景卡片恢复整卡居中布局',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl49',
    title: '游戏页竖屏布局修复：HUD 自适应 + 物品栏不溢出 + 2.5D 画布完整',
    details: <String>[
      'HUD 控件随屏幕自适应：新增 hudResponsiveScale（按视口短边缩放），摇杆/动作键/顶栏按钮在手机/平板、竖屏/横屏都合适大小',
      '所有可点控件加不透明命中区（HitTestBehavior.opaque），触摸目标更稳',
      '底部物品栏按可用宽度自适应槽位尺寸，9 格 + 2 切换键必在屏宽内排下，竖屏窄屏不再横向溢出',
      '2.5D 音效画布按约束反推瓦片尺寸，整张等距网格在竖屏/横屏都完整显示（不再左右裁切）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl48',
    title: '底部导航重做：主页/曲库/世界/探索/设置 + 场景并入主页',
    details: <String>[
      '底部 Dock 由 4 Tab 改为 5 Tab：主页 / 曲库 / 世界（星璃世界入口）/ 探索 / 设置',
      '主页合并原场景页内容（场景卡堆 + 操作条 + 音乐卡），去掉独立场景页路由',
      '世界 Tab 复用体素世界主菜单（世界存档 / 开放世界 / 游戏设置）',
      'ShellPage 索引重映射：home=0 / library=1 / world=2 / explore=3 / settings=4',
      '音乐卡独立化为 MusicCard 组件（内嵌歌词、跨页共享播放状态不重载），AppShell 与场景页统一复用',
      '视频作场景背景：当前 B站曲目静音视频画面作背景，默认关闭模糊，与音乐进度自动同步 + 变速适配开关（默认关）',
      '曲库重做：顶部聚合搜索（本地/网易云/B站三源合一）+ 第一页歌曲一览（卡片/列表切换 + 分类筛选）+ 第二页时光沉底（听歌情况 + 历史记录）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl47',
    title: '全局数据层 + 视听结合 + 游戏设置重组 + 渲染优化',
    details: <String>[
      '全局统计：听歌总时长 / 单曲播放次数，收录进每首歌卡片；播放自动记录（SQLite）',
      '全局收藏 + 全局歌单：自定义名称 / 相册背景图 / 排序方式；听歌历史自动收录（相似歌名/歌手询问归并，与歌单联动）',
      '自动播放（默认开）+ 自动过渡（曲末 5 秒淡出淡入）+ 后台播放',
      '场景中间卡片：默认 16:9、长按打开场景个性、去掉搜索/音质',
      '视听结合：当前歌曲自动搜 B站视频静音作背景画面，白噪音旁快捷开关',
      '设置重组：游戏画面/机制统统迁入「游戏」分类——画质（低中高卡片预览/分辨率/帧率 3~60+无限制/阴影）+ 机制（存档/世界/自定义世界偏移率）',
      '渲染优化：修复改分辨率只显示左上角（buildFrame/paint 同步）；可见集洪泛半径收敛（低视距不再每帧 17×17）；LOD 默认扩到 32 区块',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl45',
    title: '描边 5 格化 + 视距不硬剔 + 设置重组 + UI 编辑器大补 + EQ 修复',
    details: <String>[
      '描边：只描玩家 5 格内（实描边）+ 5~12 格极淡渐隐，设置可关',
      '渲染：视距不再硬剔除——相机 far/雾/加载推到 LOD 地平线，LOD 近 2 → 远 16（可 32）区块少面大体积替身，看得更远更流畅；可选边界雾（与 LOD 互斥）',
      '设置：画面分类改名「个性」；游戏高级画质并入个性；机制并入游戏分类',
      'UI 编辑器：撤销/重做、复制粘贴+多选、对齐/分布/网格吸附/方向键微调、层级树、预览动画、可点击反馈',
      '均衡器：应用失败自动关闭 + 补应用兜底，修复开启后无声/播放失败',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl44',
    title: '音源→后端路由落地 + 通知歌名即时更新',
    details: <String>[
      'AudioService 双后端并存（just_audio + media_kit），按曲源 requiresMediaKit 自动路由（#392/#393）',
      '网易云 / B站 流改走 media_kit（libmpv），修复 just_audio 无法解码致无声、进度条空转',
      '通知栏/锁屏歌名进入加载态即更新，不再滞后；加载失败回退上一首（#396）',
      '关于页更新日志现已展示（#①）',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl43',
    title: '描边视距修复 + 顶部播放器防重叠 + 音量链路校正',
    details: <String>[
      '② 方块描边「环绕自身立方圆」根因修复：原硬编码 15 格二值截断，改为随视距派生 + 末段淡出',
      '⑨ 游戏内顶部液态玻璃播放器改为顶栏子项，消除窄屏折行重叠',
      'media_kit 音量语义 0~1↔0~100 校正（修复「media_kit 无声」）',
      '网易云/解析类源自动路由到 media_kit 后端（just_audio 无法解码其 CDN 流）',
      '系统媒体控件歌名在加载即更新，不再滞后到加载完成',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl42',
    title: '体素渲染 / UX 大修（10 项反馈）',
    details: <String>[
      'LOD 默认开启 + 裙边裂口修复（远处方块减面生效）',
      '云视距 / 太阳无极过渡+泛光 / 向下平行面剔除复核',
      '背包物品改为居中 3×9 表格；退出按钮移到背包/合成左侧',
      '搜索 + 音质并入底部音乐卡片',
      '游戏 UI 顶部居中液态玻璃播放器；音源搜索改弹出式底部卡片',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl41',
    title: '修复「播 1 秒后静音、须拖主音量恢复」',
    details: <String>[
      '切歌时旧曲淡出在后台把新曲音量压成 0',
      '新增 _cancelFades() 在直接 setVolume 前作废在途淡出',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl40',
    title: '修复安卓「仍卡死」真凶',
    details: <String>[
      '全局播放/进世界 toast 的 Positioned/StackParentData 强转失败 → ANR',
      '通知栏小图标被资源压缩剥除 → 新增 keep.xml 保留',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl39',
    title: '安卓运行时 4 连崩修复',
    details: <String>[
      '占位符解析超时兜底、歌名/曲名真源对齐',
      '网易云源崩溃回落、进世界/进存档异步错误兜底',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.14',
    cl: 'cl38',
    title: '开放世界地基 P0+P1',
    details: <String>[
      '编辑层坐标改为 chunk 分桶（支持任意/负坐标、大范围）',
      '玩家生存状态抽离为 playerVitalsProvider 单例真相源',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.13',
    cl: 'cl37',
    title: '生存模式 bug 修复',
    details: <String>[
      '新建/读档强制生存、饥饿衰减提速',
      '新建存档作弊/浮空岛默认关',
    ],
  ),
  ChangelogEntry(
    version: '0.26.8.13',
    cl: 'cl36',
    title: '安卓切歌防闪退 + 通知系统重做',
    details: <String>[
      '占位符解析超时兜底避免无限加载',
      '通知 rootOverlay/多实例堆叠、水面默认关、返回键提醒',
      '崩溃界面兜底（ErrorWidget.builder → CrashScreen）',
    ],
  ),
];
