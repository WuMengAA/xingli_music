import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../models/scene.dart';
import '../../providers/scene/scene_custom_providers.dart';

/// 配色个性面板（v2 M5-4 · P0-M5-4，经场景页右上角微光圆点进入）。
///
/// 自定义当前场景的主色 / 强调色 / 背景渐变：
/// - 预设渐变（8 组）+ 预设强调色（8 色）；
/// - 自定义取色（色相滑块 + 饱和度/明度固定，简单取色）。
///
/// 保存时写入 `Scene.visual`（gradientColors/accent/glyph）与
/// `bgTop` / `bgBottom`（场景数据字段，允许 `Color(0x...)`，C1 豁免），
/// 经 [CustomScenesNotifier.save] 持久化。
class SceneColorPanel extends ConsumerStatefulWidget {
  const SceneColorPanel({super.key, required this.scene});

  final Scene scene;

  @override
  ConsumerState<SceneColorPanel> createState() => _SceneColorPanelState();
}

class _SceneColorPanelState extends ConsumerState<SceneColorPanel> {
  late Color _bgTop;
  late Color _bgBottom;
  late Color _accent;

  static const List<(Color, Color)> _gradientPresets =
      <(Color, Color)>[
    (Color(0xFF0D0B1A), Color(0xFF1F1838)), // 星夜
    (Color(0xFF1A1A2E), Color(0xFF16213E)), // 雨
    (Color(0xFF0F1A0F), Color(0xFF1A2E1A)), // 森林
    (Color(0xFF2E1A0F), Color(0xFF5A2E1A)), // 壁炉
    (Color(0xFF2E1A2E), Color(0xFF5A3A1A)), // 黄昏
    (Color(0xFF1A1A2E), Color(0xFF2E2E3E)), // 雪
    (Color(0xFF0A1628), Color(0xFF0F2040)), // 海底
    (Color(0xFF3A2A4A), Color(0xFF6A4A7A)), // 紫雾
  ];

  static const List<Color> _accentPresets = <Color>[
    Color(0xFF7C6BFF), // 品牌紫
    Color(0xFFF5D98F), // 星金
    Color(0xFF7B9BFF), // 雨蓝
    Color(0xFF7BFF9B), // 森绿
    Color(0xFFFF9B5A), // 火橙
    Color(0xFFFFB87B), // 夕阳
    Color(0xFFE0E8F0), // 雪白
    Color(0xFF4A9BFF), // 海蓝
  ];

  @override
  void initState() {
    super.initState();
    final Scene s = widget.scene;
    _bgTop = s.bgTop ?? (s.visual.gradientColors.isNotEmpty
        ? s.visual.gradientColors.first
        : AppColors.accent);
    _bgBottom = s.bgBottom ??
        (s.visual.gradientColors.length > 1
            ? s.visual.gradientColors.last
            : const Color(0xFF1A103C));
    _accent = s.visual.accent;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('配色面板 · ${widget.scene.name}', style: AppTextStyles.title),
            const SizedBox(height: AppSpace.md),
            Text('背景渐变', style: AppTextStyles.subtitle),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: <Widget>[
                for (final (Color top, Color bottom) in _gradientPresets)
                  _GradientSwatch(
                    top: top,
                    bottom: bottom,
                    selected: _bgTop.toARGB32() == top.toARGB32() &&
                        _bgBottom.toARGB32() == bottom.toARGB32(),
                    onTap: () => setState(() {
                      _bgTop = top;
                      _bgBottom = bottom;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Text('强调色', style: AppTextStyles.subtitle),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: <Widget>[
                for (final Color c in _accentPresets)
                  _ColorSwatch(
                    color: c,
                    selected: _accent.toARGB32() == c.toARGB32(),
                    onTap: () => setState(() => _accent = c),
                  ),
                _ColorSwatch(
                  color: _accent,
                  selected: !_accentPresets
                      .any((Color c) => c.toARGB32() == _accent.toARGB32()),
                  onTap: _pickCustomAccent,
                  isCustom: true,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('应用到当前场景'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomAccent() async {
    final Color? picked = await showDialog<Color>(
      context: context,
      builder: (BuildContext ctx) => _HuePickerDialog(initial: _accent),
    );
    if (picked != null && mounted) {
      setState(() => _accent = picked);
    }
  }

  Future<void> _apply() async {
    final Scene scene = widget.scene;
    final Scene updated = scene.copyWith(
      visual: scene.visual.copyWith(
        accent: _accent,
        gradientColors: <Color>[_bgTop, _bgBottom],
        stops: <double>[0.2, 1.0],
      ),
      bgTop: _bgTop,
      bgBottom: _bgBottom,
    );
    await ref.read(customScenesProvider.notifier).save(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已应用到当前场景并持久化')),
    );
  }
}

/// 渐变预设色块。
class _GradientSwatch extends StatelessWidget {
  const _GradientSwatch({
    required this.top,
    required this.bottom,
    required this.selected,
    required this.onTap,
  });

  final Color top;
  final Color bottom;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[top, bottom],
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.borderDefault,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

/// 单色预设色块。
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.isCustom = false,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.borderDefault,
            width: selected ? 2 : 1,
          ),
        ),
        child: isCustom
            ? const Icon(Icons.colorize_rounded,
                size: 18, color: AppColors.onAccent)
            : null,
      ),
    );
  }
}

/// 简易取色对话框：色相滑块 + 固定饱和度/明度。
class _HuePickerDialog extends StatefulWidget {
  const _HuePickerDialog({required this.initial});

  final Color initial;

  @override
  State<_HuePickerDialog> createState() => _HuePickerDialogState();
}

class _HuePickerDialogState extends State<_HuePickerDialog> {
  late double _hue;

  @override
  void initState() {
    super.initState();
    _hue = HSLColor.fromColor(widget.initial).hue;
  }

  @override
  Widget build(BuildContext context) {
    final Color current = HSLColor.fromAHSL(1, _hue, 0.75, 0.6).toColor();
    return AlertDialog(
      title: const Text('自定义强调色', style: AppTextStyles.subtitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: current,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderDefault),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Slider(
            value: _hue,
            min: 0,
            max: 360,
            onChanged: (double v) => setState(() => _hue = v),
          ),
          Text('色相 ${_hue.round()}°', style: AppTextStyles.caption),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(current),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
