/// ════════════════════════════════════════════════════════════════════════
/// 电台房大厅（社交模块 · 电台核心）：创建 / 加入电台房。
///
/// 以「电台 Radio Station」为核心抽象（PRD_电台核心.md）：
/// - v1 默认创建者即 DJ（OQ-1 已决）。
/// - 形态矩阵 [StationMode] 对应 RoomCaps{syncListen, acceptOrder}：
///   校园广播台(一起听+点歌) / 好友一起听(一起听) / 纯点歌台(点歌)。
/// - 跨公网统一走**官方 relay-server 中转**（OQ-2 已决），凭房间号加入。
///
/// 2026-08-27（用户决策：官方自己代理中转，无需用户配置，即开即用）：
/// - 移除「中转服务器地址」手动输入框 + 「中转服务器 / 局域网」切换；
/// - 用户只填昵称、选形态，点「创建」/「加入」即开即用；
/// - 中转地址统一取 [kDefaultRelayUrl]（官方公网），用户不可见、不可改。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/net/session_provider.dart';
import '../../services/net/net_node.dart';
import 'station_room_page.dart';

/// 电台房形态（RoomCaps 矩阵）：决定该房是否支持一起听 / 是否接受点歌。
enum StationMode {
  campusBroadcast(
    label: '校园广播台',
    desc: '一起听 + 点歌队列',
    syncListen: true,
    acceptOrder: true,
  ),
  friendListen(
    label: '好友一起听',
    desc: '一起听 + 可点歌',
    syncListen: true,
    acceptOrder: true,
  ),
  orderOnly(
    label: '纯点歌台',
    desc: '仅接受点歌，不同步播放',
    syncListen: false,
    acceptOrder: true,
  );

  const StationMode({
    required this.label,
    required this.desc,
    required this.syncListen,
    required this.acceptOrder,
  });
  final String label;
  final String desc;
  final bool syncListen;
  final bool acceptOrder;
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

  final TextEditingController _nameCtrl =
      TextEditingController(text: 'DJ');
  final TextEditingController _roomCtrl = TextEditingController();

  static const String _namePrefsKey = 'station_name';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
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
    super.dispose();
  }

  Future<void> _go(StationRoomPage page) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_namePrefsKey, _nameCtrl.text.trim());
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = await ref.read(netSessionProvider.notifier).host(
          seed: 0,
          name: _nameCtrl.text.trim().isEmpty ? 'DJ' : _nameCtrl.text.trim(),
          // 官方中转（即开即用），不再暴露地址输入框。
          relayUrl: kDefaultRelayUrl,
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

  Future<void> _join() async {
    final String room = _roomCtrl.text.trim().toUpperCase();
    if (room.isEmpty) {
      setState(() => _error = '请输入房间号');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = await ref.read(netSessionProvider.notifier).join(
          '',
          0,
          name: _nameCtrl.text.trim().isEmpty ? '听众' : _nameCtrl.text.trim(),
          relayUrl: kDefaultRelayUrl,
          room: room,
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
          _buildModeSelector(c),
          const SizedBox(height: 16),
          if (_isHost) ..._buildHostPanel(c) else ..._buildJoinPanel(c),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: c.danger)),
          ],
        ],
      ),
    );
  }

  /// 顶端「创建 / 加入」切换（即开即用：两种动作都无需配置中转）。
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

  Widget _buildNameField(AppThemeColors c) => TextField(
        controller: _nameCtrl,
        decoration: InputDecoration(
          labelText: '你的昵称',
          labelStyle: TextStyle(color: c.textSecondary),
          filled: true,
          fillColor: c.bgCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        style: TextStyle(color: c.textPrimary),
      );

  Widget _buildModeSelector(AppThemeColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('电台形态', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          ...StationMode.values.map((m) => _ModeTile(
                c: c,
                mode: m,
                selected: _mode == m,
                onTap: () => setState(() => _mode = m),
              )),
        ],
      );

  List<Widget> _buildHostPanel(AppThemeColors c) => <Widget>[
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
          '创建后你即为 DJ（音源）。房间号将生成并展示在房内，可分享给好友加入。',
          style: TextStyle(color: c.textSecondary, fontSize: 12),
        ),
      ];

  List<Widget> _buildJoinPanel(AppThemeColors c) => <Widget>[
        TextField(
          controller: _roomCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: '房间号',
            hintText: '例如 K7M2P9',
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
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _join,
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
}

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
                    : mode == StationMode.friendListen
                        ? Icons.headphones
                        : Icons.playlist_add,
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
