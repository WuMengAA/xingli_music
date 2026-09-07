/// ════════════════════════════════════════════════════════════════════════
/// OOBE · 极简首启引导（重写 cl_R34 · 去掉空壳与 filler）
/// ════════════════════════════════════════════════════════════════════════
///
/// 设计目标：首启应当**一眼看出这是什么、能做什么、要不要授权**，然后尽快进应用。
/// 两步即可完成，不做任何"初始化无用东西"的步骤。
///
///   0. 欢迎 —— 直接呈现设计语言（AnimatedBackground + 玻璃卡），
///              一句话定位 + 3 条具体能力（本地优先 / 智能策展 / 场景化沉浸）。
///   1. 权限 —— 用大白话解释"为什么要存储/通知权限"，可跳过、不阻塞；
///              主操作「进入星璃」直接完成首启，副操作「授权并导入」先要权再进。
///
/// 合规：服务条款 / 隐私政策仍可展开查看，但**不再阻塞**前进（用户反感被墙）。
///
/// 触发：首次启动覆盖全屏 / 设置-关于-初始化流程 / 版本升级后弹询问。
library;

import 'dart:async';
import 'dart:math' show pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/performance_providers.dart';
import '../../services/content/terms_service.dart';
import '../../services/ota_service.dart';
import '../../services/open_url.dart';
import '../../services/permission_service.dart';
import '../../widgets/design/animated_background.dart';
import '../../widgets/design/glass_controls.dart';
import '../../widgets/liquid_glass.dart';

/// 产品定位（一句话，用户可一眼读懂这是什么）。
const String _kPositioning = '会思考的本地音乐播放器 · 一个可以停留的空间';

/// 三条具体能力（避免营销空话，每条都是真能做的事）。
const List<(IconData, String, String)> _kPillars = <(IconData, String, String)>[
  (
    Icons.library_music_outlined,
    '本地优先',
    '扫描本地曲库，离线也能听，自动补全封面 / 歌词 / CUE 分轨',
  ),
  (
    Icons.auto_awesome_outlined,
    '智能策展',
    '按你的口味整理歌单与每日推荐，越听越懂你',
  ),
  (
    Icons.blur_on_rounded,
    '场景化沉浸',
    '体素世界与白噪音，边听边逛，把听歌变成停留',
  ),
];

/// 权限用途说明（大白话，解释"为什么要"）。
const List<(IconData, String, String)> _kPerms = <(IconData, String, String)>[
  (
    Icons.folder_copy_rounded,
    '存储权限',
    '读取设备里的音乐文件：离线播放，并自动补全封面与歌词',
  ),
  (
    Icons.notifications_active_rounded,
    '通知 / 后台',
    '锁屏与控制中心显示播放控制，退出应用后仍继续放歌',
  ),
];

/// OOBE 全屏引导页。
class OobePage extends ConsumerStatefulWidget {
  const OobePage({super.key});

  @override
  ConsumerState<OobePage> createState() => _OobePageState();
}

class _OobePageState extends ConsumerState<OobePage> {
  static const int _pageCount = 2;

  final PageController _ctrl = PageController();
  int _page = 0;

