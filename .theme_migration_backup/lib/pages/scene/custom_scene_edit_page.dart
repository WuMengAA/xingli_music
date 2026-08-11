import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../models/scene.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/scene_custom_providers.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_views.dart';

/// 自定义场景编辑（v2 M5-3 · P0-M5-3）。
///
/// 编辑：名称 / 描述（心情文案）/ 心情 / 图标选择 / 显示开关 /
/// **默认 BGM 选曲（从曲库选曲）**。
///
/// 新场景：`id = 'custom_<毫秒>'`，默认视觉取内置「星夜」。
class CustomSceneEditPage extends ConsumerStatefulWidget {
  const CustomSceneEditPage({super.key, this.scene});

  final Scene? scene;

  @override
  ConsumerState<CustomSceneEditPage> createState() => _CustomSceneEditPageState();
}

class _CustomSceneEditPageState extends ConsumerState<CustomSceneEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _mood;
  late String _icon;
  late bool _visible;
  Scene? _bgmTrackScene;

  static const List<String> _icons = <String>[
    'star',
    'rain',
    'forest',
    'fire',
    'sun',
    'snowflake',
    'sea',
    'mountain',
    'music',
    'clock',
  ];

  bool get _isNew => widget.scene == null;

  @override
  void initState() {
    super.initState();
    final Scene? s = widget.scene;
    _name = TextEditingController(text: s?.name ?? '');
    _desc = TextEditingController(text: s?.desc ?? '');
    _mood = TextEditingController(text: s?.mood ?? '');
    _icon = s?.icon ?? 'star';
    _visible = s?.visible ?? true;
    if (s?.bgmUri != null) {
      _bgmTrackScene = s;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _mood.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写场景名称')),
      );
      return;
    }
    final Scene base = widget.scene ??
        const Scene(
          id: '',
          name: '',
          mood: '自定义',
          desc: '',
          track: '',
          artist: '',
          soundscape: '程序合成音景',
          icon: 'star',
          visual: SceneVisual(
            gradientColors: <Color>[Color(0xFF0D0B1A), Color(0xFF1F1838)],
            stops: <double>[0.2, 1.0],
            accent: Color(0xFF7C6BFF),
            glyph: '✦',
          ),
          visualWeight: 0.8,
          valence: 0.5,
          energy: 0.5,
        );

    final Scene updated = base.copyWith(
      id: base.id.isEmpty
          ? 'custom_${DateTime.now().millisecondsSinceEpoch}'
          : base.id,
      name: name,
      desc: _desc.text.trim(),
      mood: _mood.text.trim().isEmpty ? '自定义' : _mood.text.trim(),
      icon: _icon,
      visible: _visible,
      bgmUri: _bgmTrackScene?.bgmUri,
      bgmTitle: _bgmTrackScene?.bgmTitle,
      bgmArtist: _bgmTrackScene?.bgmArtist,
    );

    await ref.read(customScenesProvider.notifier).save(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: _isNew ? '新建场景' : '编辑场景',
          onBack: () => Navigator.of(context).pop(),
          actions: <Widget>[
            TextButton(onPressed: _save, child: const Text('保存')),
          ],
          body: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              _field(_name, '名称'),
              _field(_desc, '描述 / 心情文案'),
              _field(_mood, '心情（如：温暖 / 平静）'),
              const SizedBox(height: AppSpace.md),

              Text('图标', style: AppTextStyles.bodyMuted),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: <Widget>[
                  for (final String icon in _icons)
                    ChoiceChip(
                      label: Text(_iconGlyph(icon)),
                      selected: _icon == icon,
                      onSelected: (_) => setState(() => _icon = icon),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.md),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('在列表中显示', style: AppTextStyles.body),
                value: _visible,
                onChanged: (bool v) => setState(() => _visible = v),
              ),
              const SizedBox(height: AppSpace.md),

              Text('默认背景音乐（BGM）', style: AppTextStyles.bodyMuted),
              const SizedBox(height: AppSpace.xs),
              _BgmPicker(
                selected: _bgmTrackScene,
                onSelected: (Track? t) {
                  setState(() {
                    if (t == null) {
                      _bgmTrackScene = null;
                    } else {
                      _bgmTrackScene = base.copyWith(
                        bgmUri: t.uri,
                        bgmTitle: t.title,
                        bgmArtist: t.artist,
                      );
                    }
                  });
                },
              ),
              const SizedBox(height: AppSpace.lg),
            ],
          ),
        ),
      ),
    );
  }

  Scene get base => widget.scene ??
      const Scene(
        id: '',
        name: '',
        mood: '自定义',
        desc: '',
        track: '',
        artist: '',
        soundscape: '',
        icon: 'star',
        visual: SceneVisual(
          gradientColors: <Color>[Color(0xFF0D0B1A), Color(0xFF1F1838)],
          stops: <double>[0.2, 1.0],
          accent: Color(0xFF7C6BFF),
          glyph: '✦',
        ),
        visualWeight: 0.8,
        valence: 0.5,
        energy: 0.5,
      );

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: TextField(
          controller: c,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: AppTextStyles.hint,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  String _iconGlyph(String icon) => switch (icon) {
        'star' => '✦',
        'rain' => '❖',
        'forest' => '☘',
        'fire' => '🔥',
        'sun' => '☀',
        'snowflake' => '❄',
        'sea' => '〰',
        'mountain' => '⛰',
        'music' => '♪',
        'clock' => '◷',
        _ => '✦',
      };
}

/// 默认 BGM 选曲（从曲库选择）。
class _BgmPicker extends ConsumerWidget {
  const _BgmPicker({required this.selected, required this.onSelected});

  final Scene? selected;
  final ValueChanged<Track?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);
    final String? bgmTitle = selected?.bgmTitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        library.when(
          data: (List<Track> tracks) {
            if (tracks.isEmpty) {
              return const EmptyView(
                title: '曲库为空',
                message: '请先在设置「音源」中添加音乐',
              );
            }
            return Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('无'),
                  selected: bgmTitle == null,
                  onSelected: (_) => onSelected(null),
                ),
                for (final Track t in tracks.take(20))
                  ChoiceChip(
                    label: Text(
                      '${t.title} · ${t.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: bgmTitle == t.title,
                    onSelected: (_) => onSelected(t),
                  ),
                if (tracks.length > 20)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Text(
                      '（仅展示前 20 首，完整曲库见曲库页）',
                      style: AppTextStyles.caption,
                    ),
                  ),
              ],
            );
          },
          loading: () => const LoadingView(),
          error: (Object e, StackTrace st) => Text(
            '曲库加载失败：$e',
            style: AppTextStyles.caption.copyWith(color: AppColors.danger),
          ),
        ),
        if (bgmTitle != null) ...<Widget>[
          const SizedBox(height: AppSpace.xs),
          Text(
            '已选 BGM：$bgmTitle · ${selected?.bgmArtist ?? ''}',
            style: AppTextStyles.caption,
          ),
        ],
      ],
    );
  }
}
