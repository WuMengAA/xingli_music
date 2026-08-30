/// ════════════════════════════════════════════════════════════════════════
/// 电台房大厅（社交模块 · 电台核心）：创建 / 加入电台房。
///
/// cl15 重构：电台房间体系——
///   - 创建：公开/私密 + 房间模式（校园广播 100 人 / 一起听 2-10 人）
///           + 房间号（随机 6 位数字 / 自定义中英文数字 ≤16 字符）
///           + 密码（仅字母数字，私密房可选）
///   - 加入：公开房间列表（随机显示 / 排序）+ 私密输房间号 + 密码
///   - 跨公网统一走官方 relay-server 中转（OQ-2 已决），凭房间号加入。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/auth/user_provider.dart';
import '../../providers/net/session_provider.dart';
import '../../services/net/net_node.dart';
import '../../pages/voxel/voxel_lobby_page.dart';
import 'station_room_page.dart';

/// 电台房形态（cl15：校园广播 100 人 / 一起听 2-10 人）。
enum StationMode {
  campusBroadcast(
    label: '校园广播',
    desc: '上限 100 人 · 一起听 + 点歌',
    capacity: 100,
    syncListen: true,
    acceptOrder: true,
  ),
  friendListen(
    label: '一起听',
    desc: '2-10 人 · 一起听 + 可点歌',
    capacity: 10,
    syncListen: true,
    acceptOrder: true,
  );

  const StationMode({
    required this.label,
    required this.desc,
    required this.capacity,
    required this.syncListen,
    required this.acceptOrder,
  });
  final String label;
  final String desc;
  final int capacity; // 默认人数上限
  final bool syncListen;
  final bool acceptOrder;

  /// cl15：对应 relay 后端房间模式。
  String get relayMode => switch (this) {
        StationMode.campusBroadcast => 'campus',
        StationMode.friendListen => 'listen',
      };
}

/// 电台房大厅。
class StationLobbyPage extends ConsumerStatefulWidget {
  const StationLobbyPage({super.key});

  @override
  ConsumerState<StationLobbyPage> createState() => _StationLobbyPageState();
}

class _StationLobbyPageState extends ConsumerState<StationLobbyPage> {
  bool _isHost = true;
  bool _busy = false;
  String? _error;
  StationMode _mode = StationMode.campusBroadcast;

  // 创建：公开/私密 + 房间号（随机/自定义）+ 密码。
  bool _isPublic = true;
  bool _customRoom = false;
  int _listenCapacity = 5; // 一起听人数（2-10）
  String _randomRoomCode = ''; // 预生成的随机 6 位数字房间号
  final TextEditingController _nameCtrl =
      TextEditingController(text: 'DJ');
  final TextEditingController _roomCtrl = TextEditingController();
  final TextEditingController _pwCtrl = TextEditingController();

  // 加入：公开房间列表（可排序/刷新）+ 私密密码。
  List<RadioRoomInfo> _publicRooms = <RadioRoomInfo>[];
  bool _roomsLoading = false;
  bool _roomsDesc = false; // 排序方向（按人数）

  static const String _namePrefsKey = 'station_name';

  /// 登录账号名（登录后统一用账号名，未登录为空）。
  String get _accountName {
    final AuthState a = ref.read(authProvider);
    if (!a.isAuthed) return '';
    final String n = (a.user?.username ?? '').trim();
    return n;
  }

  /// 电台内展示名：登录后优先用账号名（统一），未登录用昵称框填写值。
  String get _displayName {
    final String acc = _accountName;
    if (acc.isNotEmpty) return acc;
    final String typed = _nameCtrl.text.trim();
    return typed.isEmpty ? (_isHost ? 'DJ' : '听众') : typed;
  }

  @override
  void initState() {
    super.initState();
    _randomRoomCode = _randomRoom();
    _loadPrefs();
    _refreshPublicRooms();
  }

