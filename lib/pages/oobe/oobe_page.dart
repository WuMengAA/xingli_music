/// ════════════════════════════════════════════════════════════════════════
/// OOBE · 6 页极简引导（cl05 · Win11 OOBE 分步聚焦；cl07 视觉语言统一
/// Material，移除界面风格页）
/// ════════════════════════════════════════════════════════════════════════
///
/// 一页只做一件事，顶部进度点、底部固定操作栏：
///   0. 品牌   —— 情感开场（不索要权限，无「跳过」）
///   1. 权限   —— 存储访问（好处前置 + 「授权并导入」/「仅在线使用」）
///               底部并入合同勾选（服务条款 / 隐私政策，合规保留）
///   2. 流派   —— 选音乐流派（≤3，防选择瘫痪）
///   3. 世界   —— 星璃功能亮点（场景化 / 3D 世界 / 一起听 / 开放音源）
///   4. 体验   —— 无损音质 / 后台播放 / 白噪音 开关
///   5. 加载   —— 沉浸式扫描（旋转唱片 + 动态文案 + 进度条），完成自动进入
///
/// 文案随机：每页标题 / 描述均有多款变体，启动时随机抽一套
/// （「有秩序的随机感」——每次打开 OOBE 不重样）。
///
/// 触发：首次启动覆盖全屏 / 设置-关于-初始化流程 / 版本升级后弹询问。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/audio/audio_providers.dart';
import '../../widgets/common/aurora_background.dart';
import '../../providers/settings/notification_providers.dart';
import '../../providers/settings/oobe_choice_providers.dart';
import '../../providers/settings/performance_providers.dart';
import '../../services/open_url.dart';
import '../../services/permission_service.dart';

/// ═══════════ cl05 文案池（每页多款，随机出现）═══════════

const List<String> _kPermTitles = <String>[
  '让好音乐随时待命。',
  '把喜欢的歌，都收进你的口袋。',
  '本地音乐，离线也能听。',
];

const List<String> _kPermDescs = <String>[
  '访问本地音乐文件，以便离线播放和建立专属歌单。',
  '读取设备里的音乐，让你随时离线享受，不依赖网络。',
  '授权后即可扫描本地曲库，快速建立你的音乐地图。',
];

const List<String> _kPrefTitles = <String>[
  '选几个你爱的风格。',
  '告诉我，你耳朵的偏好。',
  '你的音乐口味，是哪种颜色？',
];

const List<String> _kPrefDescs = <String>[
  '帮你过滤同频好歌，也可以稍后更改。',
  '最多选 3 个，之后随时在设置里调整。',
  '让推荐更懂你，选完还能改。',
];

const List<String> _kWorldTitles = <String>[
  '星璃的世界，不止音乐。',
  '音乐之外，还有一片世界。',
  '看看星璃还能陪你做什么。',
];

const List<String> _kWorldSubs = <String>[
  '音乐、画面与世界，连在一起。',
  '从一首歌出发，走进一个空间。',
  '每个场景，都是一次漫游。',
];

const List<String> _kExpTitles = <String>[
  '让体验更合你心意。',
  '几个开关，调出你的听感。',
  '体验细节，随你掌控。',
];

const List<String> _kExpSubs = <String>[
  '都可以在设置里改回来。',
  '按你的习惯来，不必勉强。',
  '省电还是享受，你选。',
];

const List<String> _kLoadTitles = <String>[
  '正在整理你的音乐版图...',
  '正在为你的音乐建一座小屋...',
  '正在星璃世界里为你点亮星星...',
  '正在把每首歌安放进它的角落...',
];

/// 加载过程中按进度循环切换的动态文案（加载页副标题）。
const List<String> _kLoadMessages = <String>[
  '扫描本地曲库',
  '整理专辑封面',
  '建立听歌偏好',
  '点亮你的音乐版图',
  '为你准备第一个场景',
];

/// OOBE 全屏引导页。
class OobePage extends ConsumerStatefulWidget {
  const OobePage({super.key});

  @override
  ConsumerState<OobePage> createState() => _OobePageState();
}

class _OobePageState extends ConsumerState<OobePage> {
  static const int _pageCount = 6;

  final PageController _ctrl = PageController();
  final math.Random _rng = math.Random();
  int _page = 0;
  bool _agreed = false;

