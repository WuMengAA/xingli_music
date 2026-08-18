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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/net/session_provider.dart';
import '../../services/net/lan_discovery.dart';
import '../../services/net/net_node.dart';
import '../../widgets/voxel/voxel_world.dart';
import '../../widgets/voxel/voxel_world_view3d.dart';
import '../../widgets/voxel/voxel_save.dart';
import 'relay_input_validation.dart';

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

  /// 连接方式：false=局域网（UDP 发现 + IP 直连），true=中转服务器（跨公网，凭房间号加入）。
  bool _useRelay = false;
  final TextEditingController _relayCtrl = TextEditingController();
  final TextEditingController _roomCtrl = TextEditingController();
  static const String _relayUrlPrefsKey = 'relay_url';

  // cl-A（一起听解耦 + 主持载存档作共享世界）：
  // 建房/进房成功后不再强制进 3D 世界，停在「房间就绪」面板，
  // 用户可手动「进入世界」或仅一起听；主持可选本地存档作共享世界。
  bool _useHostSave = false;
  String? _hostSaveId;
  List<VoxelManualSaveMeta> _saves = <VoxelManualSaveMeta>[];
  int? _pendingSeed;
  WorldOptions? _pendingOpts;
  Map<String, dynamic>? _pendingSaveData;

  @override
  void initState() {
    super.initState();
    _loadRelayUrl();
    _loadSaves();
  }

  /// 载入本地手动存档列表，供主持「使用本地存档作共享世界」选择。
  Future<void> _loadSaves() async {
    final List<VoxelManualSaveMeta> s = await listManualSaves();
    if (mounted) setState(() => _saves = s);
  }

  /// 加载记忆的中转地址（无则用内置默认，保证普通用户免填）。
  Future<void> _loadRelayUrl() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString(_relayUrlPrefsKey);
    if (!mounted) return;
    setState(() {
      _relayCtrl.text =
          (saved == null || saved.isEmpty) ? kDefaultRelayUrl : saved;
    });
  }

  /// 中转地址变更即记忆，下次打开免填。
  Future<void> _saveRelayUrl(String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_relayUrlPrefsKey, value.trim());
  }

  /// 中转地址取值：为空时回退内置默认，保证「一键建房」不因空地址失败。
  String get _effectiveRelayUrl {
    final String t = _relayCtrl.text.trim();
    return t.isEmpty ? kDefaultRelayUrl : t;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _seedCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _scanSub?.cancel();
    _relayCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  int _randomSeed() => math.Random().nextInt(1 << 30);

  Future<void> _startHost() async {
    if (_busy) return;
    // cl79：中转模式前置校验（说人话，不等服务器报英文错）。
    if (_useRelay) {
      final String? relayErr = validateRelayInput(
        _effectiveRelayUrl,
        _roomCtrl.text,
        isHost: true,
      );
      if (relayErr != null) {
        setState(() => _error = relayErr);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final String name =
        _nameCtrl.text.trim().isEmpty ? '玩家' : _nameCtrl.text.trim();

    // 主持：若选了本地存档，则用它作共享世界（seed/选项/已有地形编辑）。
    int seed;
    WorldOptions opts;
    Map<String, dynamic>? saveData;
    if (_useHostSave && _hostSaveId != null) {
      final Map<String, dynamic>? data = await readManualSave(_hostSaveId!);
      if (data != null) {
        final dynamic w = data['world'];
        seed = (w is Map && w['seed'] is int) ? w['seed'] as int : _randomSeed();
        opts = (w is Map && w['options'] is Map)
            ? WorldOptions.fromJson(w['options'] as Map<String, dynamic>)
            : WorldOptions(
                cheats: _cheats,
                structures: _structures,
                floatingIslands: _floatingIslands,
              );
        saveData = data;
      } else {
        // 存档丢失：回落表单种子。
        seed = _seedCtrl.text.trim().isEmpty
            ? _randomSeed()
            : (int.tryParse(_seedCtrl.text.trim()) ?? _randomSeed());
        opts = WorldOptions(
          cheats: _cheats,
          structures: _structures,
          floatingIslands: _floatingIslands,
        );
      }
    } else {
      seed = _seedCtrl.text.trim().isEmpty
          ? _randomSeed()
          : (int.tryParse(_seedCtrl.text.trim()) ?? _randomSeed());
      opts = WorldOptions(
        cheats: _cheats,
        structures: _structures,
        floatingIslands: _floatingIslands,
      );
    }

    final String? relayUrl = _useRelay ? _effectiveRelayUrl : null;
    final String? room =
        _useRelay ? _roomCtrl.text.trim().toUpperCase() : null;
    final bool ok = await ref
        .read(netSessionProvider.notifier)
        .host(
          seed: seed,
          options: opts.toJson(),
          name: name,
          relayUrl: relayUrl,
          room: room,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      // cl79：relay 英文错误（room required / room full）映射中文人话。
      final String raw =
          ref.read(netSessionProvider).error ?? '创建房间失败';
      setState(() => _error = mapRelayErrorText(raw) ?? raw);
      return;
    }
    // cl-A：不再强制进世界，停在房间面板，用户可手动进或仅一起听。
    _pendingSeed = seed;
    _pendingOpts = opts;
    _pendingSaveData = saveData;
    if (_useRelay) {
      final String code = ref.read(netSessionProvider).roomCode ?? '';
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('房间已创建，房间号：$code（已复制，发给好友）'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _join({LanHost? host}) async {
    if (_busy) return;
    // cl79：中转模式前置校验（说人话，不等服务器报英文错）。
    if (_useRelay) {
      final String? relayErr = validateRelayInput(
        _effectiveRelayUrl,
        _roomCtrl.text,
        isHost: false,
      );
      if (relayErr != null) {
        setState(() => _error = relayErr);
        return;
      }
    }
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
    final String? relayUrl = _useRelay ? _effectiveRelayUrl : null;
    final String? room =
        _useRelay ? _roomCtrl.text.trim().toUpperCase() : null;
    final bool ok = await ref
        .read(netSessionProvider.notifier)
        .join(ip, port, name: name, relayUrl: relayUrl, room: room);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      // cl79：relay 英文错误（room required / room full）映射中文人话。
      final String raw = ref.read(netSessionProvider).error ?? '连接失败';
      setState(() => _error = mapRelayErrorText(raw) ?? raw);
      return;
    }
    // 客户端：world seed / options 由主机 welcome 消息下发，二者必须一致。
    // cl-A：不进世界，存待用户手动进入（地形靠 seed 重生，编辑层联机同步）。
    _pendingSeed =
        ref.read(netSessionProvider).hostSeed ?? VoxelWorld.defaultSeed;
    _pendingOpts =
        WorldOptions.fromJson(ref.read(netSessionProvider).hostOptions);
    _pendingSaveData = null;
  }

  /// cl-A：手动进入 3D 世界（建房/进房成功后才可点；一起听不依赖它）。
  void _enterWorld() {
    if (_pendingSeed == null || _pendingOpts == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VoxelWorld3DPage(
        multiplayer: true,
        seed: _pendingSeed!,
        options: _pendingOpts!,
        survival: _survival,
        autoStart: true,
        initialSaveData: _pendingSaveData,
      ),
    ));
  }

  /// cl-A：离开房间（断开联机，回到建房/进房表单）。
  Future<void> _leaveRoom() async {
    await ref.read(netSessionProvider.notifier).leave();
    if (!mounted) return;
    setState(() {
      _pendingSeed = null;
      _pendingOpts = null;
      _pendingSaveData = null;
      _hostSaveId = null;
      _useHostSave = false;
      _error = null;
    });
  }

  /// cl-A：房间就绪面板——建房/进房成功后展示。可手动「进入世界」，
  /// 也可不进游戏、仅通过一起听同步音乐。
  Widget _roomPanel(NetSessionState sess, Color accent, Color ink) {
    final String code = sess.roomCode ?? '';
    final int members = sess.peers.length + 1;
    return ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: <Widget>[
        Text('房间已就绪',
            style: AppTextStyles.title.copyWith(color: ink)),
        const SizedBox(height: AppSpace.sm),
        if (code.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text('房间号：$code（已复制）',
                      style: AppTextStyles.body.copyWith(color: ink)),
                ),
                TextButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: code)),
                  child: const Text('复制'),
                ),
              ],
            ),
          ),
        Text('成员：$members 人',
            style: AppTextStyles.body.copyWith(color: Colors.white70)),
        const SizedBox(height: AppSpace.sm),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            '一起听已自动开启：好友进房后会同步你正在播放的音乐，无需进入世界也能一起听。',
            style: AppTextStyles.caption.copyWith(color: Colors.white70),
          ),
        ),
        if (sess.status == ConnStatus.reconnecting) ...<Widget>[
          const SizedBox(height: AppSpace.sm),
          Text('正在重连…（第 ${sess.reconnectAttempt} 次）',
              style: AppTextStyles.body.copyWith(color: Colors.white54)),
        ],
        const SizedBox(height: AppSpace.md),
        SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: _enterWorld,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: const Text('进入世界'),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        TextButton(
          onPressed: () => _leaveRoom(),
          child: const Text('离开房间'),
        ),
      ],
    );
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
    final NetSessionState sess = ref.watch(netSessionProvider);
    final bool inRoom = sess.status == ConnStatus.connected ||
        sess.status == ConnStatus.reconnecting;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: ink),
                    tooltip: inRoom ? '离开房间' : '返回',
                    onPressed: inRoom
                        ? () => _leaveRoom()
                        : () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Text(inRoom ? '联机房间' : '开放世界 · 联机',
                      style: AppTextStyles.title.copyWith(color: ink)),
                ],
              ),
            ),
            if (inRoom)
              Expanded(child: _roomPanel(sess, accent, ink))
            else ...<Widget>[
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
              // 连接方式切换：局域网 / 中转服务器（跨公网）。
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(value: false, label: Text('局域网')),
                    ButtonSegment<bool>(value: true, label: Text('中转服务器')),
                  ],
                  selected: <bool>{_useRelay},
                  onSelectionChanged: (Set<bool> s) =>
                      setState(() => _useRelay = s.first),
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
          ],
        ),
      ),
    );
  }

  List<Widget> _hostFields(Color accent, Color ink) => <Widget>[
        if (_useRelay) ..._relayFields(ink, true),
        _SwitchRow(
          label: '使用本地存档作共享世界',
          value: _useHostSave,
          onChanged: (bool v) => setState(() => _useHostSave = v),
        ),
        if (_useHostSave) ..._hostSavePicker(ink),
        if (!_useHostSave) ...<Widget>[
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
            // cl05：非作弊（创造）下不允许生存，禁用切换。
            enabled: _cheats,
            onChanged: (bool v) => setState(() => _survival = v),
          ),
        ] else ...<Widget>[
          // 用存档时：地形与生成选项由存档决定，仅保留「生存模式」影响进入后玩法。
          _SwitchRow(
            label: '生存模式',
            value: _survival,
            onChanged: (bool v) => setState(() => _survival = v),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        _PrimaryButton(
          label: _busy ? '创建中…' : '创建房间',
          accent: accent,
          ink: ink,
          busy: _busy,
          onTap: _startHost,
        ),
      ];

  /// 主持：本地存档选择（下拉）。无存档时提示先去游戏内保存。
  List<Widget> _hostSavePicker(Color ink) {
    if (_saves.isEmpty) {
      return <Widget>[
        Text('暂无本地存档，请先在游戏中保存世界',
            style: AppTextStyles.body.copyWith(color: Colors.white54)),
        const SizedBox(height: AppSpace.sm),
      ];
    }
    final VoxelManualSaveMeta? sel = _saves
        .where((VoxelManualSaveMeta s) => s.id == _hostSaveId)
        .isEmpty
        ? null
        : _saves.firstWhere((VoxelManualSaveMeta s) => s.id == _hostSaveId);
    return <Widget>[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: sel?.id,
            dropdownColor: const Color(0xFF16203A),
            hint: Text('选择本地存档',
                style: AppTextStyles.body.copyWith(color: Colors.white54)),
            isExpanded: true,
            items: _saves
                .map((VoxelManualSaveMeta s) => DropdownMenuItem<String>(
                      value: s.id,
                      child: Text(
                        s.lastSavedAt != null
                            ? '${s.name}（${_fmt(s.lastSavedAt!)}）'
                            : s.name,
                        style: AppTextStyles.body.copyWith(color: Colors.white),
                      ),
                    ))
                .toList(),
            onChanged: (String? v) => setState(() => _hostSaveId = v),
          ),
        ),
      ),
      const SizedBox(height: AppSpace.sm),
    ];
  }

  static String _fmt(DateTime d) =>
      '${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  List<Widget> _joinFields(Color accent, Color ink) => <Widget>[
        if (_useRelay)
          ...<Widget>[
            ..._relayFields(ink, false),
            const SizedBox(height: AppSpace.md),
            _PrimaryButton(
              label: _busy ? '连接中…' : '加入房间',
              accent: accent,
              ink: ink,
              busy: _busy,
              onTap: () => _join(),
            ),
          ]
        else ...<Widget>[
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
        ],
      ];

  /// 中转模式共用字段：房间号 + 高级设置（中转地址，默认折叠免打扰）。
  List<Widget> _relayFields(Color ink, bool isHost) => <Widget>[
        _Field(
          label: isHost ? '房间号（留空随机生成）' : '房间号（好友提供）',
          controller: _roomCtrl,
          hint: '如 ABC234',
        ),
        const SizedBox(height: AppSpace.sm),
        _ExpansionSetting(
          ink: ink,
          title: '高级设置：中转服务器地址（一般不用改）',
          child: _Field(
            label: '中转服务器地址',
            controller: _relayCtrl,
            hint: '如 ws://192.168.1.248:8765/ws',
            onChanged: _saveRelayUrl,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
      ];
}

/// 可折叠设置项（默认收起，普通用户无需展开）。
class _ExpansionSetting extends StatelessWidget {
  const _ExpansionSetting({
    required this.title,
    required this.child,
    required this.ink,
  });

  final String title;
  final Widget child;
  final Color ink;

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white54),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(vertical: 2),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text(title,
              style: AppTextStyles.body.copyWith(
                  color: Colors.white54, fontSize: 13)),
          children: <Widget>[child],
        ),
      );
}

/// 文本输入行。
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboard,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label, style: AppTextStyles.body.copyWith(color: Colors.white70)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            onChanged: onChanged,
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
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// cl05：禁用态（如非作弊下不允许生存）。
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label,
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white70,
                  )),
            ),
            Switch(value: value, onChanged: enabled ? onChanged : null),
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
