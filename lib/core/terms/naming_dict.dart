/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐空间 · 界面文案词典（v2 · 极光玻璃文案规范 · 细化版）
/// ════════════════════════════════════════════════════════════════════════
///
/// 调性：玻璃般的通透轻盈 + 星璃世界的梦幻感 + 现代简约的克制。
/// 不硬（不像技术文档）、不飘（不像看不懂的诗）。
///
/// ### 全局规则
/// - 人称统一「你」；断句以短句为主，按钮 ≤ 4 字
/// - 标题/按钮/标签不加句号；简短提示可加，尽量不用感叹号（除非紧急错误）
/// - 避免直译：不写「我的资料」写「个人中心」；不写「歌单详情」写「歌单内页」
///
/// ### 文案一致性检查表（开发对照）
/// - [ ] 按钮文字不超过 4 个字
/// - [ ] 播放相关统一「播放/暂停」，无「开始/停止」
/// - [ ] 「收藏」始终用该词，不混用「喜欢/红心」
/// - [ ] 「歌单」不加「我的」前缀
/// - [ ] 提示语结尾不加感叹号（严重错误除外）
/// - [ ] 时间格式统一 `分:秒`（如 `3:42`）
library;

/// 文案词典：核心实体 + Tab 命名 + 各模块文案 + 反馈提示 + 特殊玩法。
///
/// `abstract final class` 禁止实例化，全部 `static const` 编译期常量，
/// 零运行时开销。模板类短句以 `static` 方法提供。
/// 新增文案先补此处，UI 一律 `Terms.*` 引用。
abstract final class Terms {
  // ── 核心实体 ─────────────────────────────────────────────
  /// 场景（ScenePage / 场景编辑器 / 场景包）。
  static const String scene = '场景';

  /// 曲库（聚合全部已启用音源后的歌曲集合）。
  static const String library = '曲库';

  /// 歌曲（单曲）。
  static const String track = '歌曲';

  /// 专辑（按 `Track.album` 聚合）。
  static const String album = '专辑';

  /// 目录（本地文件夹层级，曲库「文件夹」视图）。
  static const String folder = '目录';

  /// 音源（本地目录 / 服务器 / 电台的上位概念）。
  static const String source = '音源';

  /// 服务器（自建 Subsonic 服务器）。
  static const String server = '服务器';

  /// 通知中心（三合一：运行状态 / 媒体控制 / 场景状态）。
  static const String notificationCenter = '通知中心';

  // ── 延伸命名空间（世界 / 画布 / 播放）────────────────────
  /// 星璃世界（星璃体素世界本体，区别于底部 Dock「世界」Tab 的短标签）。
  static const String world = '星璃世界';

  /// 体素世界（3D 开放世界）。
  static const String voxelWorld = '体素世界';

  /// 2.5D 音效画布（场景音效可视化编辑界面）。
  static const String canvas = '2.5D 音效画布';

  /// 正在播放（整页播放器标题 / 音乐卡状态前缀）。
  static const String playing = '正在播放';

  /// 存档（名词；区别于动词 [save]）。
  static const String manualSave = '存档';

  // ── 底部导航栏（Dock Tab 标签）───────────────────────────
  /// 主页 Tab
  static const String tabHome = '主页';

  /// 曲库 Tab
  static const String tabLibrary = '曲库';

  /// 世界 Tab（品牌小字见 [tabWorldBrand]）。
  static const String tabWorld = '世界';

  /// 世界 Tab 品牌小字：星璃
  static const String tabWorldBrand = '星璃';

  /// 探索 Tab
  static const String tabExplore = '探索';

  /// 设置 Tab
  static const String tabSettings = '设置';

  // ── 主页文案 ─────────────────────────────────────────────
  /// 问候语：早上好 / 下午好 / 晚上好
  static const String greetingMorning = '早上好';
  static const String greetingAfternoon = '下午好';
  static const String greetingEvening = '晚上好';

  /// 品牌标语（头像 / logo 旁）
  static const String brandTagline = '音乐是流动的极光';

  /// 场景大卡英文小标签（不翻译）
  static const String sceneLabel = 'SCENE';

  // ── 曲库模块文案 ─────────────────────────────────────────
  /// 搜索框占位符
  static const String librarySearchHint = '搜索歌曲、歌手或专辑…';

  /// 最近播放
  static const String recentlyPlayed = '最近在听';