  /// cl05：启动时随机抽一套文案（每页标题/描述各一款）。
  /// cl07：品牌页标题/副标题改为 l10n 随机池（跟随语言），首次 build 抽一次。
  String? _welcomeTitle;
  String? _welcomeSub;
  late final String _permTitle = _pick(_kPermTitles);
  late final String _permDesc = _pick(_kPermDescs);
  late final String _prefTitle = _pick(_kPrefTitles);
  late final String _prefDesc = _pick(_kPrefDescs);
  late final String _worldTitle = _pick(_kWorldTitles);
  late final String _worldSub = _pick(_kWorldSubs);
  late final String _expTitle = _pick(_kExpTitles);
  late final String _expSub = _pick(_kExpSubs);
  late final String _loadTitle = _pick(_kLoadTitles);
  late final List<String> _loadMsgs = List<String>.of(_kLoadMessages)
    ..shuffle(_rng);

  String _pick(List<String> pool) => pool[_rng.nextInt(pool.length)];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(oobeDoneProvider.notifier).state = true;
    // 兜底：若用户「仅在线使用」跳过授权，进入后仍静默申请（不阻塞）。
    unawaited(PermissionService.requestEssentialOnStartup());
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _next() {
    if (_page == 1 && !_agreed) return; // 权限页合同未勾不可前进
    _ctrl.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _grantAndNext() {
    // 「授权并导入」：主动申请通知 + 存储，失败不阻塞流程。
    unawaited(PermissionService.requestEssentialOnStartup());
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color accent = context.appColors.accent;
    final Set<String> genres = ref.watch(genrePrefsProvider);
    final int page = _page;
    final bool isLoading = page == _pageCount - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: Stack(
        children: <Widget>[
          // cl05：光效 + 图形动态背景（所有页共用）。
          Positioned.fill(child: AuroraBackground(accent: accent)),
          SafeArea(
            child: Column(
              children: <Widget>[
                // 顶部进度点。
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(_pageCount, (int i) {
                      final bool active = i == page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: active ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? accent
                              : (i < page
                                    ? accent.withValues(alpha: 0.5)
                                    : const Color(0x44FFFFFF)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
                // 页面主体（PageView 滑动）。
                Expanded(
                  child: PageView.builder(
                    controller: _ctrl,
                    itemCount: _pageCount,
                    onPageChanged: (int i) => setState(() => _page = i),
                    itemBuilder: (BuildContext c, int i) {
                      if (i == 0) return _welcomePage(c, accent);
                      if (i == 1) return _permPage(c, accent);
                      if (i == 2) return _prefPage(c, accent);
                      if (i == 3) return _worldPage(c, accent);
                      if (i == 4) return _expPage(c, accent);
                      return _loadingPage(c, accent); // i == 5
                    },
                  ),
                ),
                // 底部操作栏（加载页无按钮，自动跳转）。
                if (!isLoading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Row(
                      children: <Widget>[
                        if (page > 0)
                          TextButton(
                            onPressed: () => _ctrl.previousPage(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                            ),
                            child: const Text(
                              '上一步',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        else
                          const Spacer(),
                        const Spacer(),
                        if (page == 1)
                          TextButton(
                            onPressed: _agreed ? _next : null,
                            child: const Text(
                              '仅在线使用',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 14,
                            ),
                          ),
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                          label: Text(
                            page == 0
                                ? l10n.startExplore
                                : (page == 1 ? '授权并导入' : '下一步'),
                          ),
                          onPressed: switch (page) {
                            0 => _next,
                            1 => _agreed ? _grantAndNext : null,
                            2 => genres.isEmpty ? null : _next,
                            _ => _next,
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 通用构件 ─────────────────────────────────────

  Widget _scroll(Widget child) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
    child: child,
  );

  Widget _title(Color accent, String t) => Text(
    t,
    style: AppTextStyles.title.copyWith(color: Colors.white, fontSize: 22),
    textAlign: TextAlign.center,
  );

  Widget _sub(String t) => Text(
    t,
    textAlign: TextAlign.center,
    style: AppTextStyles.body.copyWith(color: const Color(0xFFB8C4D8)),
  );

  Widget _chip(Color accent, String label, bool selected, VoidCallback onTap) =>
      ChoiceChip(
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.white),
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: const Color(0x1AFFFFFF),
        selectedColor: accent,
        side: const BorderSide(color: Color(0x33FFFFFF)),
      );

  Widget _switchRow(
    Color accent,
    bool value,
    ValueChanged<bool> onChanged,
    String title,
    String subtitle,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: const Color(0x22FFFFFF)),
    ),
    child: SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: accent,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, color: Colors.white),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: Colors.white70),
      ),
    ),
  );

  // ── 第 0 页：品牌（情感开场） ──────────────────────

  Widget _welcomePage(BuildContext context, Color accent) {
    // cl07：品牌页标题/副标题随机池改为 l10n 提供（跟随语言）。
    final AppLocalizations l10n = AppLocalizations.of(context);
    _welcomeTitle ??= _pick(<String>[
      l10n.welcomeTitle0,
      l10n.welcomeTitle1,
      l10n.welcomeTitle2,
      l10n.welcomeTitle3,
    ]);
    _welcomeSub ??= _pick(<String>[
      l10n.welcomeSub0,
      l10n.welcomeSub1,
      l10n.welcomeSub2,
      l10n.welcomeSub3,
    ]);
    return _scroll(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _BrandGlyph(accent: accent),
          const SizedBox(height: 28),
          _title(accent, _welcomeTitle!),
          const SizedBox(height: 10),
          _sub(_welcomeSub!),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  // ── 第 1 页：权限 + 合同 ──────────────────────────

  Widget _permPage(BuildContext context, Color accent) => _scroll(
    Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: <Color>[
                accent.withValues(alpha: 0.9),
                accent.withValues(alpha: 0.2),
              ],
            ),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.folder_copy_rounded,
            size: 40,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        _title(accent, _permTitle),
        const SizedBox(height: 8),
        _sub(_permDesc),
        const SizedBox(height: 20),
        _contractTile(
          accent,
          '服务条款',
          '星璃音乐为开源（MIT）项目，供个人学习与研究使用。第三方音源（网易云、B站等）的版权归原平台所有，仅限个人学习，请勿用于商业或二次分发。',
        ),
        const SizedBox(height: 8),
        _contractTile(
          accent,
          '隐私政策',
          '你的数据仅保存在本机。日志默认脱敏，不收集账号密码与具体曲目标题。我们不会向第三方出售你的数据。',
        ),
        const SizedBox(height: 10),
        _linkRow(
          context,
          '查看开源仓库与完整协议',
          'https://github.com/WuMengAA/xingli_music',
        ),
        const SizedBox(height: 14),
        CheckboxListTile(
          value: _agreed,
          onChanged: (bool? v) => setState(() => _agreed = v ?? false),
          activeColor: accent,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '我已阅读并同意《服务条款》与《隐私政策》',
            style: TextStyle(fontSize: 13, color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );

  // ── 第 2 页：流派（≤3） ───────────────────────────

  Widget _prefPage(BuildContext context, Color accent) {
    final Set<String> genres = ref.watch(genrePrefsProvider);
    return _scroll(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _title(accent, _prefTitle),
          const SizedBox(height: 8),
          _sub(_prefDesc),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final String g in kGenreOptions)
                _chip(accent, g, genres.contains(g), () {
                  final bool ok = ref
                      .read(genrePrefsProvider.notifier)
                      .toggle(g);
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('最多选 3 个就够了'),
                        duration: Duration(milliseconds: 1200),
                      ),
                    );
                  }
                }),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── 第 3 页：星璃世界（功能亮点四宫格） ────────────

  Widget _worldPage(BuildContext context, Color accent) => _scroll(
    Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _title(accent, _worldTitle),
        const SizedBox(height: 8),
        _sub(_worldSub),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _capCard(accent, Icons.blur_on_rounded, '场景化聆听', '每首歌都有它的画面与光'),
            _capCard(accent, Icons.view_in_ar_rounded, '3D 体素世界', '边听边逛，空间里漫游'),
            _capCard(accent, Icons.group_rounded, '一起听', '和 TA 同步听同一首歌'),
            _capCard(accent, Icons.cloud_outlined, '开放音源', '网易云、B站… 一处聚合'),
          ],
        ),
        const SizedBox(height: 16),
      ],
    ),
  );

  Widget _capCard(
    Color accent,
    IconData icon,
    String title,
    String desc,
  ) => Container(
    width: (MediaQuery.of(context).size.width - 28 * 2 - 12) / 2,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: const Color(0x22FFFFFF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 24, color: accent),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontSize: 14, color: Colors.white)),
        const SizedBox(height: 4),
        Text(desc, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    ),
  );

  // ── 第 4 页：体验开关 ─────────────────────────────

  Widget _expPage(BuildContext context, Color accent) {
    final int aq = ref.watch(audioQualityProvider);
    final bool bg = ref.watch(backgroundPlayProvider);
    final bool wn = ref.watch(whiteNoiseEnabledProvider);
    return _scroll(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _title(accent, _expTitle),
          const SizedBox(height: 8),
          _sub(_expSub),
          const SizedBox(height: 20),
          _switchRow(
            accent,
            aq == 0,
            (bool v) =>
                ref.read(audioQualityProvider.notifier).state = v ? 0 : 1,
            '无损音质',
            '优先使用高品 / 无损档位播放',
          ),
          const SizedBox(height: 10),
          _switchRow(
            accent,
            bg,
            (bool v) => ref.read(backgroundPlayProvider.notifier).state = v,
            '允许后台播放',
            '退出应用后继续播放音乐',
          ),
          const SizedBox(height: 10),
          _switchRow(
            accent,
            wn,
            (bool v) => ref.read(whiteNoiseEnabledProvider.notifier).state = v,
            '白噪音',
            '无人声时播放环境音，助眠专注',
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── 第 5 页：沉浸式加载（扫描本地） ────────────────

  Widget _loadingPage(BuildContext context, Color accent) => _LoadingProgress(
    accent: accent,
    title: _loadTitle,
    messages: _loadMsgs,
    onDone: _finish,
  );

  // ── 合同辅助 ─────────────────────────────────────

  Widget _contractTile(Color accent, String title, String body) => Container(
    decoration: BoxDecoration(
      color: const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: const Color(0x22FFFFFF)),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, color: Colors.white),
        ),
        iconColor: accent,
        collapsedIconColor: Colors.white70,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              body,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _linkRow(BuildContext context, String label, String url) => InkWell(
    onTap: () async {
      await OpenUrl.launch(context, url);
    },
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.open_in_new_rounded,
            size: 14,
            color: Colors.white70,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  url,
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 品牌图标 + 呼吸动画（cl05：慢速缩放 + 外圈光晕脉冲）。
class _BrandGlyph extends StatefulWidget {
  const _BrandGlyph({required this.accent});

  final Color accent;

  @override
  State<_BrandGlyph> createState() => _BrandGlyphState();
}

class _BrandGlyphState extends State<_BrandGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? _) {
        // 正弦呼吸：图标 1.0↔1.06，外圈光晕 0.12↔0.3。
        final double t = _ctrl.value;
        final double s = 1 + 0.06 * math.sin(t * math.pi * 2);
        final double halo =
            0.12 + 0.18 * (0.5 + 0.5 * math.sin(t * math.pi * 2));
        return Transform.scale(
          scale: s,
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: widget.accent.withValues(alpha: halo),
                  blurRadius: 36,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: <Color>[
                    widget.accent.withValues(alpha: 0.9),
                    widget.accent.withValues(alpha: 0.2),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.music_note_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 沉浸式加载进度（cl05：旋转唱片 + 动态文案 + 进度条，完成后回调）。
class _LoadingProgress extends StatefulWidget {
  const _LoadingProgress({
    required this.accent,
    required this.title,
    required this.messages,
    required this.onDone,
  });

  final Color accent;
  final String title;
  final List<String> messages;
  final VoidCallback onDone;

  @override
  State<_LoadingProgress> createState() => _LoadingProgressState();
}

class _LoadingProgressState extends State<_LoadingProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2000),
        )
        ..addStatusListener((AnimationStatus s) {
          if (s == AnimationStatus.completed) widget.onDone();
        })
        ..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? _) {
        final double v = _ctrl.value;
        final int msgIdx = (v * widget.messages.length).floor().clamp(
          0,
          widget.messages.length - 1,
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // 旋转唱片（2 圈）。
              Transform.rotate(
                angle: v * math.pi * 4,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: <Color>[
                        widget.accent.withValues(alpha: 0.9),
                        widget.accent.withValues(alpha: 0.2),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x33FFFFFF)),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: AppTextStyles.title.copyWith(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.messages[msgIdx],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB8C4D8)),
              ),
              const SizedBox(height: 22),
              // 百分比 + 细进度条。
              Text(
                '${(v * 100).round()}%',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 4,
                  color: widget.accent,
                  backgroundColor: const Color(0x22FFFFFF),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