  Future<void> _loadPrefs() async {
    // 已登录：直接以账号名作为电台名（统一），无需再读旧昵称。
    if (_accountName.isNotEmpty) {
      if (mounted) setState(() => _nameCtrl.text = _accountName);
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? savedName = prefs.getString(_namePrefsKey);
    if (!mounted) return;
    setState(() {
      if (savedName != null && savedName.isNotEmpty) {
        _nameCtrl.text = savedName;
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roomCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  /// 生成 6 位纯数字随机房间号（首位非 0）。
  String _randomRoom() {
    final math.Random r = math.Random();
    return String.fromCharCodes(Iterable<int>.generate(6, (i) {
      final int d = i == 0 ? 1 + r.nextInt(9) : r.nextInt(10);
      return 0x30 + d;
    }));
  }

  /// 拉取公开房间列表（失败静默为空，UI 显示空态）。
  Future<void> _refreshPublicRooms() async {
    setState(() => _roomsLoading = true);
    final List<RadioRoomInfo> rooms =
        await fetchPublicRooms(kDefaultRelayUrl);
    if (!mounted) return;
    setState(() {
      _publicRooms = rooms;
      _roomsLoading = false;
    });
  }

  Future<void> _go(StationRoomPage page) async {
    // 已登录不写昵称覆盖（账号名为准）；仅游客保存手填昵称。
    if (_accountName.isEmpty) {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      await prefs.setString(_namePrefsKey, _nameCtrl.text.trim());
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    // 返回大厅后刷新公开房间列表（房间可能已变化）。
    if (mounted) _refreshPublicRooms();
  }

  Future<void> _create() async {
    // 房间号：自定义校验（中英文数字，≤16 字符）。
    final String room;
    if (_customRoom) {
      final String custom = _roomCtrl.text.trim();
      if (custom.isEmpty) {
        setState(() => _error = '请输入自定义房间号');
        return;
      }
      if (custom.length > 16) {
        setState(() => _error = '房间号最多 16 个字符');
        return;
      }
      if (!RegExp(r'^[0-9A-Za-z]+$').hasMatch(custom)) {
        setState(() => _error = '房间号仅限中英文与数字');
        return;
      }
      room = custom;
    } else {
      room = _randomRoomCode;
    }
    // 密码：仅字母数字。
    final String pw = _pwCtrl.text.trim();
    if (pw.isNotEmpty && !RegExp(r'^[0-9A-Za-z]+$').hasMatch(pw)) {
      setState(() => _error = '密码仅限英文字母和数字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final int capacity = _mode == StationMode.campusBroadcast
        ? 100
        : _listenCapacity;
    final bool ok = await ref.read(netSessionProvider.notifier).host(
          seed: 0,
          name: _displayName,
          relayUrl: kDefaultRelayUrl,
          room: room,
          isPublic: _isPublic,
          mode: _mode.relayMode,
          capacity: capacity,
          password: pw.isEmpty ? null : pw,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = ref.read(netSessionProvider).error);
      return;
    }
    await _go(StationRoomPage(
      mode: _mode,
      isHost: true,
    ));
  }

  Future<void> _joinByCode([String? presetRoom]) async {
    final String room =
        (presetRoom ?? _roomCtrl.text.trim()).toUpperCase();
    if (room.isEmpty) {
      setState(() => _error = '请输入房间号');
      return;
    }
    final String pw = _pwCtrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = await ref.read(netSessionProvider.notifier).join(
          '',
          0,
          name: _displayName,
          relayUrl: kDefaultRelayUrl,
          room: room,
          password: pw.isEmpty ? null : pw,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = ref.read(netSessionProvider).error);
      return;
    }
    await _go(StationRoomPage(
      mode: _mode,
      isHost: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Scaffold(
      backgroundColor: c.bgPage,
      appBar: AppBar(
        title: const Text('电台房'),
        backgroundColor: c.bgPage,
        foregroundColor: c.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _buildHostJoinToggle(c),
          const SizedBox(height: 16),
          _buildNameField(c),
          const SizedBox(height: 16),
          if (_isHost) ..._buildHostPanel(c) else ..._buildJoinPanel(c),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: c.danger)),
          ],
          const SizedBox(height: 16),
          // cl15：电台 ↔ 联机互入口。
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const VoxelLobbyPage()),
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.public_rounded, color: c.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('体素联机世界',
                            style: TextStyle(
                                color: c.textPrimary,
                                fontWeight: FontWeight.bold)),
                        Text('进入实时体素世界，自由探索与建造',
                            style: TextStyle(
                                color: c.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶端「创建 / 加入」切换。
  Widget _buildHostJoinToggle(AppThemeColors c) => Row(
        children: <Widget>[
          Expanded(
            child: SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('创建电台房')),
                ButtonSegment<bool>(value: false, label: Text('加入电台房')),
              ],
              selected: <bool>{_isHost},
              onSelectionChanged: (s) => setState(() {
                _isHost = s.first;
                _error = null;
              }),
            ),
          ),
        ],
      );

  Widget _buildNameField(AppThemeColors c) {
    final bool locked = _accountName.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _nameCtrl,
          enabled: !locked,
          decoration: InputDecoration(
            labelText: locked ? '电台昵称（登录账号名）' : '你的昵称',
            labelStyle: TextStyle(color: c.textSecondary),
            filled: true,
            fillColor: c.bgCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            suffixIcon: locked ? Icon(Icons.person, color: c.accent) : null,
          ),
          style: TextStyle(color: c.textPrimary),
        ),
        if (locked) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '已登录，电台内统一使用账号名「$_accountName」',
            style: TextStyle(color: c.accent, fontSize: 12),
          ),
        ],
      ],
    );
  }

  // ── 创建面板 ────────────────────────────────────────────────
  List<Widget> _buildHostPanel(AppThemeColors c) => <Widget>[
        _buildPublicToggle(c),
        const SizedBox(height: 16),
        _buildModeSelector(c),
        const SizedBox(height: 16),
        _buildRoomField(c),
        const SizedBox(height: 16),
        if (!_isPublic) ...<Widget>[
          _buildPasswordField(c),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.radio),
          label: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('创建电台房'),
        ),
        const SizedBox(height: 8),
        Text(
          _isPublic
              ? '公开房间会显示在大厅列表，好友凭房间号或直接点加入即可进入。'
              : '私密房间不会出现在列表，需凭房间号 + 密码加入。',
          style: TextStyle(color: c.textSecondary, fontSize: 12),
        ),
      ];

