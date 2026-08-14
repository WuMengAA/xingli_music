/// ════════════════════════════════════════════════════════════════════════
/// OOBE · 首次启动欢迎引导（Out Of Box Experience）
/// ════════════════════════════════════════════════════════════════════════
///
/// 首次启动显示 4 步引导（PageView 滑动）：
///   1. 欢迎 —— 品牌 + 一句话
///   2. 权限 —— 通知 / 存储授权（复用 PermissionService.requestAll）
///   3. 场景 —— 星璃世界介绍（音乐场景 / 3D 体素）
///   4. 完成 —— 开始使用（置 oobeDone=true，此后不再显示）
///
/// 挂载：AppShell 启动时 `!oobeDoneProvider` → 覆盖全屏显示本页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/performance_providers.dart';
import '../../services/permission_service.dart';

/// OOBE 全屏引导页（首次启动覆盖显示）。
class OobePage extends ConsumerStatefulWidget {
  const OobePage({super.key});

  @override
  ConsumerState<OobePage> createState() => _OobePageState();
}

class _OobePageState extends ConsumerState<OobePage> {
  final PageController _ctrl = PageController();
  int _page = 0;

  static const List<(IconData, String, String, String)> _steps =
      <(IconData, String, String, String)>[
    (
      Icons.auto_awesome_rounded,
      '欢迎来到星璃',
      '声音 · 场景 · 世界的随身空间',
      '用一个应用装下音乐、3D 体素世界与你的自定义场景。',
    ),
    (
      Icons.shield_outlined,
      '权限',
      '授权通知与媒体权限',
      '用于后台播放、通知中心与读取本地音乐文件。随时可在设置里修改。',
    ),
    (
      Icons.view_in_ar_rounded,
      '星璃世界',
      '3D 体素 · 手电筒 · 河流与昼夜',
      '在方块世界里自由探索、建造、取景拍摄场景，音乐融入环境。',
    ),
    (
      Icons.rocket_launch_rounded,
      '开始',
      '准备好了吗？',
      '现在进入星璃——之后可在设置中随时调整一切。',
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(oobeDoneProvider.notifier).state = true;
  }

  Future<void> _grantPermissions() async {
    await PermissionService.requestAll();
    if (!mounted) return;
    _ctrl.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = context.appColors.accent;
    final (IconData icon, String title, String sub, String desc) =
        _steps[_page];
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // 顶部进度点。
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(_steps.length, (int i) {
                  final bool active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? accent : const Color(0x44FFFFFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            // 页面主体（PageView 滑动）。
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _steps.length,
                onPageChanged: (int i) => setState(() => _page = i),
                itemBuilder: (BuildContext c, int i) {
                  final (IconData ic, String t, String s, String d) = _steps[i];
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
                          child: Icon(ic, size: 44, color: Colors.white),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          t,
                          style: AppTextStyles.title
                              .copyWith(color: Colors.white, fontSize: 26),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s,
                          style: AppTextStyles.body
                              .copyWith(color: const Color(0xFFB8C4D8)),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          d,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.artist
                              .copyWith(color: const Color(0xFF8A96AA)),
                        ),
                      ],
                    ),
                  );
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
                      _page == 1
                          ? Icons.shield_outlined
                          : _page == _steps.length - 1
                              ? Icons.rocket_launch_rounded
                              : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _page == 1
                          ? '授权并继续'
                          : _page == _steps.length - 1
                              ? '进入星璃'
                              : '继续',
                    ),
                    onPressed: () {
                      if (_page == 1) {
                        _grantPermissions();
                      } else if (_page == _steps.length - 1) {
                        _finish();
                      } else {
                        _ctrl.nextPage(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
