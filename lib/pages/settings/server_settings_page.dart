import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/local_dir_config.dart';
import '../../models/server_config.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/local_dir_providers.dart';
import '../../providers/audio/server_config_provider.dart';
import '../../services/music_sources/radio_source.dart';
import '../../services/music_sources/subsonic_source.dart';

/// 外部流媒体连接设置页
///
/// 支持新增 / 编辑 Subsonic 自建服务器与公开电台目录，
/// 密码存于系统安全存储，连接信息存于本地 SharedPreferences。
class ServerSettingsPage extends ConsumerStatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  ConsumerState<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends ConsumerState<ServerSettingsPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _dirCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _pwdCtrl = TextEditingController();
  final TextEditingController _tagsCtrl = TextEditingController(text: 'ambient');

  SourceType _type = SourceType.subsonic;
  bool _enabled = true;
  bool _testing = false;
  String? _testResult;
  ServerConfig? _editing;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dirCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _startEdit(ServerConfig c) {
    setState(() {
      _editing = c;
      _type = c.type;
      _nameCtrl.text = c.name;
      _urlCtrl.text = c.baseUrl;
      _userCtrl.text = c.user;
      _pwdCtrl.text = c.password;
      _tagsCtrl.text = c.tags.join(', ');
      _enabled = c.enabled;
      _testResult = null;
    });
  }

  void _resetForm() {
    setState(() {
      _editing = null;
      _type = SourceType.subsonic;
      _nameCtrl.clear();
      _urlCtrl.clear();
      _userCtrl.clear();
      _pwdCtrl.clear();
      _tagsCtrl.text = 'ambient';
      _enabled = true;
      _testResult = null;
    });
  }

  Future<void> _addDir() async {
    final String p = _dirCtrl.text.trim();
    if (p.isEmpty) return;
    await ref.read(localDirConfigsProvider.notifier).add(p);
    _dirCtrl.clear();
    // 立即重新扫描曲库，回到曲库界面即能看到新目录
    ref.invalidate(musicLibraryProvider);
    ref.invalidate(effectiveMusicLibraryProvider);
  }

  Future<void> _test() async {
    final ServerConfig cfg = _buildConfig();
    if (cfg.name.isEmpty) {
      setState(() => _testResult = '请先填写名称');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final bool ok = cfg.type == SourceType.subsonic
        ? await SubsonicSource(cfg).testConnection()
        : await RadioSource(tags: cfg.tags).testConnection();
    if (mounted) {
      setState(() {
        _testing = false;
        _testResult = ok ? '连接成功 ✓' : '连接失败 ✗';
      });
    }
  }

  ServerConfig _buildConfig() {
    final List<String> tags = _tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return ServerConfig(
      type: _type,
      name: _nameCtrl.text.trim(),
      baseUrl: _urlCtrl.text.trim(),
      user: _userCtrl.text.trim(),
      password: _pwdCtrl.text,
      enabled: _enabled,
      tags: tags.isNotEmpty ? tags : const ['ambient'],
    );
  }

  Future<void> _save() async {
    final ServerConfig cfg = _buildConfig();
    if (cfg.name.isEmpty) {
      setState(() => _testResult = '名称不能为空');
      return;
    }
    await ref.read(serverConfigsProvider.notifier).addOrUpdate(cfg);
    _resetForm();
  }

  @override
  Widget build(BuildContext context) {
    final List<ServerConfig> configs = ref.watch(serverConfigsProvider);
    final List<LocalDirConfig> dirs = ref.watch(localDirConfigsProvider);
    final Color accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0A1F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('设置', style: TextStyle(color: Colors.white70)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── 全局设置 ──
          _sectionTitle('全局设置'),
          _globalPlayMode(accent),
          const SizedBox(height: 8),
          _globalMusicVolume(accent),
          _globalSoundscapeVolume(accent),

          // ── 展示设置 ──
          _sectionTitle('展示'),
          _showParticlesSwitch(),

          // ── 曲库设置（可配置） ──
          _sectionTitle('曲库（本地目录）'),
          _field(_dirCtrl,
              '如 d:/Music/我的音乐 或 /storage/emulated/0/Music/xxx', false),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addDir,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加曲库'),
            ),
          ),
          if (dirs.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...dirs.map((d) => _dirTile(d, accent)),
          ],

          _sectionTitle('已配置源'),
          ...configs.map((c) => _configTile(c, accent)),
          const SizedBox(height: 8),
          _sectionTitle(_editing != null ? '编辑源' : '新增源'),
          _typeToggle(),
          const SizedBox(height: 12),
          _field(_nameCtrl, '名称（唯一标识）', false),
          if (_type == SourceType.subsonic) ...[
            _field(_urlCtrl, '服务器地址（http://IP:4533）', false),
            _field(_userCtrl, '用户名', false),
            _field(_pwdCtrl, '密码', true),
          ] else
            _field(_tagsCtrl, '标签（逗号分隔，如 ambient, jazz）', false),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : _test,
                  child: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: Text(_editing != null ? '保存修改' : '添加'),
                ),
              ),
            ],
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.contains('成功')
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_editing != null)
            TextButton(
              onPressed: _resetForm,
              child: const Text('取消编辑', style: TextStyle(color: Colors.white54)),
            ),

          // ── 高级 ──
          _sectionTitle('高级'),
          _advancedTile(Icons.bug_report, '调试日志',
              '查看或定位日志文件（自动写入 logs/app.log）', () {}),

          // ── 关于 ──
          _sectionTitle('关于'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline, color: Colors.white54),
            title: const Text('星璃 · 无限音乐空间',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('v1.0 · 本地优先的沉浸式音乐空间',
                style: TextStyle(color: Colors.white38)),
            trailing: TextButton(
              onPressed: () => _showAbout(context),
              child: const Text('更多', style: TextStyle(color: Colors.white54)),
            ),
          ),
        ],
      ),
    );
  }

  /// 全局：默认播放方式
  Widget _globalPlayMode(Color accent) {
    final PlayMode mode = ref.watch(playModeProvider);
    const Map<PlayMode, String> labels = {
      PlayMode.order: '顺序播放',
      PlayMode.reverse: '倒叙播放',
      PlayMode.shuffle: '随机播放',
      PlayMode.loop: '单曲循环',
    };
    return Row(
      children: [
        const Text('播放方式', style: TextStyle(color: Colors.white70)),
        const Spacer(),
        DropdownButton<PlayMode>(
          value: mode,
          dropdownColor: const Color(0xFF1A1230),
          style: const TextStyle(color: Colors.white),
          items: PlayMode.values
              .map((m) =>
                  DropdownMenuItem(value: m, child: Text(labels[m] ?? '')))
              .toList(),
          onChanged: (m) {
            if (m != null) {
              ref.read(playModeProvider.notifier).state = m;
            }
          },
        ),
      ],
    );
  }

  /// 全局：默认音乐声音量
  Widget _globalMusicVolume(Color accent) {
    final double v = ref.watch(musicVolumeProvider);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text('音乐声 ${(v * 100).round()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: v,
            activeColor: accent,
            onChanged: (nv) {
              ref.read(musicVolumeProvider.notifier).state = nv;
              unawaited(ref.read(audioServiceProvider).setMusicVolume(nv));
            },
          ),
        ),
      ],
    );
  }

  /// 全局：默认背景声音量
  Widget _globalSoundscapeVolume(Color accent) {
    final double v = ref.watch(soundscapeVolumeProvider);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text('背景声 ${(v * 100).round()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: v,
            activeColor: accent,
            onChanged: (nv) {
              ref.read(soundscapeVolumeProvider.notifier).state = nv;
              unawaited(
                  ref.read(audioServiceProvider).setSoundscapeVolume(nv));
            },
          ),
        ),
      ],
    );
  }

  /// 展示：粒子开关
  Widget _showParticlesSwitch() {
    // 粒子显隐由主题派生，此处提供全局偏好（默认开）
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('粒子效果', style: TextStyle(color: Colors.white70)),
      value: ref.watch(showParticlesProvider),
      onChanged: (v) =>
          ref.read(showParticlesProvider.notifier).state = v,
    );
  }

  Widget _advancedTile(IconData icon, String title, String sub, VoidCallback onTap) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Colors.white54),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(sub, style: const TextStyle(color: Colors.white38)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
        onTap: onTap,
      );

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: '星璃 · 无限音乐空间',
      applicationVersion: 'v1.0',
      applicationIcon: const Icon(Icons.music_note, color: Colors.purpleAccent),
      applicationLegalese: '本地优先的沉浸式音乐空间\n星璃 Stelarith',
      children: const [
        Text('在星光中流淌的真理之光，陪你找到答案。'),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
      );

  Widget _typeToggle() => ToggleButtons(
        isSelected: [
          _type == SourceType.subsonic,
          _type == SourceType.radio,
        ],
        onPressed: (i) => setState(
            () => _type = i == 0 ? SourceType.subsonic : SourceType.radio),
        borderRadius: BorderRadius.circular(12),
        selectedColor: Colors.white,
        fillColor: Colors.purpleAccent.withValues(alpha: 0.4),
        color: Colors.white54,
        children: const [
          Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('自建服务器')),
          Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('公开电台')),
        ],
      );

  Widget _field(TextEditingController c, String label, bool obscure) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white54),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.white24),
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.purpleAccent),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );

  Widget _dirTile(LocalDirConfig d, Color accent) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, color: Colors.white54, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(d.path,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            Switch(
              value: d.enabled,
              activeThumbColor: accent,
              onChanged: (v) async {
                await ref
                    .read(localDirConfigsProvider.notifier)
                    .setEnabled(d.path, v);
                ref.invalidate(musicLibraryProvider);
                ref.invalidate(effectiveMusicLibraryProvider);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
              onPressed: () async {
                await ref
                    .read(localDirConfigsProvider.notifier)
                    .remove(d.path);
                ref.invalidate(musicLibraryProvider);
                ref.invalidate(effectiveMusicLibraryProvider);
              },
            ),
          ],
        ),
      );

  Widget _configTile(ServerConfig c, Color accent) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(
              c.type == SourceType.subsonic ? Icons.storage : Icons.radio,
              color: Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                  Text(
                    c.type == SourceType.subsonic
                        ? (c.baseUrl.isEmpty ? '电台目录' : c.baseUrl)
                        : '标签：${c.tags.join(", ")}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: c.enabled,
              activeThumbColor: accent,
              onChanged: (v) => ref
                  .read(serverConfigsProvider.notifier)
                  .setEnabled(c.name, v),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
              onPressed: () => _startEdit(c),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
              onPressed: () =>
                  ref.read(serverConfigsProvider.notifier).remove(c.name),
            ),
          ],
        ),
      );
}
