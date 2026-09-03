/// ════════════════════════════════════════════════════════════════════════
/// ClassIsland 集控联动页
///
/// - 顶部：当前课 / 下一节 卡片（实时）
/// - 中部：今日课表列表（按开始时间排序）
/// - 底部/右上：集控服务器配置（URL + 班级标识）+ 立即同步
///
/// 说明：ClassIsland 集控体系由学校/机构部署服务端统一配置下发；本页作为
/// 被集控客户端展示课表/时间表，并支持播放状态上报（供集控后台可见）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/tools/classisland_provider.dart';
import '../../services/tools/control_server.dart';

/// ClassIsland 联动页。
class ClassIslandPage extends ConsumerStatefulWidget {
  const ClassIslandPage({super.key});

  @override
  ConsumerState<ClassIslandPage> createState() => _ClassIslandPageState();
}

class _ClassIslandPageState extends ConsumerState<ClassIslandPage> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _classCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _classCtrl = TextEditingController();
    Future<void>.delayed(
        Duration.zero, () => ref.read(classislandProvider.notifier).load());
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _classCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    await ref
        .read(classislandProvider.notifier)
        .configure(baseUrl: _urlCtrl.text, classId: _classCtrl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            _urlCtrl.text.trim().isEmpty ? '已清除集控配置' : '已保存并同步集控课表'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final ClassIslandState s = ref.watch(classislandProvider);
    final DateTime now = DateTime.now();
    // 每 30s 刷新「当前课」判定。
    final ClassPeriod? current = s.currentClassAt(now);
    final ClassPeriod? next = s.nextClassAt(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ClassIsland 联动'),
        actions: <Widget>[
          IconButton(
            tooltip: '同步',
            icon: const Icon(Icons.sync),
            onPressed: () =>
                ref.read(classislandProvider.notifier).sync(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _statusCard(c, s, current, next),
          const SizedBox(height: 16),
          _configCard(c, s),
          const SizedBox(height: 16),
          _controlCard(c),
          const SizedBox(height: 16),
          _todayClasses(c, s),
        ],
      ),
    );
  }

  /// 集控插件（被控端）状态卡：本机 localhost 控制服务。
  Widget _controlCard(AppThemeColors c) {
    final ControlServer svc = ControlServer.instance;
    final bool running = svc.running;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: running ? c.accent : c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                running ? Icons.memory : Icons.memory_outlined,
                size: 18,
                color: running ? c.accent : c.textTertiary,
              ),
              const SizedBox(width: 6),
              Text('集控插件（被控端）',
                  style: c.textPrimary.style(fontSize: 14, w700: true)),
              const Spacer(),
              if (running)
                Text('运行中', style: TextStyle(color: c.accent, fontSize: 12))
              else
                Text('未启动',
                    style: c.textTertiary.style(fontSize: 12)),
            ],
          ),
          if (svc.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(svc.error,
                  style: TextStyle(color: c.accent, fontSize: 12)),
            ),
          if (running) ...<Widget>[
            const SizedBox(height: 8),
            SelectableText(
              'http://127.0.0.1:${svc.port}/api/control',
              style: c.textSecondary.style(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              '动作：report / set_weather / set_volume / play / pause / notice',
              style: c.textTertiary.style(fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(AppThemeColors c, ClassIslandState s,
      ClassPeriod? current, ClassPeriod? next) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: s.connected ? c.accent : c.border,
          width: s.connected ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                s.connected
                    ? Icons.wifi_tethering
                    : Icons.cloud_off_outlined,
                size: 18,
                color: s.connected ? c.accent : c.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                s.connected ? '集控已连接' : '未连接集控',
                style: c.textPrimary.style(fontSize: 14, w700: true),
              ),
              const Spacer(),
              if (s.lastSync != null)
                Text(
                  '${s.lastSync!.hour.toString().padLeft(2, '0')}:'
                  '${s.lastSync!.minute.toString().padLeft(2, '0')} 同步',
                  style: c.textTertiary.style(fontSize: 11),
                ),
            ],
          ),
          if (s.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(s.error,
                  style: TextStyle(color: c.accent, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          // 当前课
          _bigLine(c, '当前', current?.name ?? '—',
              current == null ? '' : '${current.start} - ${current.end}'),
          const SizedBox(height: 8),
          // 下一节
          _bigLine(c, '下一节', next?.name ?? '—',
              next == null ? '' : '${next.start} 开始'),
          if (s.date.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('日期：${s.date}',
                  style: c.textTertiary.style(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _bigLine(AppThemeColors c, String label, String value, String sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 52,
          child: Text(label,
              style: c.textSecondary.style(fontSize: 13)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(value,
                  style: c.textPrimary.style(fontSize: 18, w700: true)),
              if (sub.isNotEmpty)
                Text(sub, style: c.textTertiary.style(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _configCard(AppThemeColors c, ClassIslandState s) {
    _urlCtrl.text = s.baseUrl;
    _classCtrl.text = s.classId;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('集控服务器', style: c.textPrimary.style(fontSize: 14, w700: true)),
          const SizedBox(height: 4),
          Text(
            '由学校/机构的 ClassIsland 集控端提供；留空则停用联动。\n'
            '协议：GET /api/classisland/status → { code, data:{ date, classes:[{start,end,name,teacher,room}] } }',
            style: c.textTertiary.style(fontSize: 11),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              hintText: 'https://classisland.example.com',
              prefixIcon: Icon(Icons.dns_outlined),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _classCtrl,
            decoration: const InputDecoration(
              hintText: '班级标识（可选，如 class-2026-3）',
              prefixIcon: Icon(Icons.badge_outlined),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _saveConfig,
            icon: const Icon(Icons.cloud_sync_outlined, size: 16),
            label: const Text('保存并同步'),
          ),
        ],
      ),
    );
  }

  Widget _todayClasses(AppThemeColors c, ClassIslandState s) {
    if (s.classes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('暂无课表（配置集控服务器后自动拉取）',
              style: c.textTertiary.style(fontSize: 13)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('今日课表（${s.classes.length} 节）',
            style: c.textPrimary.style(fontSize: 14, w700: true)),
        const SizedBox(height: 8),
        for (final ClassPeriod p in s.classes)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.bgSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 92,
                  child: Text('${p.start} - ${p.end}',
                      style: c.textSecondary.style(fontSize: 12)),
                ),
                Expanded(
                  child: Text(p.name,
                      style: c.textPrimary.style(fontSize: 14)),
                ),
                if (p.room.isNotEmpty)
                  Text(p.room,
                      style: c.textTertiary.style(fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 颜色 → 文本样式便捷扩展（本文件内使用）。
extension _ColorStyle on Color {
  TextStyle style({double fontSize = 14, bool w700 = false}) => TextStyle(
        color: this,
        fontSize: fontSize,
        fontWeight: w700 ? FontWeight.w700 : null,
      );
}