  // ═══ 条款（远端拉取，本地兜底，仅作查看，不阻塞）═══
  TermsDoc? _termsDoc;
  TermsDoc? _privacyDoc;

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  /// 条款文本从 GitHub 拉取，失败自动回退本地内置（见 [fetchTermsDoc]）。
  Future<void> _loadTerms() async {
    final TermsDoc terms = await fetchTermsDoc(TermsKind.terms);
    final TermsDoc privacy = await fetchTermsDoc(TermsKind.privacy);
    if (!mounted) return;
    setState(() {
      _termsDoc = terms;
      _privacyDoc = privacy;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// cl05 契约：完成首启。
  ///   1) 标记 oobeDone，AppShell 据此进入主界面；
  ///   2) 兜底静默申请必要权限（不阻塞）；
  ///   3) 回到首个路由（AppShell 已就绪）。
  void _finish() {
    ref.read(oobeDoneProvider.notifier).state = true;
    // 兜底：若用户「仅在线使用」跳过授权，进入后仍静默申请（不阻塞）。
    unawaited(PermissionService.requestEssentialOnStartup());
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _next() {
    _ctrl.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// 「授权并导入」：先主动申请权限，再完成首启。
  void _grantAndNext() {
    unawaited(PermissionService.requestEssentialOnStartup());
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = context.appColors.accent;
    final int page = _page;
    final bool isLast = page == _pageCount - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: Stack(
        children: <Widget>[
          // 设计语言背景（极淡渐变 + 抽象色块，随页面位移）。
          Positioned.fill(child: AnimatedBackground()),
          SafeArea(
            child: Column(
              children: <Widget>[
                // 顶部：进度点 + 右上角「跳过」。
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 16),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List<Widget>.generate(_pageCount, (int i) {
                            final bool active = i == page;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              width: active ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: active
                                    ? accent
                                    : (i < page
                                          ? accent.withValues(alpha: 0.5)
                                          : const Color(0x44FFFFFF)),
                                borderRadius: BorderRadius.circular(3),
                                boxShadow: active
                                    ? <BoxShadow>[
                                        BoxShadow(
                                          color: accent.withValues(alpha: 0.55),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                            );
                          }),
                        ),
                      ),
                      _SkipButton(onTap: _finish),
                    ],
                  ),
                ),
                // 页面主体。
                Expanded(
                  child: PageView.builder(
                    controller: _ctrl,
                    itemCount: _pageCount,
                    onPageChanged: (int i) => setState(() => _page = i),
                    itemBuilder: (BuildContext c, int i) {
                      if (i == 0) return _welcomePage(c, accent);
                      return _permPage(c, accent); // i == 1
                    },
                  ),
                ),
                // 底部操作栏。
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Row(
                    children: <Widget>[
                      if (page > 0)
                        XGlassButton(
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
                      if (isLast) ...<Widget>[
                        XGlassButton(
                          onPressed: _grantAndNext,
                          child: const Text(
                            '授权并导入',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      XGlassButton(
                        onPressed: isLast ? _finish : _next,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(isLast ? '进入星璃' : '开始体验'),
                          ],
                        ),
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

  /// 内容窄栏聚焦（≤440dp，一页只讲一件事）。
  Widget _scroll(Widget child) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: child,
      ),
    ),
  );

  Widget _title(Color accent, String t) => Text(
    t,
    style: AppTextStyles.title.copyWith(
      color: Colors.white,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    textAlign: TextAlign.center,
  );

  Widget _sub(String t) => Text(
    t,
    textAlign: TextAlign.center,
    style: AppTextStyles.body.copyWith(
      color: const Color(0xFFC3CFE3),
      fontSize: 14,
      height: 1.5,
    ),
  );

  // ── 第 0 页：欢迎（看见设计语言 + 这是什么） ──────────

  Widget _welcomePage(BuildContext context, Color accent) {
    return _scroll(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          LiquidGlass(
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: Column(
              children: <Widget>[
                _BrandGlyph(accent: accent),
                const SizedBox(height: 22),
                Text(
                  '星璃·无限音乐画布',
                  style: AppTextStyles.title.copyWith(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _kPositioning,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: accent.withValues(alpha: 0.95),
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),
                ..._kPillars.map(
                  (p) => _pillarRow(accent, p.$1, p.$2, p.$3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppVersion.displayShort,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white38,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  /// 一条能力说明：图标 + 标题 + 一句具体描述。
  Widget _pillarRow(Color accent, IconData icon, String title, String desc) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFC3CFE3),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── 第 1 页：权限（为什么 + 可跳过） ────────────────

  Widget _permPage(BuildContext context, Color accent) {
    return _scroll(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _title(accent, '先帮你准备好'),
          const SizedBox(height: 8),
          _sub('下面两项权限让本地音乐更好用；不给也能进，随时在设置里补。'),
          const SizedBox(height: 20),
          ..._kPerms.map((p) => _permRow(accent, p.$1, p.$2, p.$3)),
          const SizedBox(height: 18),
          _contractTile(
            accent,
            _termsDoc?.title ?? '服务条款',
            _termsDoc?.body ?? kLocalTermsBody,
            _termsDoc == null
                ? null
                : '${_termsDoc!.source} · 更新于 ${_termsDoc!.updatedAt}',
          ),
          const SizedBox(height: 8),
          _contractTile(
            accent,
            _privacyDoc?.title ?? '隐私政策',
            _privacyDoc?.body ?? kLocalPrivacyBody,
            _privacyDoc == null
                ? null
                : '${_privacyDoc!.source} · 更新于 ${_privacyDoc!.updatedAt}',
          ),
          const SizedBox(height: 10),
          _linkRow(context, '查看开源仓库与完整协议', kRepoUrl),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  /// 一条权限说明：图标 + 标题 + 为什么。
  Widget _permRow(Color accent, IconData icon, String title, String desc) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: const Color(0x22FFFFFF)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 22, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFC3CFE3),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  // ── 合同辅助（查看用，不阻塞） ──────────────────────

  Widget _contractTile(Color accent, String title, String body,
      [String? sourceNote]) =>
      // Material（而非 DecoratedBox）：ExpansionTile 内部是 ListTile，
      // 需在 Material 上绘制背景 / 水墨波纹，否则会触发断言。
      Material(
        color: const Color(0x14FFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: const BorderSide(color: Color(0x22FFFFFF)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
            subtitle: sourceNote == null
                ? null
                : Text(
                    sourceNote,
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
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

/// 右上角「跳过」文字按钮（尊重"尽快进应用"）。
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        '跳过',
        style: TextStyle(fontSize: 13, color: Colors.white54),
      ),
    ),
  );
}

/// 品牌图标 + 呼吸动画（慢速缩放 + 外圈光晕脉冲）。
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
        final double s = 1 + 0.06 * sin(t * pi * 2);
        final double halo = 0.12 + 0.18 * (0.5 + 0.5 * sin(t * pi * 2));
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
