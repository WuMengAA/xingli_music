/// ════════════════════════════════════════════════════════════════════════
/// 开放世界 · 联机大厅（G9）：创建房间 / 加入房间 / 局域网发现。
///
/// 拓扑：主机-客户端（任何人可当主机，即用户理解的 P2P）。地形按 seed 确定性
/// 重现，故只同步方块编辑 + 玩家变换 + 一起听。大厅只负责**建连**，
/// 成功即把 (seed, options) 透传给 [VoxelWorld3DPage(multiplayer: true)]。
///
/// 传输：零依赖 —— WebSocket（dart:io）传输 + UDP（dart:io RawDatagramSocket）
/// 局域网发现，无任何第三方网络库。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/net/session_provider.dart';
import '../../services/net/lan_discovery.dart';
import '../../services/net/net_node.dart';
import '../../widgets/voxel/voxel_world.dart';
import '../../widgets/voxel/voxel_world_view3d.dart';

/// 开放世界联机大厅。
class VoxelLobbyPage extends ConsumerStatefulWidget {
  const VoxelLobbyPage({super.key});

  @override
  ConsumerState<VoxelLobbyPage> createState() => _VoxelLobbyPageState();
}

class _VoxelLobbyPageState extends ConsumerState<VoxelLobbyPage> {
  bool _isHost = true;
  bool _busy = false;
  String? _error;

  final TextEditingController _nameCtrl = TextEditingController(text: '玩家');
  final TextEditingController _seedCtrl = TextEditingController();
  final TextEditingController _ipCtrl = TextEditingController();
  final TextEditingController _portCtrl =
      TextEditingController(text: kNetDefaultPort.toString());

  bool _cheats = false;
  bool _structures = true;
  bool _floatingIslands = false;
  bool _survival = false;