  Widget _buildPublicToggle(AppThemeColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('房间可见性', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: true, label: Text('公开')),
              ButtonSegment<bool>(value: false, label: Text('私密')),
            ],
            selected: <bool>{_isPublic},
            onSelectionChanged: (s) => setState(() => _isPublic = s.first),
          ),
        ],
      );

  Widget _buildModeSelector(AppThemeColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('房间模式', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          ...StationMode.values.map((m) => _ModeTile(
                c: c,
                mode: m,
                selected: _mode == m,
                onTap: () => setState(() => _mode = m),
              )),
          // 一起听：可选人数 2-10。
          if (_mode == StationMode.friendListen) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text('人数上限：$_listenCapacity 人',
                    style: TextStyle(color: c.textPrimary)),
                Expanded(
                  child: Slider(
                    value: _listenCapacity.toDouble(),
                    min: 2,
                    max: 10,
                    divisions: 8,
                    label: '$_listenCapacity 人',
                    onChanged: (double v) =>
                        setState(() => _listenCapacity = v.round()),
                  ),
                ),
              ],
            ),
          ],
        ],
      );

  Widget _buildRoomField(AppThemeColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('房间号', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: false, label: Text('随机 6 位数字')),
              ButtonSegment<bool>(value: true, label: Text('自定义')),
            ],
            selected: <bool>{_customRoom},
            onSelectionChanged: (s) => setState(() {
              _customRoom = s.first;
              _roomCtrl.clear();
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _roomCtrl,
            enabled: _customRoom,
            textCapitalization: TextCapitalization.characters,
            maxLength: 16,
            decoration: InputDecoration(
              labelText: _customRoom ? '自定义房间号' : '随机 6 位数字房间号',
              hintText: _customRoom ? '如 Music24 / 888888' : '将自动生成',
              helperText: '中英文数字，最多 16 个字符',
              labelStyle: TextStyle(color: c.textSecondary),
              filled: true,
              fillColor: c.bgCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: !_customRoom
                  ? IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: '换一个',
                      onPressed: () =>
                          setState(() => _randomRoomCode = _randomRoom()),
                    )
                  : null,
            ),
            style: TextStyle(color: c.textPrimary, letterSpacing: 2),
          ),
          if (!_customRoom)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('本房号：$_randomRoomCode',
                  style: TextStyle(color: c.accent, fontSize: 12)),
            ),
        ],
      );

  Widget _buildPasswordField(AppThemeColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('房间密码（可选）',
              style: TextStyle(color: c.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _pwCtrl,
            obscureText: true,
            maxLength: 16,
            decoration: InputDecoration(
              hintText: '仅英文字母和数字',
              labelStyle: TextStyle(color: c.textSecondary),
              filled: true,
              fillColor: c.bgCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: TextStyle(color: c.textPrimary),
          ),
        ],
      );

  // ── 加入面板 ────────────────────────────────────────────────
  List<Widget> _buildJoinPanel(AppThemeColors c) => <Widget>[
        _buildPublicRoomList(c),
        const SizedBox(height: 16),
        Text('凭房间号加入', style: TextStyle(color: c.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _roomCtrl,
          textCapitalization: TextCapitalization.characters,
          maxLength: 16,
          decoration: InputDecoration(
            labelText: '房间号',
            hintText: '输入 6 位数字或自定义房间号',
            labelStyle: TextStyle(color: c.textSecondary),
            filled: true,
            fillColor: c.bgCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          style: TextStyle(color: c.textPrimary, letterSpacing: 2),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _pwCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: '密码（私密房间需要）',
            hintText: '仅英文字母和数字',
            labelStyle: TextStyle(color: c.textSecondary),
            filled: true,
            fillColor: c.bgCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          style: TextStyle(color: c.textPrimary),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : () => _joinByCode(),
          icon: const Icon(Icons.login),
          label: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('加入电台房'),
        ),
      ];

  /// 公开房间列表（可排序 / 刷新）。
  Widget _buildPublicRoomList(AppThemeColors c) {
    final List<RadioRoomInfo> rooms = List<RadioRoomInfo>.of(_publicRooms);
    rooms.sort((a, b) => _roomsDesc
        ? b.members.compareTo(a.members)
        : a.members.compareTo(b.members));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('公开房间（${rooms.length}）',
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.sort, size: 18),
              tooltip: '按人数${_roomsDesc ? '升序' : '降序'}',
              onPressed: () => setState(() => _roomsDesc = !_roomsDesc),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: '刷新',
              onPressed: _refreshPublicRooms,
            ),
          ],
        ),
        if (_roomsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (rooms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('暂无公开房间，快去创建一间吧！',
                style: TextStyle(color: c.textSecondary, fontSize: 12)),
          )
        else ...<Widget>[
          ...rooms.map((r) => _PublicRoomTile(
                c: c,
                room: r,
                onJoin: () => _joinByCode(r.code),
              )),
        ],
      ],
    );
  }
}

/// 模式选择卡片。
class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.c,
    required this.mode,
    required this.selected,
    required this.onTap,
  });
  final AppThemeColors c;
  final StationMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? c.accent.withValues(alpha: 0.15) : c.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? c.accent : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                mode == StationMode.campusBroadcast
                    ? Icons.campaign
                    : Icons.headphones,
                color: selected ? c.accent : c.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(mode.label,
                        style: TextStyle(
                            color: c.textPrimary, fontWeight: FontWeight.bold)),
                    Text(mode.desc,
                        style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: c.accent),
            ],
          ),
        ),
      );
}

/// 公开房间条目。
class _PublicRoomTile extends StatelessWidget {
  const _PublicRoomTile({
    required this.c,
    required this.room,
    required this.onJoin,
  });
  final AppThemeColors c;
  final RadioRoomInfo room;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              room.isCampus ? Icons.campaign : Icons.headphones,
              color: c.accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(room.code,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5)),
                  Text(
                    '${room.modeLabel} · ${room.members}/${room.capacity} 人 · ${room.name}',
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (room.members < room.capacity)
              TextButton(onPressed: onJoin, child: const Text('加入'))
            else
              Text('已满',
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
          ],
        ),
      );
}
