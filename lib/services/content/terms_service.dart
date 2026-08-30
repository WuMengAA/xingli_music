/// ════════════════════════════════════════════════════════════════════════
/// 服务条款 / 隐私政策 · 拉取服务（cl17 · 目标6）
/// ════════════════════════════════════════════════════════════════════════
///
/// 优先从 GitHub 仓库拉取最新条款文本（开源兼容，正文随版本维护）；
/// 拉取失败（离线 / 404 / 超时）回退到内置「本地最新版」并标注回退来源，
/// 保证同意闸门永不因网络问题卡死。返回文本均带更新时间戳供页面展示
/// （「本地内置 · 更新于 …」或「GitHub · 更新于 …」）。
///
/// 纯 Dart，可单测；[client] 可注入（自托管/测试场景）。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// 一份条款文档（正文 + 来源 + 更新时间）。
class TermsDoc {
  const TermsDoc({
    required this.title,
    required this.body,
    required this.source,
    required this.updatedAt,
  });

  final String title;
  final String body;

  /// 来源描述：'GitHub' 或 '本地内置'。
  final String source;

  /// 更新时间（远程文件日期或本地内置日期）。
  final String updatedAt;
}

/// 内置本地最新条款版本日期（与正文同步维护）。
const String kLocalTermsDate = '2026-08-29';

/// 内置本地最新·服务条款（远端拉取失败的兜底，OSS 开源免责）。
const String kLocalTermsBody =
    '星璃音乐为开源（MIT 协议）项目，仅供个人学习与研究使用。'
    '第三方音源（网易云、B 站等）的版权归原平台所有，仅限个人学习使用，'
    '请勿用于商业用途或二次分发。';

/// 内置本地最新·隐私政策（远端拉取失败的兜底，本地优先脱敏）。
const String kLocalPrivacyBody =
    '你的数据仅保存在本机，不会上传。日志默认脱敏，不收集账号密码与具体曲目标题。'
    '我们不会向第三方出售你的数据；跨设备同步由你主动开启（需登录账号）。'
    '你可随时在设置中撤销授权或清除本地数据。';

/// 拉取类型。
enum TermsKind { terms, privacy }

/// 条款在仓库里的文件名。
String termsFileName(TermsKind kind) => switch (kind) {
      TermsKind.terms => 'TERMS.md',
      TermsKind.privacy => 'PRIVACY.md',
    };

/// 拉取条款正文。
///
/// 成功：GitHub 仓库 `docs/` 下的 `TERMS.md` / `PRIVACY.md`；
/// 失败（离线 / 404 / 超时）：返回本地内置文本，来源标注「本地内置」。
Future<TermsDoc> fetchTermsDoc(TermsKind kind, {http.Client? client}) async {
  final String title = switch (kind) {
    TermsKind.terms => '服务条款',
    TermsKind.privacy => '隐私政策',
  };
  final String fallbackBody = switch (kind) {
    TermsKind.terms => kLocalTermsBody,
    TermsKind.privacy => kLocalPrivacyBody,
  };

  final http.Client c = client ?? http.Client();
  try {
    final http.Response resp = await c
        .get(
          Uri.parse(
            'https://raw.githubusercontent.com/WuMengAA/xingli_music/main/docs/${termsFileName(kind)}',
          ),
        )
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
      return TermsDoc(
        title: title,
        body: utf8.decode(resp.bodyBytes).trim(),
        source: 'GitHub',
        updatedAt: kLocalTermsDate, // 远程文件不随请求带日期，用仓库配套日期
      );
    }
  } catch (_) {
    // 网络异常 → 回落本地
  } finally {
    if (client == null) c.close();
  }
  return TermsDoc(
    title: title,
    body: fallbackBody,
    source: '本地内置',
    updatedAt: kLocalTermsDate,
  );
}