/// 第三方大模型设置弹层（用户自配；API Key 经 SecureBox AES-256 加密落盘）。
///
/// - 地址 / 模型名：普通持久化，实时保存；
/// - API Key：输入新值点「保存」才写（明文不回显；已设置时输入框留空 = 不变）；
/// - 测试连接：用当前表单里的配置发一条 system+user 测试消息。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/llm_providers.dart';
import '../../services/llm/llm_client.dart';

/// 打开大模型设置弹层。
Future<void> showLlmSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.bgSurface,
    // 桌面宽屏下收窄居中（避免整条全宽的 Material 默认弹层）。
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _LlmSettingsSheet(),
  );
}

class _LlmSettingsSheet extends ConsumerStatefulWidget {
  const _LlmSettingsSheet();

  @override
  ConsumerState<_LlmSettingsSheet> createState() => _LlmSettingsSheetState();
}

class _LlmSettingsSheetState extends ConsumerState<_LlmSettingsSheet> {
  late final TextEditingController _baseCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _keyCtrl;
  bool _obscureKey = true;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _baseCtrl =
        TextEditingController(text: ref.read(llmBaseUrlProvider));
    _modelCtrl = TextEditingController(text: ref.read(llmModelProvider));
    _keyCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _modelCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  String get _currentKey {
    final String typed = _keyCtrl.text.trim();
    return typed.isNotEmpty ? typed : ref.read(llmApiKeyProvider);
  }

  Future<void> _save() async {
    ref.read(llmBaseUrlProvider.notifier).state = _baseCtrl.text.trim();
    ref.read(llmModelProvider.notifier).state = _modelCtrl.text.trim();
    final String typed = _keyCtrl.text.trim();
    if (typed.isNotEmpty) {
      await saveLlmApiKey(ref.read, typed);
    }
    if (!mounted) return;
    setState(() => _status = '已保存${typed.isNotEmpty ? '（Key 已加密落盘）' : ''}');
  }

  Future<void> _clearKey() async {
    await saveLlmApiKey(ref.read, '');
    _keyCtrl.clear();
    if (!mounted) return;
    setState(() => _status = '已清除 API Key');
  }

  Future<void> _test() async {
    final LlmConfig config = LlmConfig(
      baseUrl: _baseCtrl.text.trim(),
      apiKey: _currentKey,
      model: _modelCtrl.text.trim(),
    );
    if (!config.valid) {
      setState(() => _status = '请先填全地址 / API Key / 模型名');
      return;
    }
    setState(() => _status = '测试中…');
    try {
      final String reply = await ref.read(llmClientProvider).chat(
            config: config,
            messages: const <LlmMessage>[
              LlmMessage(role: 'system', content: '只回复两个字：正常'),
              LlmMessage(role: 'user', content: '连接测试'),
            ],
            maxTokens: 20,
          );
      if (!mounted) return;
      setState(() => _status = '连接成功，模型回复：$reply');
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() => _status = '失败：${e.message}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = '失败：未知错误');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool keySet = ref.watch(llmApiKeySetProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 标题行
              Row(
                children: <Widget>[
                  Icon(Icons.smart_toy_outlined,
                      size: AppSize.icon, color: context.appColors.accent),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text('大模型设置', style: context.appText.subtitle),
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
                '接入任意 OpenAI 兼容大模型（OpenAI / DeepSeek / 中转 / 本地 vLLM）。'
                '配置后 AI 陪伴优先用大模型回复，失败自动回退离线模板。'
                'API Key 经 AES-256 加密仅存本机。',
                style: context.appText.artist,
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _baseCtrl,
                keyboardType: TextInputType.url,
                style: context.appText.body,
                decoration: _dec('接口地址', 'https://api.openai.com/v1'),
                onChanged: (_) => ref.read(llmBaseUrlProvider.notifier).state =
                    _baseCtrl.text.trim(),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _modelCtrl,
                style: context.appText.body,
                decoration: _dec('模型名', 'gpt-4o-mini / deepseek-chat'),
                onChanged: (_) => ref.read(llmModelProvider.notifier).state =
                    _modelCtrl.text.trim(),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _keyCtrl,
                obscureText: _obscureKey,
                style: context.appText.body,
                decoration: _dec(
                  keySet ? 'API Key（已设置，留空不变）' : 'API Key',
                  'sk-...',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: AppSize.iconSm,
                      color: context.appColors.iconInactive,
                    ),
                    onPressed: () =>
                        setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _test,
                    icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: const Text('测试连接'),
                  ),
                  if (keySet)
                    TextButton.icon(
                      onPressed: _clearKey,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('清除 Key'),
                    ),
                ],
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

  InputDecoration _dec(String label, String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: context.appText.artist,
      suffixIcon: suffixIcon,
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
    );
  }
}
