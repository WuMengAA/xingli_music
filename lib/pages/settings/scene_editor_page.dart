import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scene.dart';
import '../../providers/scene/scene_custom_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../scenes/scene_api.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/notification/app_notify.dart';

/// 场景自定义编辑页：名称 / 图标 / 风格 / 内容 / 背景 / 粒子 / 音频 / 音景
class SceneEditorPage extends ConsumerStatefulWidget {
  final String sceneId;
  const SceneEditorPage({super.key, required this.sceneId});

  @override
  ConsumerState<SceneEditorPage> createState() => _SceneEditorPageState();
}

class _SceneEditorPageState extends ConsumerState<SceneEditorPage> {
  late TextEditingController _name;
  late TextEditingController _mood;
  late TextEditingController _desc;
  late TextEditingController _track;
  late TextEditingController _artist;
  late TextEditingController _soundscapePath;
  late String _icon;
  late Color _bgTop;
  late Color _bgBottom;
  late Color _particleColor;
  late String _particleMotion;
  late String? _musicSourceId;
  bool _useCustomBg = false;
  bool _useCustomParticle = false;

  // 可选粒子风格
  static const List<String> _motions = [
    'float', 'rain', 'snow', 'fireplace', 'ocean', 'dust',
  ];

  // 可选音源
  static const List<String> _sources = ['minecraft', 'local', 'demo'];

  @override
  void initState() {
    super.initState();
    final Scene scene = _baseScene();
    _name = TextEditingController(text: scene.name);
    _mood = TextEditingController(text: scene.mood);
    _desc = TextEditingController(text: scene.desc);
    _track = TextEditingController(text: scene.track);
    _artist = TextEditingController(text: scene.artist);
    _soundscapePath =
        TextEditingController(text: scene.soundscapePath ?? '');
    _icon = scene.icon;
    _bgTop = scene.bgTop ?? scene.visual.gradientColors.first;
    _bgBottom = scene.bgBottom ?? const Color(0xFF1A103C);
    _particleColor = scene.particleColor ?? const Color(0xFFF5D98F);
    _particleMotion = scene.particleMotion ?? 'float';
    _musicSourceId = scene.musicSourceId;
    _useCustomBg = scene.bgTop != null;
    _useCustomParticle = scene.particleColor != null;
  }