  /// 听歌排行
  static const String topCharts = '你的排行';

  /// 听歌排行加载中
  static const String topChartsLoading = '你的排行加载中…';

  /// 听歌排行二级：周榜 / 月榜 / 总榜
  static const String chartWeekly = '周榜';
  static const String chartMonthly = '月榜';
  static const String chartAll = '总榜';

  /// 累计听歌时长（时光沉底横幅标题）
  static const String totalPlaytime = '累计听歌时长';

  /// 音乐时光机（按年份归档）
  static const String musicTimeMachine = '音乐时光机';

  /// 筛选标签：全部（歌曲 = 全部来源）
  static const String filterAll = '全部';

  /// 筛选标签：歌曲
  static const String filterTracks = '歌曲';

  /// 筛选标签：专辑
  static const String filterAlbums = '专辑';

  /// 筛选标签：歌单（cl15 曲库四栏）
  static const String filterPlaylists = '歌单';

  /// 筛选标签：歌手（cl15 曲库四栏）
  static const String filterSingers = '歌手';

  /// 筛选标签：在线
  static const String filterOnline = '在线';

  /// 筛选标签：音景（白噪音集合）
  static const String filterSoundscape = '音景';

  /// 视图切换：卡片模式
  static const String viewCard = '卡片';

  /// 视图切换：列表模式
  static const String viewList = '列表';

  /// 聚合搜索按钮
  static const String aggregateSearch = '聚合搜索';

  // ── 探索模块文案 ─────────────────────────────────────────
  /// 顶部搜索框占位符
  static const String exploreSearchHint = '搜索歌曲或场景…';

  /// 精选区大卡标题
  static const String featuredHero = '今日精选';

  /// 场景歌单区块标题
  static const String sceneMusic = '场景歌单';

  /// 推荐场景区块标题（同 [sceneMusic]，保留兼容）
  static const String recommendedScenes = '场景歌单';

  /// 区块标题
  static const String hotPlaylists = '热门推荐';

  /// 功能区区块标题
  static const String features = '功能';

  /// 实验室区块标题（原「实验」区）
  static const String lab = '实验室';

  /// 功能区入口：智能推荐
  static const String smartRecommend = '智能推荐';

  /// 功能区入口：AI 陪伴
  static const String aiCompanion = '小璃';

  /// 功能区入口：星璃世界
  static const String starliteWorld = '星璃世界';

  /// 功能区入口：声景工坊（2.5D 音效画布快捷入口）
  static const String soundscapeStudio = '声景工坊';

  /// 探索页顶部搜索 Tab 标签
  static const String exploreTabTracks = '歌曲';
  static const String exploreTabPlaylists = '歌单';
  static const String exploreTabUsers = '用户';

  // ── 播放控制文案 ─────────────────────────────────────────
  /// 播放
  static const String play = '播放';

  /// 暂停
  static const String pause = '暂停';

  /// 下一首
  static const String nextTrack = '下一首';

  /// 上一首
  static const String prevTrack = '上一首';

  /// 随机播放
  static const String shuffle = '随机';

  /// 列表循环
  static const String loopList = '列表循环';

  /// 单曲循环
  static const String loopSingle = '单曲循环';

  /// 收藏
  static const String favorite = '收藏';

  /// 已收藏
  static const String favorited = '已收藏';

  /// 添加到歌单
  static const String addToPlaylist = '添加到歌单';

  /// 下载
  static const String download = '下载';

  /// 分享
  static const String share = '分享';

  /// 歌词
  static const String lyrics = '歌词';

  /// 音效（原「均衡器」入口，内部预设见 [presetClear] 等）
  static const String equalizer = '音效';

  /// 音效预设：清澈 / 人声 / 重低音 / 古典 / 摇滚 / 自定义
  static const String presetClear = '清澈';
  static const String presetVocal = '人声';
  static const String presetBass = '重低音';
  static const String presetClassic = '古典';
  static const String presetRock = '摇滚';
  static const String presetCustom = '自定义';

  /// 安睡（睡眠定时入口）
  static const String sleepTimer = '安睡';

  /// 安睡选项：15 / 30 / 60 分钟 / 结束时停止
  static const String sleep15 = '15分钟';
  static const String sleep30 = '30分钟';
  static const String sleep60 = '60分钟';
  static const String sleepEnd = '结束时停止';

  /// 画面（B 站视频背景开关）
  static const String videoBg = '画面';

