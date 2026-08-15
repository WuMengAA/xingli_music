/// ════════════════════════════════════════════════════════════════════════
/// OOBE · 初始化流程（Out Of Box Experience，F4 重做 + cl58 选项/示意图）
/// ════════════════════════════════════════════════════════════════════════
///
/// 带用户过一遍完整的初始化流程（PageView 滑动 / 按钮推进），每步配
/// **简单示意图** + 关键步骤直接提供**可选项**（即时写入 provider）：
///   0. 欢迎        —— 品牌 + 一句话 + 开始按钮
///   1. 界面介绍    —— 底部 5 Tab 示意图
///   2. 个性化      —— 全局画面预设四档选项 + 主题模式选项
///   3. 游戏画质    —— 游戏画质四档选项（独立于全局）
///   4. 隐私与安全  —— 权限总览示意图 + 数据脱敏说明
///   5. 通知权限    —— 授权通知 / 媒体 / 存储（复用 PermissionService.requestAll）
///   6. 实验性功能  —— 实验开关入口示意图 + 风险提示
///   7. 版本日志    —— 自动获取最新日志（changelog 首条）
///   8. 更新检查    —— OTA 更新说明（GitHub Releases / 哈希校验）
///   9. 用户协议    —— 签署用户协议（同意后进入）
///  10. 完成        —— 丝滑过渡到主页（置 oobeDone=true）
///
/// 触发：首次启动覆盖全屏 / 设置-关于-初始化流程 / 版本升级后弹询问。
/// 数据保护：检测到已有数据 → 完成页醒目提示「合并且不清除数据」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/experiment.dart';
import '../../providers/explore/experiment_providers.dart';
import '../../providers/settings/performance_providers.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../providers/voxel/graphics_quality_provider.dart';
import '../../services/ota_service.dart';
import '../../services/permission_service.dart';
import '../../widgets/notification/app_notify.dart';
import '../../widgets/voxel/voxel_world_view3d.dart' show GraphicsQuality;

/// OOBE 全屏引导页。
class OobePage extends ConsumerStatefulWidget {
  const OobePage({super.key});

  @override
  ConsumerState<OobePage> createState() => _OobePageState();
}

/// 单个引导步骤（含示意图类型）。
class _Step {
  const _Step(this.icon, this.title, this.sub, this.desc, this.diagram);

  final IconData icon;
  final String title;
  final String sub;
  final String desc;

  /// 示意图类型（_Diagram 按此渲染简单图示）。
  final _DiagramKind diagram;
}

/// 示意图类型。
enum _DiagramKind {
  nav, // 底部 5 Tab
  preset, // 全局画面预设四档
  gameQuality, // 游戏画质档
  shield, // 隐私权限
  bell, // 通知
  flask, // 实验
  log, // 版本日志
  update, // OTA
  contract, // 协议
  none,
}

class _OobePageState extends ConsumerState<OobePage> {
  final PageController _ctrl = PageController();
  int _page = 0;
  bool _agreed = false;

