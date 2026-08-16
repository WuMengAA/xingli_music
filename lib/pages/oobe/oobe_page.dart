/// ════════════════════════════════════════════════════════════════════════
/// OOBE · 初始化流程重做（cl75：六支柱）
/// ════════════════════════════════════════════════════════════════════════
///
/// 围绕「实用性 + 引导性 + 简洁」重做，全程不出现版本号 / 构建号 / changelog
/// 等内部标识。通过 8 页把用户真正需要的选择与同意摆上桌：
///   0. 欢迎        —— 品牌 + 一句引导（无版本号）
///   1. 内容        —— 三个核心价值点（为什么用）
///   2. 展示        —— 能力卡片（能做什么）
///   3. 选择        —— 音质 / 外观 / 皮肤 / 画质，即时写入 provider（落库）
///   4. 询问        —— 常听场景多选 + 匿名体验改进同意
///   5. 意见采纳    —— 汇总所有选择，可「上一步」回改
///   6. 合同        —— 条款可展开 + 真链接可点 + 必勾同意
///   7. 完成        —— 静默申请权限后进入（修复原 off-by-one 不可达）
///
/// 触发：首次启动覆盖全屏 / 设置-关于-初始化流程 / 版本升级后弹询问。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/theme/theme_skins.dart';
import '../../providers/settings/oobe_choice_providers.dart';
import '../../providers/settings/performance_providers.dart';
import '../../providers/theme/theme_providers.dart';
import '../../providers/voxel/graphics_quality_provider.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../services/open_url.dart';
import '../../services/permission_service.dart';
import '../../widgets/voxel/voxel_world_view3d.dart' show GraphicsQuality;

/// OOBE 全屏引导页。
class OobePage extends ConsumerStatefulWidget {
  const OobePage({super.key});

  @override
  ConsumerState<OobePage> createState() => _OobePageState();
}

class _OobePageState extends ConsumerState<OobePage> {
  static const int _pageCount = 8; // 欢迎 + 6 支柱 + 完成