  bool _scanning = false;
  List<LanHost> _scanHosts = <LanHost>[];
  StreamSubscription<LanHost>? _scanSub;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _seedCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _scanSub?.cancel();
    super.dispose();
  }

  int _randomSeed() => math.Random().nextInt(1 << 30);

  Future<void> _startHost() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final String name =
        _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim();
    final int seed = _seedCtrl.text.trim().isEmpty
        ? _randomSeed()
        : (int.tryParse(_seedCtrl.text.trim()) ?? _randomSeed());
    final WorldOptions opts = WorldOptions(
      cheats: _cheats,
      structures: _structures,
      floatingIslands: _floatingIslands,
    );
    final bool ok = await ref
        .read(netSessionProvider.notifier)
        .host(seed: seed, options: opts.toJson(), name: name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() =>
          _error = ref.read(netSessionProvider).error ?? '创建房间失败');
      return;
    }
    _enterWorld(seed, opts);
  }

  Future<void> _join({LanHost? host}) async {
    if (_busy) return;
    final String ip = host?.ip ?? _ipCtrl.text.trim();
    final int port =
        host?.port ?? (int.tryParse(_portCtrl.text.trim()) ?? kNetDefaultPort);
    if (ip.isEmpty) {
      setState(() => _error = '请输入房主 IP');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final String name =
        _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim();
    final bool ok = await ref
        .read(netSessionProvider.notifier)
        .join(ip, port, name: name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = ref.read(netSessionProvider).error ?? '连接失败');
      return;
    }
    // 客户端：world seed / options 由主机 welcome 消息下发，二者必须一致。
    final int seed =
        ref.read(netSessionProvider).hostSeed ?? VoxelWorld.defaultSeed;
    final WorldOptions opts =
        WorldOptions.fromJson(ref.read(netSessionProvider).hostOptions);
    _enterWorld(seed, opts);
  }

  void _enterWorld(int seed, WorldOptions opts) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VoxelWorld3DPage(
        multiplayer: true,
        seed: seed,
        options: opts,
        survival: _survival,
        autoStart: true,
      ),
    ));
  }

  Future<void> _scanLan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanHosts = <LanHost>[];
      _error = null;
    });
    _scanSub?.cancel();
    final Stream<LanHost> stream = await LanDiscovery.scan();
    _scanSub = stream.listen(
      (LanHost h) =>
          setState(() => _scanHosts = <LanHost>[..._scanHosts, h]),
      onDone: () => setState(() => _scanning = false),
      onError: (_) => setState(() => _scanning = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color ink = Color(0xFFF2F5FA);
    final Color accent = context.appColors.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // 顶栏：返回 + 标题。
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: ink),
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Text('开放世界 · 联机',
                      style: AppTextStyles.title.copyWith(color: ink)),
                ],
              ),
            ),
            // 模式切换：创建 / 加入。
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: true, label: Text('创建房间')),
                  ButtonSegment<bool>(value: false, label: Text('加入房间')),
                ],
                selected: <bool>{_isHost},
                onSelectionChanged: (Set<bool> s) =>
                    setState(() => _isHost = s.first),
                style: SegmentedButton.styleFrom(
                  selectedForegroundColor: ink,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.md),
                children: <Widget>[
                  _Field(
                    label: '昵称',
                    controller: _nameCtrl,
                    hint: '玩家',
                  ),
                  const SizedBox(height: AppSpace.sm),
                  if (_isHost) ..._hostFields(accent, ink),
                  if (!_isHost) ..._joinFields(accent, ink),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      _error!,
                      style: AppTextStyles.body
                          .copyWith(color: const Color(0xFFFF8A8A)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _hostFields(Color accent, Color ink) => <Widget>[
        _Field(
          label: '世界种子（留空随机）',
          controller: _seedCtrl,
          hint: '数字',
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: AppSpace.sm),
        _SwitchRow(
          label: '作弊（创造）',
          value: _cheats,
          onChanged: (bool v) => setState(() => _cheats = v),
        ),
        _SwitchRow(
          label: '生成结构',
          value: _structures,
          onChanged: (bool v) => setState(() => _structures = v),
        ),
        _SwitchRow(
          label: '浮空岛',
          value: _floatingIslands,
          onChanged: (bool v) => setState(() => _floatingIslands = v),
        ),
        _SwitchRow(
          label: '生存模式',
          value: _survival,
          onChanged: (bool v) => setState(() => _survival = v),
        ),
        const SizedBox(height: AppSpace.md),
        _PrimaryButton(
          label: _busy ? '创建中…' : '创建并开始',
          accent: accent,
          ink: ink,
          busy: _busy,
          onTap: _startHost,
        ),
      ];

  List<Widget> _joinFields(Color accent, Color ink) => <Widget>[
        _Field(
          label: '房主 IP',
          controller: _ipCtrl,
          hint: '如 192.168.1.5',
        ),
        const SizedBox(height: AppSpace.sm),
        _Field(
          label: '端口',
          controller: _portCtrl,
          hint: kNetDefaultPort.toString(),
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: AppSpace.md),
        _PrimaryButton(
          label: _busy ? '连接中…' : '加入房间',
          accent: accent,
          ink: ink,
          busy: _busy,
          onTap: () => _join(),
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: <Widget>[
            Expanded(
              child: Text('局域网房间',
                  style: AppTextStyles.body.copyWith(color: ink)),
            ),
            TextButton(
              onPressed: _scanning ? null : _scanLan,
              child: Text(_scanning ? '扫描中…' : '扫描局域网'),
            ),
          ],
        ),
        if (_scanHosts.isNotEmpty)
          ..._scanHosts.map((LanHost h) => _HostCard(
                host: h,
                ink: ink,
                onTap: () => _join(host: h),
              )),
      ];
}

/// 文本输入行。
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboard,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label, style: AppTextStyles.body.copyWith(color: Colors.white70)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0x1AFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      );
}

/// 开关行。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label,
                  style: AppTextStyles.body.copyWith(color: Colors.white70)),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      );
}

/// 主操作按钮。
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    required this.accent,
    required this.ink,
    this.busy = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color accent;
  final Color ink;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: ElevatedButton(
          onPressed: busy ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Text(label),
        ),
      );
}

/// 局域网主机卡。
class _HostCard extends StatelessWidget {
  const _HostCard({
    required this.host,
    required this.onTap,
    required this.ink,
  });

  final LanHost host;
  final VoidCallback onTap;
  final Color ink;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Material(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.wifi_rounded,
                      size: 20, color: Colors.white70),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(host.name,
                            style: AppTextStyles.body.copyWith(color: ink)),
                        Text('${host.ip}:${host.port}',
                            style: AppTextStyles.caption
                                .copyWith(color: Colors.white54)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white54),
                ],
              ),
            ),
          ),
        ),
      );
}
