import 'package:flutter/material.dart';

import '../../services/log_service.dart';
import '../../widgets/settings/log_upload_sheet.dart';

/// 程序最后底线（崩溃界面）：widget 构建期抛错时由 `ErrorWidget.builder`
/// 渲染，替代默认红屏——程序**不退出**，列出最近异常日志（已脱敏），
/// 并提供「重新启动」「日志上报」两个出口。
///
///  deliberately 不依赖任何 Theme / 自定义 extension（避免崩溃发生在主题构建
/// 时引发递归），全部用硬编码颜色，保证自身永不二次抛错。
class CrashScreen extends StatelessWidget {
  const CrashScreen({
    super.key,
    required this.details,
    required this.onRestart,
  });

  final FlutterErrorDetails? details;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    // 直接读内存中的最近异常窗口（LogService 内部维护，永不抛异常）。
    final List<Map<String, String>> issues = LogService.instance.recentIssues;

    return Container(
      color: const Color(0xFF121418),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFFE8ECF2), fontSize: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Icon(Icons.error_outline_rounded,
                    size: 44, color: Color(0xFFFFB74D)),
                const SizedBox(height: 12),
                const Text('程序遇到问题，但仍在运行',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text(
                  '已记录异常日志（已脱敏）。可重新启动，或上报日志协助定位。',
                  style: TextStyle(color: Color(0xFF9AA4B2)),
                ),
                const SizedBox(height: 12),
                if (details != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0x33FF6B6B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      details!.exceptionAsString(),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1F26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: issues.isEmpty
                        ? const Center(
                            child: Text('暂无异常记录',
                                style: TextStyle(color: Color(0xFF9AA4B2))))
                        : ListView.separated(
                            itemCount: issues.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: Color(0xFF2A2F38)),
                            itemBuilder: (BuildContext _, int i) {
                              final Map<String, String> e = issues[i];
                              return Text(
                                '[${e['level']}] ${e['tag']}：${e['msg']}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onRestart,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('重新启动'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => showLogUploadSheet(context),
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('日志上报'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
