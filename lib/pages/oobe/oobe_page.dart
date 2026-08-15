/// ════════════════════════════════════════════════════════════════════════
/// OOBE · 初始化流程（Out Of Box Experience，F4 重做）
/// ════════════════════════════════════════════════════════════════════════
///
/// 带用户过一遍完整的初始化流程（PageView 滑动 / 按钮推进）：
///   0. 欢迎        —— 品牌 + 一句话
///   1. 界面介绍    —— 底部导航 5 Tab / 手势 / 全局主题
///   2. 个性化      —— 全局画面预设四档（省电/流畅/标准/高质）+ 主题模式
///   3. 游戏画质    —— 体素世界画质 / 视距 / 帧率入口
///   4. 隐私与安全  —— 权限总览 + 数据脱敏说明
///   5. 通知权限    —— 授权通知 / 媒体 / 存储（复用 PermissionService.requestAll）
///   6. 实验性功能  —— 实验开关入口 + 风险提示
///   7. 版本日志    —— 自动获取最新版本日志（changelog 首条）
///   8. 更新检查    —— 说明 OTA 更新（GitHub Releases / 哈希校验）
///   9. 用户协议    —— 签署用户协议（同意后进入）
///  10. 完成        —— 丝滑过渡到主页（置 oobeDone=true）
///
/// 触发：
/// - 首次启动（`!oobeDoneProvider`）→ AppShell 覆盖全屏显示；
/// - 设置 → 关于 → 初始化流程 → 以普通路由重新打开；
/// - 版本升级后（`oobeLastBuild < buildCount`）→ 启动弹窗询问是否重走。
///
/// 数据保护：若检测到已有播放/收藏等数据，完成页醒目提示
/// 「合并且不清除数据」，明确重走流程不会清理任何数据。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/performance_providers.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../services/permission_service.dart';

/// OOBE 全屏引导页。
class OobePage extends ConsumerStatefulWidget {
  const OobePage({super.key});

  @override
  ConsumerState<OobePage> createState() => _OobePageState();
}

/// 单个引导步骤。
class _Step {
  const _Step(this.icon, this.title, this.sub, this.desc);

  final IconData icon;
  final String title;
  final String sub;
  final String desc;
}

class _OobePageState extends ConsumerState<OobePage> {
  final PageController _ctrl = PageController();
  int _page = 0;
  bool _agreed = false;

