/// 用户反馈弹层（结构化：类型 + 快速预设 + 自由文本 + 可选附带日志）。
///
/// 提交后由官方 relay `/api/feedback` 自动建/同步 GitHub issue。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/content/content_providers.dart';
import '../../providers/settings/log_upload_providers.dart';
import '../../services/feedback_service.dart';
import '../../services/log_service.dart';

/// 打开用户反馈弹层。
Future<void> showFeedbackSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.bgSurface,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _FeedbackSheet(),
  );
}

/// 反馈类型（与 relay 标签对齐）。
const Map<String, String> _kFeedbackTypes = <String, String>{
  'bug': '缺陷',
  'suggestion': '建议',
  'performance': '性能',
  'ui': '界面',
  'other': '其他',
};

/// 快速预设（一键选，写入 preset 字段）。
const List<String> _kQuickPresets = <String>[
  '崩溃/闪退',
  '卡顿/耗电',
  '播放异常',
  '界面/排版',
  '功能建议',
  '音质/声音',
  '网络/投屏',
  '其他',
];

class _FeedbackSheet extends ConsumerStatefulWidget {
  const _FeedbackSheet();

  @override
  ConsumerState<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<_FeedbackSheet> {
  String _type = 'bug';
  String _preset = '';
  bool _attachLogs = true;
  String _status = '';
  bool _submitting = false;
  late final TextEditingController _textCtrl;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _status = '请先填写反馈内容');
      return;
    }
    setState(() {
      _submitting = true;
      _status = '提交中…';
    });
    final List<Map<String, String>>? logs = _attachLogs
        ? LogService.instance.recentIssues
            .map((Map<String, String> e) => <String, String>{
                  'ts': '',
                  'level': e['level'] ?? '',
                  'tag': e['tag'] ?? '',
                  'msg': e['msg'] ?? '',
                })
            .toList()
        : null;
    final FeedbackPayload payload = FeedbackPayload(
      type: _type,
      preset: _preset,
      text: text,
      version: AppVersion.displayShort,
      channel: AppVersion.channel.tag,
      os: Platform.operatingSystem,
      attachLogs: _attachLogs,
      logs: logs,
    );
    final String endpoint = ref.read(logUploadEndpointProvider);
    final FeedbackResult r = await FeedbackService().submit(payload, endpoint);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _status = r.ok
          ? (r.synced ? '已提交，感谢反馈（已自动建 issue）' : '已提交（relay 未接 GitHub，待人工处理）')
          : '提交失败：${r.error}';
    });
  }

  Widget _chip(String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.xs,
          ),
          decoration: BoxDecoration(
            color: active ? context.appColors.accent : context.appColors.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: active
                  ? context.appColors.accent
                  : context.appColors.border,
            ),
          ),
          child: Text(
            label,
            style: (active ? context.appText.body : context.appText.artist)
                .copyWith(
              color: active ? context.appColors.onAccent : null,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            AppSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.feedback_outlined,
                      size: AppSize.icon, color: context.appColors.accent),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text('反馈', style: context.appText.subtitle),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: AppSize.iconSm,
                        color: context.appColors.iconInactive),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                '崩溃/建议会经官方 relay 自动建 GitHub issue，便于跟踪修复。',
                style: context.appText.artist,
              ),
              const SizedBox(height: AppSpace.md),
              Text('类型', style: context.appText.body),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: <Widget>[
                  for (final MapEntry<String, String> e in _kFeedbackTypes.entries)
                    _chip(e.value, _type == e.key, () {
                      setState(() {
                        _type = e.key;
                        if (_type != 'bug') _attachLogs = false;
                      });
                    }),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              Text('快速预设', style: context.appText.body),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: <Widget>[
                  for (final String p in _kQuickPresets)
                    _chip(p, _preset == p, () {
                      setState(() => _preset = _preset == p ? '' : p);
                    }),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _textCtrl,
                maxLines: 5,
                minLines: 3,
                style: context.appText.body,
                decoration: InputDecoration(
                  labelText: '反馈内容',
                  hintText: '描述你遇到的问题或建议…',
                  hintStyle: context.appText.artist,
                  filled: true,
                  fillColor: context.appColors.bgCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: context.appColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: context.appColors.border),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('附带最近错误/告警日志', style: context.appText.body),
                subtitle: Text('仅发送已脱敏的 ERROR/WARN 摘要，便于定位',
                    style: context.appText.artist),
                value: _attachLogs,
                onChanged: (bool v) => setState(() => _attachLogs = v),
              ),
              const SizedBox(height: AppSpace.sm),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_submitting ? '提交中…' : '提交反馈'),
              ),
              if (_status.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpace.sm),
                Text(_status, style: context.appText.artist),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