  /// 倍速标签前缀（后接 `1.0x` 等）
  static const String speed = '倍速';

  /// 无歌词时显示
  static const String noLyrics = '纯音乐 · 无声词';

  /// 音景内部自然音：雨声 / 海浪 / 篝火 / 森林 / 风
  static const String ambientRain = '雨声';
  static const String ambientWaves = '海浪';
  static const String ambientCampfire = '篝火';
  static const String ambientForest = '森林';
  static const String ambientWind = '风';

  // ── 音乐卡文案 ───────────────────────────────────────────
  /// 展开按钮
  static const String expand = '展开';

  /// 收起时状态：正在播放 · 曲名
  static String playingStatus(String name) => '正在播放 · $name';

  // ── 歌单模块文案 ─────────────────────────────────────────
  /// 新建歌单按钮
  static const String createPlaylist = '新建歌单';

  /// 歌单内页标题
  static const String playlistDetail = '歌单内页';

  /// 歌单空状态提示
  static const String playlistEmpty = '还没有歌单，去曲库收藏歌曲后会自动生成';

  /// 无歌单引导
  static const String noPlaylist = '创建你的第一个歌单';

  // ── 世界模块文案 ─────────────────────────────────────────
  /// 世界页标题（独立页，突出品牌）
  static const String worldTitle = '星璃';

  /// 世界入口卡片：荒野 / 雨林 / 雪原 / 极光
  static const String biomeWild = '荒野';
  static const String biomeRain = '雨林';
  static const String biomeSnow = '雪原';
  static const String biomeAurora = '极光';

  /// 自由探索（开放世界入口）
  static const String freeExplore = '自由探索';

  /// 世界规则（游戏设置入口）
  static const String worldRules = '世界规则';

  /// 一起听（联机 / 音乐社交）
  static const String listenTogether = '一起听';

  /// 电台房（由一起听统一演进而来，见 PRD_电台核心）——正式功能入口。
  static const String station = '电台';

  /// 读取（存档读取按钮）
  static const String loadGame = '读取';

  /// 进入世界
  static const String enterWorld = '进入世界';

  /// 创建新世界
  static const String createNewWorld = '创建世界';

  /// 世界设置
  static const String worldSettings = '世界设置';

  /// 多人联机
  static const String multiplayer = '多人联机';

  /// 邀请好友
  static const String inviteFriends = '邀请好友';

  /// 世界排行榜
  static const String worldLeaderboard = '世界排行榜';

  /// 世界无存档空状态
  static const String worldNoSave = '还没有存档，开始一场冒险吧';

  // ── 设置模块文案 ─────────────────────────────────────────
  /// 设置分组：音频 / 画面 / 通知 / 实验 / 关于
  static const String groupAudio = '音频';
  static const String groupVisual = '画面';
  static const String groupNotify = '通知';
  static const String groupLab = '实验';
  static const String groupAbout = '关于';

  /// 关于
  static const String about = '关于';

  /// 版本更新
  static const String versionUpdate = '版本更新';

  /// 主题模式
  static const String themeMode = '主题模式';

  /// 皮肤
  static const String skin = '皮肤';

  /// 界面密度
  static const String uiDensity = '界面密度';

  /// 存储管理
  static const String storageManagement = '存储管理';

  /// 日志上传
  static const String logUpload = '日志上传';

  /// 实验功能
  static const String experimentalFeatures = '实验功能';

  /// 退出登录
  static const String logout = '退出登录';

  /// 清除缓存
  static const String clearCache = '清除缓存';

  /// 检查更新
  static const String checkForUpdates = '检查更新';

  // ── 常用动词 / 操作文案 ─────────────────────────────────
  /// 添加（音源 / 场景等）。
  static const String add = '添加';

  /// 编辑。
  static const String edit = '编辑';

  /// 删除。
  static const String delete = '删除';

  /// 保存。
  static const String save = '保存';

  /// 取消。
  static const String cancel = '取消';

  /// 确定。
  static const String confirm = '确定';

  /// 搜索。
  static const String search = '搜索';

  /// 个人中心（不用「我的」）。
  static const String profile = '个人中心';

  /// 测试连接。
  static const String testConnection = '测试连接';

  /// 启用 / 停用（开关动词）。
  static const String enable = '启用';
  static const String disable = '停用';

  /// 关闭。
  static const String close = '关闭';

