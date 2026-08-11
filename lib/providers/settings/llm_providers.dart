/// 第三方大模型配置（用户自配；apiKey 经 [SecureBox] AES-256 加密落盘）。
///
/// - 地址 / 模型名不敏感，走普通持久化（[SettingsRepository]）；
/// - API Key 敏感，只存内存 StateProvider + SecureBox 密文，绝不明文进
///   SharedPreferences，也不进日志。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/llm/llm_client.dart';
import '../../services/security/secure_store.dart';

/// 服务商地址（OpenAI 兼容；默认 OpenAI）。
final llmBaseUrlProvider = StateProvider<String>(
  (ref) => 'https://api.openai.com/v1',
);

/// 模型名（如 gpt-4o-mini / deepseek-chat）。
final llmModelProvider = StateProvider<String>((ref) => '');

/// API Key（内存态；已配置与否用 [llmApiKeySetProvider]，不向外暴露明文）。
final llmApiKeyProvider = StateProvider<String>((ref) => '');

/// 是否已设置 API Key（UI 只读这个，不读明文）。
final llmApiKeySetProvider = Provider<bool>(
  (ref) => ref.watch(llmApiKeyProvider).isNotEmpty,
);

/// 是否整体配置就绪（地址 + Key + 模型）。
final llmConfiguredProvider = Provider<bool>((ref) {
  final String base = ref.watch(llmBaseUrlProvider);
  final String model = ref.watch(llmModelProvider);
  final String key = ref.watch(llmApiKeyProvider);
  return base.trim().isNotEmpty && model.trim().isNotEmpty && key.trim().isNotEmpty;
});

/// 组合配置（供 [LlmClient] 使用）。
final llmConfigProvider = Provider<LlmConfig>((ref) => LlmConfig(
      baseUrl: ref.watch(llmBaseUrlProvider),
      apiKey: ref.watch(llmApiKeyProvider),
      model: ref.watch(llmModelProvider),
    ));

/// 聊天补全客户端。
final llmClientProvider = Provider<LlmClient>((ref) {
  final LlmClient client = LlmClient();
  ref.onDispose(client.dispose);
  return client;
});

/// 加密保险箱（复用 SecureBox）。
final llmSecureBoxProvider = Provider<SecureBox>((ref) => SecureBox());

/// 只读 Provider 取值函数（`WidgetRef.read` / `Ref.read` / `ProviderContainer.read` 均满足）。
typedef LlmReader = T Function<T>(ProviderListenable<T> provider);

/// 冷启动恢复 API Key（从 SecureBox 密文读回内存态）。由设置恢复流程调用。
Future<void> restoreLlmApiKey(LlmReader read) async {
  final String? key =
      await read(llmSecureBoxProvider).readSecret(SecureBox.kLlmApiKey);
  if (key != null && key.isNotEmpty) {
    read(llmApiKeyProvider.notifier).state = key;
  }
}

/// 保存 / 清除 API Key：加密落盘 + 更新内存态。
Future<void> saveLlmApiKey(LlmReader read, String key) async {
  final String trimmed = key.trim();
  read(llmApiKeyProvider.notifier).state = trimmed;
  if (trimmed.isEmpty) {
    await read(llmSecureBoxProvider).deleteSecret(SecureBox.kLlmApiKey);
  } else {
    await read(llmSecureBoxProvider).writeSecret(SecureBox.kLlmApiKey, trimmed);
  }
}