  final PageController _ctrl = PageController();
  int _page = 0;
  bool _agreed = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(oobeDoneProvider.notifier).state = true;
    // 权限在流程末尾静默申请（不阻塞、不弹解释框）。
    unawaited(PermissionService.requestEssentialOnStartup());
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _next() {
    if (_page == 6 && !_agreed) return; // 合同页未同意不可前进
    _ctrl.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = context.appColors.accent;
    final bool hasData =
        ref.watch(playStatsProvider).valueOrNull?.isNotEmpty ?? false;
    final int page = _page;
    final bool isFinish = page == _pageCount - 1; // 7 完成
    final bool isContract = page == 6; // 6 合同

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // 顶部进度点（8 点）。
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
                  if (i == 0) return _welcome(c, accent);
                  if (i == _pageCount - 1) {
                    return _finishPage(c, accent, hasData);
                  }
                  if (i == 6) return _contractPage(c, accent);
                  if (i == 5) return _summaryPage(c, accent);
                  if (i == 4) return _inquiryPage(c, accent);
                  if (i == 3) return _choicePage(c, accent);
                  if (i == 2) return _displayPage(c, accent);
                  return _contentPage(c, accent); // i == 1
                },
              ),
            ),
            // 底部按钮区。
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
                      isFinish
                          ? Icons.rocket_launch_rounded
                          : (isContract
                              ? Icons.check_circle_outline_rounded
                              : Icons.arrow_forward_rounded),
                      size: 18,
                    ),
                    label: Text(
                      isFinish
                          ? '进入星璃'
                          : (isContract ? '同意并继续' : '继续'),
                    ),
                    onPressed: (isContract && !_agreed) ||
                            (isFinish && !_agreed)
                        ? null
                        : () {
                            if (isFinish) {
                              _finish();
                            } else {
                              _next();
                            }
                          },
                  ),
                ],
              ),
            ),
            if (isFinish) _dataProtect(accent, hasData),
          ],
        ),
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
        style: AppTextStyles.title
            .copyWith(color: Colors.white, fontSize: 22),
        textAlign: TextAlign.center,
      );

  Widget _sub(String t) => Text(
        t,
        textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(color: const Color(0xFFB8C4D8)),
      );

  Widget _groupLabel(String t) =>
      Text(t, style: const TextStyle(fontSize: 13, color: Colors.white70));

  Widget _chip(
    Color accent,
    String label,
    bool selected,
    VoidCallback onTap,
  ) =>
      ChoiceChip(
        label:
            Text(label, style: const TextStyle(fontSize: 13, color: Colors.white)),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: const Color(0x1AFFFFFF),
        selectedColor: accent,
        side: const BorderSide(color: Color(0x33FFFFFF)),
      );

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 64,
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.white54)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 14, color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _valueRow(
    Color accent,
    IconData icon,
    String title,
    String desc,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70, height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _capCard(
    Color accent,
    IconData icon,
    String title,
    String desc,
  ) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: accent, size: 24),
            const SizedBox(height: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(desc,
                style: const TextStyle(
                    fontSize: 11, color: Colors.white70, height: 1.5)),
          ],
        ),
      );

  Widget _dataProtect(Color accent, bool hasData) => Padding(
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
                      ? '已检测到播放/收藏数据：本次仅合并，不会清除任何数据。'
                      : '本次不会清除任何已有数据。',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFC8E6C9)),
                ),
              ),
            ],
          ),
        ),
      );

  // ── 各页 ─────────────────────────────────────────

  /// 0 欢迎（无版本号）。
  Widget _welcome(BuildContext context, Color accent) => _scroll(
        Column(
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
            Text('星璃音乐',
                style: AppTextStyles.title
                    .copyWith(color: Colors.white, fontSize: 26)),
            const SizedBox(height: 8),
            Text('欢迎，先把听歌环境调好',
                style: AppTextStyles.body
                    .copyWith(color: const Color(0xFFB8C4D8))),
            const SizedBox(height: 14),
            Text('几步设置，马上开始',
                textAlign: TextAlign.center,
                style: AppTextStyles.artist
                    .copyWith(color: const Color(0xFF8A96AA))),
          ],
        ),
      );

  /// 1 内容：三个核心价值点。
  Widget _contentPage(BuildContext context, Color accent) => _scroll(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _title(accent, '为场景而生的音乐'),
            const SizedBox(height: 8),
            _sub('不止播放，更懂你要的氛围'),
            const SizedBox(height: 22),
            _valueRow(accent, Icons.nightlight_round, '场景化聆听',
                '按睡眠、专注、放松自动匹配合适的意境音乐与白噪音'),
            _valueRow(accent, Icons.public, '体素世界',
                '边听边逛的 3D 星璃世界，还能邀请好友一起联机'),
            _valueRow(accent, Icons.link, '开放音源',
                '接入网易云、B站等，供个人学习研究使用'),
            const SizedBox(height: 16),
          ],
        ),
      );

  /// 2 展示：能力卡片。
  Widget _displayPage(BuildContext context, Color accent) => _scroll(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _title(accent, '看看都能做什么'),
            const SizedBox(height: 8),
            _sub('把音乐、画面与世界连在一起'),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: <Widget>[
                _capCard(accent, Icons.graphic_eq, '场景意境',
                    '音乐 + 画面 + 白噪音融合'),
                _capCard(accent, Icons.palette, '个性主题',
                    '多套皮肤 / 亮暗切换'),
                _capCard(accent, Icons.view_in_ar, '3D 世界',
                    '可联机的体素世界'),
                _capCard(accent, Icons.groups, '一起听',
                    '与好友同步播放'),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      );

  /// 3 选择：音质 / 外观 / 皮肤 / 画质，即时落库。
  Widget _choicePage(BuildContext context, Color accent) {
    final int aq = ref.watch(audioQualityProvider);
    final String tm = ref.watch(themeModeNameProvider);
    final String sk = ref.watch(themeSkinProvider);
    final GraphicsQuality gq = ref.watch(graphicsQualityProvider);
    return _scroll(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _title(accent, '选几项你喜欢的'),
          const SizedBox(height: 8),
          _sub('都会立刻生效，之后也能在「设置」里改'),
          const SizedBox(height: 20),
          _groupLabel('音质'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final int v in const <int>[0, 1, 2])
                _chip(accent, kAudioQualityLabels[v]!, aq == v,
                    () => ref.read(audioQualityProvider.notifier).state = v),
            ],
          ),
          const SizedBox(height: 16),
          _groupLabel('外观'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final MapEntry<String, String> e
                  in const <String, String>{
                    'light': '亮',
                    'dark': '暗',
                    'system': '跟随系统',
                  }.entries)
                _chip(accent, e.value, tm == e.key,
                    () => ref.read(themeModeNameProvider.notifier).state = e.key),
            ],
          ),
          const SizedBox(height: 16),
          _groupLabel('皮肤'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final ThemeSkin s in ThemeSkins.all)
                _chip(accent, s.name, sk == s.id,
                    () => ref.read(themeSkinProvider.notifier).state = s.id),
            ],
          ),
          const SizedBox(height: 16),
          _groupLabel('画质'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final GraphicsQuality g in GraphicsQuality.values)
                _chip(accent, g.label, gq == g,
                    () => ref.read(graphicsQualityProvider.notifier).state = g),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 4 询问：常听场景多选 + 匿名体验改进同意。
  Widget _inquiryPage(BuildContext context, Color accent) {
    final Set<String> sel = ref.watch(listenSourcesProvider);
    final bool an = ref.watch(analyticsConsentProvider);
    return _scroll(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _title(accent, '告诉我们你的偏好'),
          const SizedBox(height: 8),
          _sub('帮我们把内容调得更合你胃口'),
          const SizedBox(height: 20),
          _groupLabel('你主要听什么（可多选）'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final String o in kListenSourceOptions)
                _chip(accent, o, sel.contains(o), () {
                  final Set<String> next = Set<String>.from(sel);
                  if (next.contains(o)) {
                    next.remove(o);
                  } else {
                    next.add(o);
                  }
                  ref.read(listenSourcesProvider.notifier).state = next;
                }),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: SwitchListTile(
              value: an,
              onChanged: (bool v) =>
                  ref.read(analyticsConsentProvider.notifier).state = v,
              activeThumbColor: accent,
              title: const Text('允许匿名体验改进',
                  style: TextStyle(fontSize: 14, color: Colors.white)),
              subtitle: const Text(
                  '仅发送匿名统计改进体验，不含账号与曲目，可随时关闭',
                  style: TextStyle(fontSize: 11, color: Colors.white70)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 5 意见采纳：汇总所有选择，可回改。
  Widget _summaryPage(BuildContext context, Color accent) {
    final int aq = ref.watch(audioQualityProvider);
    final String tm = ref.watch(themeModeNameProvider);
    final String sk = ref.watch(themeSkinProvider);
    final GraphicsQuality gq = ref.watch(graphicsQualityProvider);
    final Set<String> ls = ref.watch(listenSourcesProvider);
    final bool an = ref.watch(analyticsConsentProvider);
    final String tmLabel =
        const <String, String>{'light': '亮', 'dark': '暗', 'system': '跟随系统'}[tm] ??
            tm;
    final String skinLabel = ThemeSkins.byId(sk)?.name ?? sk;
    final String lsLabel = ls.isEmpty ? '未选择' : ls.join(' · ');
    return _scroll(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _title(accent, '确认一下你的选择'),
          const SizedBox(height: 8),
          _sub('我们都记下了，之后也能在「设置」里改'),
          const SizedBox(height: 18),
          _summaryRow('音质', kAudioQualityLabels[aq] ?? '标准'),
          _summaryRow('外观', tmLabel),
          _summaryRow('皮肤', skinLabel),
          _summaryRow('画质', gq.label),
          _summaryRow('常听', lsLabel),
          _summaryRow('体验改进', an ? '已开启' : '未开启'),
          const SizedBox(height: 14),
          Text('如需调整，点左上「上一步」返回修改',
              style: AppTextStyles.artist
                  .copyWith(color: const Color(0xFF8A96AA))),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 6 合同：条款可展开 + 真链接可点 + 必勾同意。
  Widget _contractPage(BuildContext context, Color accent) => _scroll(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _title(accent, '同意条款后继续使用'),
            const SizedBox(height: 8),
            _sub('内容已为你准备好，链接也能直接打开'),
            const SizedBox(height: 16),
            _contractTile(accent, '服务条款',
                '星璃音乐为开源（MIT）项目，供个人学习与研究使用。第三方音源（网易云、B站等）的版权归原平台所有，仅限个人学习，请勿用于商业或二次分发。使用本软件即表示你理解并自行承担相关风险。'),
            const SizedBox(height: 8),
            _contractTile(accent, '隐私政策',
                '你的数据仅保存在本机。日志默认脱敏，不收集账号密码与具体曲目标题。可选的「匿名体验改进」仅发送匿名统计，关闭后不发送任何信息。我们不会向第三方出售你的数据。'),
            const SizedBox(height: 10),
            _linkRow(context, '查看开源仓库与完整协议',
                'https://github.com/WuMengAA/xingli_music'),
            const SizedBox(height: 14),
            CheckboxListTile(
              value: _agreed,
              onChanged: (bool? v) => setState(() => _agreed = v ?? false),
              activeColor: accent,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('我已阅读并同意《服务条款》与《隐私政策》',
                  style: TextStyle(fontSize: 13, color: Colors.white)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );

  Widget _contractTile(Color accent, String title, String body) => Container(
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Theme(
          data: Theme.of(context)
              .copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(title,
                style: const TextStyle(fontSize: 14, color: Colors.white)),
            iconColor: accent,
            collapsedIconColor: Colors.white70,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(body,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70, height: 1.5)),
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
              const Icon(Icons.open_in_new_rounded,
                  size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(url,
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white54),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  /// 7 完成。
  Widget _finishPage(BuildContext context, Color accent, bool hasData) => _scroll(
        Column(
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
            Text('准备好了',
                style: AppTextStyles.title
                    .copyWith(color: Colors.white, fontSize: 24)),
            const SizedBox(height: 8),
            Text('进入星璃，开始听歌',
                style: AppTextStyles.body
                    .copyWith(color: const Color(0xFFB8C4D8))),
            const SizedBox(height: 14),
            Text('所有设置都能在「设置」中随时调整。',
                textAlign: TextAlign.center,
                style: AppTextStyles.artist
                    .copyWith(color: const Color(0xFF8A96AA))),
          ],
        ),
      );
}