  /// 重试。
  static const String retry = '重试';

  /// 安装。
  static const String install = '安装';

  /// 跳过。
  static const String skip = '跳过';

  /// 重新初始化（OOBE 重走流程按钮）。
  static const String reinitialize = '重新初始化';

  /// 知道了（提示确认按钮）。
  static const String gotIt = '知道了';

  /// 场景切换通知标签。
  static const String sceneSwitch = '场景';

  /// 下一步。
  static const String next = '下一步';

  /// 返回。
  static const String back = '返回';

  /// 更多。
  static const String more = '更多';

  /// 当前播放。
  static const String nowPlaying = '当前播放';

  /// 实验（探索实验室）。
  static const String experiment = '实验';

  // ── 反馈与提示文案 ───────────────────────────────────────
  /// 加载中…
  static const String loading = '加载中…';

  /// 加载超时（可点击重试）
  static const String loadTimeout = '加载超时，点击重试';

  /// 加载成功提示
  static const String loadSuccess = '加载成功';

  /// 操作成功提示
  static const String actionSuccess = '操作成功';

  /// 收藏成功提示
  static const String favoriteSuccess = '已收藏';

  /// 取消收藏提示
  static const String unfavoriteSuccess = '已移除';

  /// 添加歌单成功提示
  static const String addToPlaylistSuccess = '已添加到歌单';

  /// 歌单已保存
  static const String playlistSaved = '歌单已保存';

  /// 睡眠定时已设置：将在 {minutes} 分钟后停止
  static String sleepTimerSet(int minutes) => '将在 $minutes 分钟后停止';

  /// 错误提示通用文案
  static const String errorGeneral = '出错了，请稍后重试';

  /// 网络错误提示
  static const String errorNetwork = '网络未连接，请检查后重试';

  /// 歌曲无法播放
  static const String songUnplayable = '此歌曲无法播放';

  /// 加载失败提示
  static const String loadFailed = '加载失败，请稍后重试';

  /// 空状态通用标题
  static const String emptyTitle = '这里空空如也';

  /// 空状态通用描述
  static const String emptyMessage = '这里还没有歌曲，去添加一些吧';

  /// 无播放记录空状态
  static const String noPlayHistory = '还没有播放记录';
  static const String noPlayHistoryMsg = '播放几首歌后，这里会按播放次数排行';

  /// 曲库为空提示
  static const String libraryEmpty = '这里还没有歌曲，去添加一些吧';
  static const String libraryEmptyMsg = '添加本地音乐或连接音源后，这里会出现你的歌曲';

  /// 搜索无结果
  static const String searchNoResult = '未找到相关内容，换个关键词试试';

  /// 找不到曲目提示
  static const String trackNotFound = '曲库中找不到该曲目';

  /// 下载中提示
  static const String downloading = '下载中…';

  /// 下载完成提示
  static const String downloadComplete = '下载完成';

  /// 分享成功提示
  static const String shareSuccess = '分享成功';

  /// 复制成功提示
  static const String copySuccess = '已复制到剪贴板';

  /// 权限请求提示
  static const String permissionRequest = '请授权存储访问';

  /// 确认对话框标题
  static const String confirmTitle = '确认';

  /// 警告对话框标题
  static const String warningTitle = '提醒';

  /// 新版本可用提示
  static const String updateAvailable = '发现新版本';

  /// 版本已更新提示
  static const String updated = '版本已更新';

  /// 更新渠道已切换提示
  static const String channelSwitched = '更新渠道已切换';

  /// 安装失败提示
  static const String installFailed = '安装失败，请稍后重试';

  /// 下载失败提示
  static const String downloadFailed = '更新下载失败';

  /// 校验成功提示
  static const String verifySuccess = '已通过 SHA-256 校验';

  // ── 特殊玩法文案 ─────────────────────────────────────────
  /// 声景工坊：添加方块提示
  static const String dragToCanvas = '拖拽方块到画布';

  /// 声景工坊：播放音景按钮（不叫「播放场景」）
  static const String playSoundscape = '奏响';

  /// 声景工坊：导出分享弹窗标题
  static const String shareSoundscapeTitle = '分享你的音景';

  /// 小璃：聊天输入框占位符
  static const String aiInputPlaceholder = '跟小璃说点什么…';

  /// 小璃：代操作时反馈
  static const String aiDidAdjust = '小璃已帮你调整音量';
}
