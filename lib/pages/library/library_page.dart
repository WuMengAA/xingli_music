import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio/audio_providers.dart';

/// 曲库页 · 曲目列表（主内容，背景/控制栏由 AppShell 提供）
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final tracks = ref.watch(effectiveMusicLibraryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('曲库',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                )),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: tracks.when(
              data: (list) => ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final t = list[i];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.music_note)),
                    title: Text(t.title),
                    subtitle: Text(t.artist),
                    trailing: Text(
                      _fmtDuration(t.duration),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    onTap: () {},
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
            ),
          ),
        ],
    );
  }

  String _fmtDuration(Duration? d) {
    if (d == null) return '--:--';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}