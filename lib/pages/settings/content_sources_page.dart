import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/capability.dart';
import '../../providers/content/capability_providers.dart';

/// 内容来源：按能力清单渲染开关，让用户自己决定内容层要什么。
///
/// 与「音源设置」的分工必须分清，否则两个页面都会变得含混：
/// - **音源设置**管*连接*——服务器地址、本地目录、账号凭据，即「怎么连上」。
/// - **本页**管*取舍*——连上之后要哪些内容，即「拿什么」。
///
/// 清单主体来自服务端 `/api/capabilities`，所以服务端以后新增能力会自动出现
/// 在这里且默认启用，用户再自行裁剪，不必等客户端发版。
class ContentSourcesPage extends ConsumerWidget {
  const ContentSourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;

    // 刻意用**未应用选配**的原始清单：本页要区分「能力本身不可用」与
    // 「用户主动关掉」——前者开关必须置灰（点了也不会生效），后者才可切换。
    // 若直接用 capabilitiesProvider，两者都被压成 enabled=false，无法区分。
    final List<Capability> caps = <Capability>[
      ...ref.watch(localCapabilitiesProvider),
      ...(ref.watch(capabilityManifestProvider).valueOrNull?.capabilities ??
          const <Capability>[]),
    ];
    final Set<String> off = ref.watch(capabilitySelectionProvider);
    final bool fromCache = ref.watch(capabilitiesFromCacheProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('内容来源')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: <Widget>[
          if (fromCache) ...<Widget>[
            _Hint(
              icon: Icons.cloud_off_rounded,
              text: '当前显示的是离线缓存的清单，联网后会自动更新。',
              color: c.warning,
            ),
            const SizedBox(height: AppSpace.md),
          ],
          for (final _CapGroup g in _group(caps))
            _Section(
              title: g.title,
              capabilities: g.items,
              off: off,
            ),
          const SizedBox(height: AppSpace.lg),
        ],
      ),
    );
  }
}

/// 按来源分组后的一个区块。
class _CapGroup {
  const _CapGroup(this.title, this.items);

  final String title;
  final List<Capability> items;
}

/// 分组展示顺序固定：本机 → 服务端内容 → 网易云 → 其他。
///
/// 本机能力排最前，是因为它们不依赖网络、任何时候都可用；服务端内容居中；
/// 需要登录的第三方排在后面。
List<_CapGroup> _group(List<Capability> caps) {
  final List<_CapGroup> out = <_CapGroup>[];

  void add(String title, String source) {
    final List<Capability> items =
        caps.where((Capability c) => c.source == source).toList(growable: false);
    if (items.isNotEmpty) out.add(_CapGroup(title, items));
  }

  add('本机', 'local');
  add('服务端内容', 'content');
  add('网易云', 'netease');
  // B站与网易云不同：搜索本身**不需要登录**（2026-08-29 实测 WBI 搜索免登录
  // 即可返回数据），登录影响的是播放音质（带 cookie 才拿得到高码率音频流）。
  // 所以这里不写「需登录」，避免用户以为不登录就完全用不了。
  add('哔哩哔哩', 'bilibili');

  // 服务端以后可能下发上面没列出的新来源，不能让它们静默消失。
  final Set<String> known = <String>{'local', 'content', 'netease', 'bilibili'};
  final List<Capability> rest =
      caps.where((Capability c) => !known.contains(c.source)).toList(
            growable: false,
          );
  if (rest.isNotEmpty) {
    out.add(_CapGroup('其他', rest));
  }
  return out;
}

/// 一个分组区块。
class _Section extends ConsumerWidget {
  const _Section({
    required this.title,
    required this.capabilities,
    required this.off,
  });

  final String title;
  final List<Capability> capabilities;
  final Set<String> off;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: context.appText.subtitle),
          const SizedBox(height: AppSpace.sm),
          for (final Capability cap in capabilities)
            _CapabilityTile(cap: cap, on: !off.contains(cap.id)),
          Divider(color: c.border),
        ],
      ),
    );
  }
}

/// 单条能力的开关。
class _CapabilityTile extends ConsumerWidget {
  const _CapabilityTile({required this.cap, required this.on});

  final Capability cap;

  /// 用户的选配（默认开）。注意与 [Capability.enabled] 是两回事。
  final bool on;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // enabled=false 有两种成因，必须分开处理：
    //  - 能力本身不可用（没配本地目录 / 服务端没开放）→ 开关置灰，点了也没用；
    //  - 能力可用但服务端只登记未实现（planned）→ 同样置灰，但文案说明是有这条路。
    final bool usable = cap.enabled;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(cap.title),
      value: usable && on,
      onChanged: usable
          ? (bool v) =>
              ref.read(capabilitySelectionProvider.notifier).setOn(cap.id, v)
          : null,
    );
  }
}

/// 一行提示。
class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(text, style: context.appText.artist)),
      ],
    );
  }
}