  /// 10 步引导内容。
  static final List<_Step> _steps = <_Step>[
    _Step(
      Icons.explore_outlined,
      '界面介绍',
      '底部 5 Tab · 手势 · 全局主题',
      '主页（场景+播放）/ 曲库 / 世界（3D 入口）/ 探索 / 设置。左右滑切换场景，'
      '右上角主题按钮切换亮暗与皮肤。',
      _DiagramKind.nav,
    ),
    _Step(
      Icons.palette_outlined,
      '个性化',
      '全局画面预设 + 主题模式',
      '选择你偏好的全局画面效果与主题，随时可在 设置 → 个性 切换。',
      _DiagramKind.preset,
    ),
    _Step(
      Icons.videogame_asset_outlined,
      '游戏画质',
      '体素世界 · 独立画质档',
      '3D 世界画质与全局画面独立；低端设备选「低/极低」更流畅。',
      _DiagramKind.gameQuality,
    ),
    _Step(
      Icons.shield_outlined,
      '隐私与安全',
      '权限总览 · 数据脱敏',
      '日志默认脱敏（不落凭据）；第三方音源仅供个人学习；应用数据仅存本机。',
      _DiagramKind.shield,
    ),
    _Step(
      Icons.notifications_active_outlined,
      '通知权限',
      '通知 / 媒体 / 存储',
      '用于后台播放、通知中心与读取本地音乐。Android 13+ 分级申请，'
      '可随时在 设置 → 通知 修改。',
      _DiagramKind.bell,
    ),
    _Step(
      Icons.science_outlined,
      '实验性功能',
      '逐项启停 · 风险提示',
      '大模型设置、实验开关等在 设置 → 实验 中逐项管理；实验性功能可能不稳定。',
      _DiagramKind.flask,
    ),
    _Step(
      Icons.history_rounded,
      '版本日志',
      '自动获取最新日志',
      '设置 → 关于 → 版本日志 展示全部更新（当前 cl${AppVersion.buildCount}）。',
      _DiagramKind.log,
    ),
    _Step(
      Icons.system_update_alt_rounded,
      '更新检查',
      'GitHub Releases · OTA',
      '自动检查新版本，下载后校验 SHA-256 哈希，hotfix 直接下载。',
      _DiagramKind.update,
    ),
    _Step(
      Icons.description_outlined,
      '用户协议',
      '签署后进入',
      '项目开源（MIT），第三方音源仅供个人学习研究，版权归原平台，'
      '勿商用二次分发。',
      _DiagramKind.contract,
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
    if (_page == _steps.length) {
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
    // 数据保护：检测是否已有数据（播放统计非空 → 提示「合并且不清除数据」）。
    final bool hasData =
        ref.watch(playStatsProvider).valueOrNull?.isNotEmpty ?? false;
    final bool isFinish = _page == _steps.length;
    final bool isPerm = _page == 5;
    // 内容步（第 0 页欢迎 + 第 1~9 内容 + 第 10 完成 = 共 11 页）。

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // 顶部进度点（11 点：欢迎 + 10 步）。
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(
                    _steps.length + 2, (int i) {
                  final bool active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? accent
                          : (i < _page
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
                itemCount: _steps.length + 2, // 欢迎 + 10 步 + 完成
                onPageChanged: (int i) => setState(() => _page = i),
                itemBuilder: (BuildContext c, int i) {
                  if (i == 0) return _welcome(c, accent);
                  if (i == _steps.length + 1) return _finishPage(c, accent, hasData);
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
                      isPerm
                          ? Icons.shield_outlined
                          : (isFinish
                              ? Icons.rocket_launch_rounded
                              : Icons.arrow_forward_rounded),
                      size: 18,
                    ),
                    label: Text(
                      isPerm
                          ? '授权并继续'
                          : (isFinish ? '进入星璃' : '继续'),
                    ),
                    onPressed: isFinish && !_agreed
                        ? null
                        : () {
                            if (isPerm) {
                              _grantPermissions();
                            } else {
                              _next();
                            }
                          },
                  ),
                ],
              ),
            ),
            if (isFinish) ...<Widget>[
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

  /// 欢迎页（第 0 页）。
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

  /// 完成页。
  Widget _finishPage(BuildContext context, Color accent, bool hasData) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: <Color>[
                  accent.withValues(alpha: 0.85),
                  accent.withValues(alpha: 0.2),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.rocket_launch_rounded,
                size: 44, color: Colors.white),
          ),
          const SizedBox(height: 26),
          Text(
            '准备好了',
            style: AppTextStyles.title
                .copyWith(color: Colors.white, fontSize: 24),
          ),
          const SizedBox(height: 8),
          Text(
            '初始化完成，进入星璃',
            style: AppTextStyles.body
                .copyWith(color: const Color(0xFFB8C4D8)),
          ),
          const SizedBox(height: 14),
          Text(
            '所有设置均可随时在「设置」中调整。',
            textAlign: TextAlign.center,
            style: AppTextStyles.artist
                .copyWith(color: const Color(0xFF8A96AA)),
          ),
        ],
      ),
    );
  }

  /// 内容步骤页：示意图 + 说明 + 可选配置。
  Widget _content(BuildContext context, Color accent, _Step s) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // 简单示意图。
          _Diagram(kind: s.diagram, accent: accent),
          const SizedBox(height: 20),
          Text(
            s.title,
            style: AppTextStyles.title
                .copyWith(color: Colors.white, fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            s.sub,
            textAlign: TextAlign.center,
            style: AppTextStyles.body
                .copyWith(color: const Color(0xFFB8C4D8)),
          ),
          const SizedBox(height: 10),
          Text(
            s.desc,
            textAlign: TextAlign.center,
            style: AppTextStyles.artist
                .copyWith(color: const Color(0xFF8A96AA)),
          ),
          const SizedBox(height: 16),
          // 可选项（按步骤类型注入实际配置控件）。
          _Options(kind: s.diagram, accent: accent),
          // 用户协议签署。
          if (s.title == '用户协议') ...<Widget>[
            const SizedBox(height: 12),
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

/// 简单示意图（纯 Flutter 组件绘制，无图片资源依赖）。
class _Diagram extends StatelessWidget {
  const _Diagram({required this.kind, required this.accent});

  final _DiagramKind kind;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case _DiagramKind.nav:
        // 底部 5 Tab 示意。
        return _box(
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              for (final IconData ic in <IconData>[
                Icons.home_outlined,
                Icons.library_music_outlined,
                Icons.public_outlined,
                Icons.explore_outlined,
                Icons.settings_outlined,
              ])
                Icon(ic, size: 20, color: Colors.white70),
            ],
          ),
        );
      case _DiagramKind.preset:
        // 四档预设示意。
        return _box(
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              for (final int i in List<int>.generate(4, (int i) => i))
                Column(
                  children: <Widget>[
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.25 + 0.18 * i),
                      ),
                      child: Icon(Icons.palette_outlined,
                          size: 14, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(['省电', '流畅', '标准', '高质'][i],
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white70)),
                  ],
                ),
            ],
          ),
        );
      case _DiagramKind.gameQuality:
        return _box(
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              for (final String l in <String>['极低', '低', '中', '高'])
                Column(
                  children: <Widget>[
                    Container(
                      width: 30,
                      height: 18,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2 + 0.2 * (['极低', '低', '中', '高'].indexOf(l))),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(l,
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white70)),
                  ],
                ),
            ],
          ),
        );
      case _DiagramKind.shield:
        return _box(const Icon(Icons.shield_outlined,
            size: 40, color: Colors.white70));
      case _DiagramKind.bell:
        return _box(const Icon(Icons.notifications_active_outlined,
            size: 40, color: Colors.white70));
      case _DiagramKind.flask:
        return _box(const Icon(Icons.science_outlined,
            size: 40, color: Colors.white70));
      case _DiagramKind.log:
        return _box(const Icon(Icons.history_rounded,
            size: 40, color: Colors.white70));
      case _DiagramKind.update:
        return _box(const Icon(Icons.system_update_alt_rounded,
            size: 40, color: Colors.white70));
      case _DiagramKind.contract:
        return _box(const Icon(Icons.description_outlined,
            size: 40, color: Colors.white70));
      case _DiagramKind.none:
        return const SizedBox.shrink();
    }
  }

  Widget _box(Widget child) {
    return Container(
      width: 200,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: child,
    );
  }
}