  /// F4：10 步引导内容。
  static final List<_Step> _steps = <_Step>[
    _Step(
      Icons.auto_awesome_rounded,
      '欢迎来到星璃',
      '声音 · 场景 · 世界的随身空间',
      '一个应用装下音乐、体素 3D 世界与你的自定义场景。花一分钟完成初始化，'
      '之后随时可在设置里调整一切。',
    ),
    _Step(
      Icons.explore_outlined,
      '界面介绍',
      '底部 5 Tab · 手势 · 全局主题',
      '主页（场景+播放）/ 曲库 / 世界（3D 入口）/ 探索 / 设置。左右滑切换场景，'
      '右上角主题按钮切换亮暗与皮肤。',
    ),
    _Step(
      Icons.palette_outlined,
      '个性化',
      '全局画面预设 + 主题模式',
      '四种预设一键套用：省电（关动效/24fps）/ 流畅（无特效+低模糊）/ 标准 / '
      '高质（全特效+液态玻璃）。后续在 设置 → 个性 随时切换。',
    ),
    _Step(
      Icons.videogame_asset_outlined,
      '游戏画质',
      '体素世界 · 独立画质档',
      '3D 世界画质 / 视距 / 帧率与全局画面独立，可在 设置 → 游戏 或游戏内调整，'
      '低端设备选「性能」档更流畅。',
    ),
    _Step(
      Icons.shield_outlined,
      '隐私与安全',
      '权限总览 · 数据脱敏',
      '日志默认脱敏（不落凭据）；第三方音源仅供个人学习；应用数据仅存本机。'
      '下一步统一申请必要权限。',
    ),
    _Step(
      Icons.notifications_active_outlined,
      '通知权限',
      '通知 / 媒体 / 存储',
      '用于后台播放、通知中心与读取本地音乐。Android 13+ 分级申请，'
      '可随时在 设置 → 通知 修改。',
    ),
    _Step(
      Icons.science_outlined,
      '实验性功能',
      '逐项启停 · 风险提示',
      '大模型设置、实验开关等在 设置 → 实验 中逐项管理；实验性功能可能不稳定，'
      '可随时关闭。',
    ),
    _Step(
      Icons.history_rounded,
      '版本日志',
      '自动获取最新日志',
      '设置 → 关于 → 版本日志 展示全部更新（当前 cl${AppVersion.buildCount}）。'
      '每次构建自动补录，最新在顶部。',
    ),
    _Step(
      Icons.system_update_alt_rounded,
      '更新检查',
      'GitHub Releases · OTA',
      '设置 → 关于 → 版本更新 自动检查新版本，下载后校验 SHA-256 哈希，'
      'hotfix 直接下载。发布流程开源在 GitHub。',
    ),
    _Step(
      Icons.description_outlined,
      '用户协议',
      '签署后进入',
      '请阅读并同意用户协议与隐私政策：本项目开源（MIT），第三方音源仅供个人'
      '学习研究，版权归原平台，勿商用二次分发。',
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(oobeDoneProvider.notifier).state = true;
    // 数据保护：重走流程不清数据——只标记完成，不重置任何统计。
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _grantPermissions() async {
    await PermissionService.requestAll();
    if (!mounted) return;
    _ctrl.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_page == _steps.length - 1) {
      if (_agreed) _finish();
      return;
    }
    _ctrl.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = context.appColors.accent;
    // F4：检测是否已有数据（播放统计非空 → 提示「合并且不清除数据」）。
    final bool hasData =
        ref.watch(playStatsProvider).valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // 顶部进度点（10 步 + 欢迎，11 点）。
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(
                    _steps.length + 1, (int i) {
                  final bool active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? accent
                          : (i < _page ? accent.withValues(alpha: 0.5) : const Color(0x44FFFFFF)),
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
                itemCount: _steps.length + 1, // +1 欢迎页
                onPageChanged: (int i) => setState(() => _page = i),
                itemBuilder: (BuildContext c, int i) {
                  // 第 0 页：欢迎（无内容步骤）。
                  if (i == 0) {
                    return _welcome(c, accent);
                  }
                  final _Step s = _steps[i - 1];
                  return _content(c, accent, s);
                },
              ),
            ),
            // 底部按钮区。
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: <Widget>[
                  if (_page > 0)
                    TextButton(
                      onPressed: () => _ctrl.previousPage(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                      ),
                      child: const Text('上一步',
                          style: TextStyle(color: Colors.white70)),
                    )
                  else
                    const Spacer(),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 14),
                    ),
                    icon: Icon(
                      _page == 5
                          ? Icons.shield_outlined
                          : (_page == _steps.length // 完成页
                              ? Icons.rocket_launch_rounded
                              : Icons.arrow_forward_rounded),
                      size: 18,
                    ),
                    label: Text(
                      _page == 5
                          ? '授权并继续'
                          : (_page == _steps.length
                              ? '进入星璃'
                              : '继续'),
                    ),
                    onPressed: _page == _steps.length && !_agreed
                        ? null
                        : () {
                            if (_page == 5) {
                              _grantPermissions();
                            } else {
                              _next();
                            }
                          },
                  ),
                ],
              ),
            ),
            if (_page == _steps.length) ...<Widget>[
              // 数据保护醒目提示（合并且不清除数据）。
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpace.sm),
                  decoration: BoxDecoration(
                    color: const Color(0x1A4CAF50),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: const Color(0x664CAF50)),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.merge_rounded,
                          size: 16, color: Color(0xFF81C784)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasData
                              ? '已检测到播放/收藏数据：本次流程仅合并，不会清除任何数据。'
                              : '本次流程不会清除任何已有数据。',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFC8E6C9)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 欢迎页（第 0 步）。
  Widget _welcome(BuildContext context, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: <Color>[
                  accent.withValues(alpha: 0.9),
                  accent.withValues(alpha: 0.2),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 52, color: Colors.white),
          ),
          const SizedBox(height: 28),
          Text(
            '星璃音乐 · 初始化',
            style: AppTextStyles.title.copyWith(
                color: Colors.white, fontSize: 26),
          ),
          const SizedBox(height: 8),
          Text(
            '${AppVersion.display} · ${AppVersion.brand}',
            style: AppTextStyles.body
                .copyWith(color: const Color(0xFFB8C4D8)),
          ),
          const SizedBox(height: 14),
          Text(
            '十步初始化：界面 · 个性 · 画质 · 权限 · 协议',
            textAlign: TextAlign.center,
            style: AppTextStyles.artist
                .copyWith(color: const Color(0xFF8A96AA)),
          ),
        ],
      ),
    );
  }

  /// 内容步骤页。
  Widget _content(BuildContext context, Color accent, _Step s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: <Color>[
                  accent.withValues(alpha: 0.85),
                  accent.withValues(alpha: 0.2),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(s.icon, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 26),
          Text(
            s.title,
            style: AppTextStyles.title
                .copyWith(color: Colors.white, fontSize: 24),
          ),
          const SizedBox(height: 8),
          Text(
            s.sub,
            style: AppTextStyles.body
                .copyWith(color: const Color(0xFFB8C4D8)),
          ),
          const SizedBox(height: 14),
          Text(
            s.desc,
            textAlign: TextAlign.center,
            style: AppTextStyles.artist
                .copyWith(color: const Color(0xFF8A96AA)),
          ),
          // 用户协议签署（第 10 步 = steps[9]）。
          if (s.title == '用户协议') ...<Widget>[
            const SizedBox(height: 20),
            CheckboxListTile(
              value: _agreed,
              onChanged: (bool? v) => setState(() => _agreed = v ?? false),
              title: const Text('我已阅读并同意《用户协议》与《隐私政策》',
                  style: TextStyle(fontSize: 12, color: Colors.white)),
              activeColor: accent,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}
