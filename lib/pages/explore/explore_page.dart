import 'package:flutter/material.dart';

/// 探索页 · 情绪网格（主内容，背景/控制栏由 AppShell 提供）
class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color base = theme.colorScheme.primary;
    final HSLColor hsl = HSLColor.fromColor(base);
    final Color accent = hsl.withHue((hsl.hue + 30) % 360).toColor();

    final moods = <_Mood>[
      _Mood('雨夜', '🌧️', '平静 · 低落', base),
      _Mood('极光', '✨', '惊喜 · 明亮', accent),
      _Mood('壁炉', '🔥', '温暖 · 沉静', base),
      _Mood('森林', '🌲', '清新 · 平静', accent),
      _Mood('海洋', '🌊', '开阔 · 平静', base),
      _Mood('雪落', '❄️', '沉静 · 纯白', accent),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('探索',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                )),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.05,
              ),
              itemCount: moods.length,
              itemBuilder: (_, i) {
                final m = moods[i];
                return Card(
                  color: m.color,
                  child: InkWell(
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(m.glyph, style: const TextStyle(fontSize: 32)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(m.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.onPrimary,
                                  )),
                              const SizedBox(height: 4),
                              Text(m.mood,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onPrimary
                                        .withValues(alpha: 0.75),
                                  )),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Mood {
  final String name;
  final String glyph;
  final String mood;
  final Color color;
  const _Mood(this.name, this.glyph, this.mood, this.color);
}