/// 可选项（关键步骤直接写入 provider）。
class _Options extends ConsumerWidget {
  const _Options({required this.kind, required this.accent});

  final _DiagramKind kind;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (kind) {
      case _DiagramKind.preset:
        // 全局画面预设四档（直接套用）。
        final PicturePreset p = ref.watch(picturePresetProvider);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final PicturePreset x in PicturePreset.values)
              ChoiceChip(
                label: Text(x.label,
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
                selected: p == x,
                onSelected: (_) => applyPicturePreset(ref, x),
                backgroundColor: const Color(0x1AFFFFFF),
                selectedColor: accent,
                side: const BorderSide(color: Color(0x33FFFFFF)),
              ),
          ],
        );
      case _DiagramKind.gameQuality:
        // 游戏画质四档（独立于全局）。
        final GraphicsQuality q = ref.watch(graphicsQualityProvider);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final GraphicsQuality g in GraphicsQuality.values)
              ChoiceChip(
                label: Text(g.label,
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
                selected: q == g,
                onSelected: (_) =>
                    ref.read(graphicsQualityProvider.notifier).state = g,
                backgroundColor: const Color(0x1AFFFFFF),
                selectedColor: accent,
                side: const BorderSide(color: Color(0x33FFFFFF)),
              ),
          ],
        );
      case _DiagramKind.shield:
        // cl59：隐私与安全——索要权限（通知 + 存储）。
        return _pillButton(
          context,
          icon: Icons.shield_outlined,
          label: '索要权限',
          onTap: () async {
            await PermissionService.requestAll();
            if (context.mounted) appNotify(context, '权限已处理');
          },
        );
      case _DiagramKind.bell:
        // cl59：通知——索要通知权限。
        return _pillButton(
          context,
          icon: Icons.notifications_active_outlined,
          label: '索要通知权限',
          onTap: () async {
            await PermissionService.requestEssentialOnStartup();
            if (context.mounted) appNotify(context, '通知权限已处理');
          },
        );
      case _DiagramKind.flask:
        // cl59：实验性功能——选择同意与否。
        final ExperimentConsent consent =
            ref.watch(experimentConsentProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              consent.agreed ? '已同意 · 实验可用' : '未同意 · 实验关闭',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _pillButton(
                  context,
                  icon: Icons.check_rounded,
                  label: '同意',
                  filled: true,
                  onTap: () => ref
                      .read(experimentConsentProvider.notifier)
                      .agree(),
                ),
                const SizedBox(width: 8),
                _pillButton(
                  context,
                  icon: Icons.close_rounded,
                  label: '不同意',
                  onTap: () => ref
                      .read(experimentConsentProvider.notifier)
                      .revoke(),
                ),
              ],
            ),
          ],
        );
      case _DiagramKind.log:
        // cl59：版本日志——拉取本地更新日志（changelog 前几条）。
        final List<ChangelogEntry> logs = changelog.take(3).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final ChangelogEntry e in logs)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${e.cl} · ${e.title}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white70),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      case _DiagramKind.update:
        // cl59：版本检查——按流程走一遍，有更新提示更新，超时提示继续。
        return _pillButton(
          context,
          icon: Icons.system_update_alt_rounded,
          label: '检查更新',
          onTap: () async {
            final OtaCheckResult r = await OtaService.instance.checkForUpdate();
            if (!context.mounted) return;
            if (r.hasUpdate) {
              appNotify(context, '发现新版本：${r.latestTag}（可在设置→关于更新）');
            } else {
              appNotify(context, '已是最新版本 / 检查超时，可继续初始化');
            }
          },
        );
      case _DiagramKind.contract:
        // cl59：用户协议——贴 GitHub 仓库与 LICENSE 链接。
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _linkRow(context, 'GitHub 仓库', 'github.com/WuMengAA/xingli_music'),
            const SizedBox(height: 6),
            _linkRow(context, '开源协议', 'github.com/WuMengAA/xingli_music/blob/main/LICENSE'),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// 胶囊按钮（OOBE 内通用）。
  Widget _pillButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: filled ? accent : const Color(0x1AFFFFFF),
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0x33FFFFFF)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }

  /// 链接行（显示可复制链接）。
  Widget _linkRow(BuildContext context, String label, String url) {
    return InkWell(
      onTap: () {
        // 复制链接到剪贴板（OOBE 无浏览器依赖）。
        appNotify(context, '已复制：$url');
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.link_rounded, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.white)),
            const SizedBox(width: 8),
            Text(url,
                style: const TextStyle(
                    fontSize: 10, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}