  /// 取当前有效场景（优先自定义覆盖，否则内置）
  Scene _baseScene() {
    final List<Scene> all = ref.read(scenesProvider);
    final Scene? custom =
        ref.read(customScenesProvider.notifier).byId(widget.sceneId);
    if (custom != null) return custom;
    return all.firstWhere(
      (s) => s.id == widget.sceneId,
      orElse: () => all.first,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _mood.dispose();
    _desc.dispose();
    _track.dispose();
    _artist.dispose();
    _soundscapePath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Scene base = _baseScene();
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(base.isCustom ? '编辑自定义场景' : '自定义场景'),
        actions: [
          IconButton(
            tooltip: '保存',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('基本信息'),
          _field(_name, '名称'),
          _field(_mood, '氛围词（风格）'),
          _field(_desc, '描述'),
          _field(_track, '默认曲目'),
          _field(_artist, '默认艺术家'),

          _section('图标'),
          _iconPicker(),

          _section('背景'),
          _bgEditor(theme),

          _section('粒子'),
          _particleEditor(theme),

          _section('音频与音景'),
          _audioEditor(theme),

          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('保存自定义'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1,
              ),
        ),
      );

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            isDense: true,
          ),
        ),
      );

  /// 图标选择（现有场景图标）
  Widget _iconPicker() {
    const List<String> icons = [
      'star', 'rain', 'forest', 'fire', 'sun', 'snowflake', 'sea', 'mountain',
      'block',
    ];
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: icons.map((ic) {
        final bool sel = _icon == ic;
        return GestureDetector(
          onTap: () => setState(() => _icon = ic),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: sel
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: sel
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white24,
                width: sel ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: AppIcon(ic, size: 26, color: onSurface),
          ),
        );
      }).toList(),
    );
  }

  Widget _bgEditor(ThemeData theme) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('自定义背景渐变色'),
          value: _useCustomBg,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() => _useCustomBg = v),
        ),
        if (_useCustomBg) ...[
          Row(
            children: [
              Expanded(child: _colorRow('顶部色', _bgTop, (c) => setState(() => _bgTop = c))),
              const SizedBox(width: 12),
              Expanded(child: _colorRow('底部色', _bgBottom, (c) => setState(() => _bgBottom = c))),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_bgTop, _bgBottom],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _particleEditor(ThemeData theme) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('自定义粒子颜色'),
          value: _useCustomParticle,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() => _useCustomParticle = v),
        ),
        if (_useCustomParticle)
          Align(
            alignment: Alignment.centerLeft,
            child: _colorRow('粒子色', _particleColor, (c) => setState(() => _particleColor = c)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('粒子风格'),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                value: _particleMotion,
                isExpanded: true,
                items: _motions
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _particleMotion = v ?? 'float'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _audioEditor(ThemeData theme) {
    return Column(
      children: [
        _field(_soundscapePath, '自定义音景文件（绝对路径，留空=程序合成）'),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('专属音源'),
            const SizedBox(width: 12),
            DropdownButton<String?>(
              value: _musicSourceId,
              hint: const Text('无（使用全局曲库）'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('无（全局曲库）')),
                ..._sources
                    .map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
              ],
              onChanged: (v) => setState(() => _musicSourceId = v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _colorRow(String label, Color c, ValueChanged<Color> onChange) {
    return Row(
      children: [
        Text(label),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () async {
            final Color? picked = await showDialog<Color>(
              context: context,
              builder: (_) => _SimpleColorPicker(
                title: label,
                initial: c,
              ),
            );
            if (picked != null) onChange(picked);
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final Scene base = _baseScene();
    final Scene updated = base.copyWith(
      name: _name.text.trim().isEmpty ? base.name : _name.text.trim(),
      mood: _mood.text.trim().isEmpty ? base.mood : _mood.text.trim(),
      desc: _desc.text.trim().isEmpty ? base.desc : _desc.text.trim(),
      track: _track.text.trim().isEmpty ? base.track : _track.text.trim(),
      artist:
          _artist.text.trim().isEmpty ? base.artist : _artist.text.trim(),
      icon: _icon,
      musicSourceId: _musicSourceId,
      soundscapePath: _soundscapePath.text.trim().isEmpty
          ? null
          : _soundscapePath.text.trim(),
      bgTop: _useCustomBg ? _bgTop : null,
      bgBottom: _useCustomBg ? _bgBottom : null,
      particleColor: _useCustomParticle ? _particleColor : null,
      particleMotion: _particleMotion,
    );

    await ref.read(customScenesProvider.notifier).save(updated);

    if (mounted) {
      appNotify(context, '已保存');
      Navigator.of(context).pop();
    }
  }
}

/// 简易颜色选择器（预设色块）
class _SimpleColorPicker extends StatefulWidget {
  final String title;
  final Color initial;
  const _SimpleColorPicker({required this.title, required this.initial});

  @override
  State<_SimpleColorPicker> createState() => _SimpleColorPickerState();
}

class _SimpleColorPickerState extends State<_SimpleColorPicker> {
  late Color _sel;

  @override
  void initState() {
    super.initState();
    _sel = widget.initial;
  }

  static const List<int> _swatches = [
    0xFFF5D98F, // 星光金
    0xFF9B7BFF, // 琉璃紫
    0xFF2B2D6B, // 暮光蓝
    0xFFF8F4ED, // 奶白
    0xFF7BFF9B, // 森林绿
    0xFFFF9B5A, // 暖橙
    0xFF4A9BFF, // 海蓝
    0xFFFF7B7B, // 暖红
    0xFF1A103C, // 深空紫
    0xFFE0E8F0, // 雪白
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('选择${widget.title}'),
      content: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _swatches.map((v) {
          final Color c = Color(v);
          final bool sel = c.toARGB32() == _sel.toARGB32();
          return GestureDetector(
            onTap: () {
              setState(() => _sel = c);
              Navigator.of(context).pop(c);
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: sel ? Colors.white : Colors.white24,
                  width: sel ? 3 : 1,
                ),
              ),
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
