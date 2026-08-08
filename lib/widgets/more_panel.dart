import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scene.dart';
import '../models/track.dart';
import '../providers/audio/audio_providers.dart';
import '../providers/scene/scene_providers.dart';
import '../providers/session/session_providers.dart';
import '../services/audio/audio_service.dart';
import '../pages/settings/scene_editor_page.dart';
import '../pages/settings/server_settings_page.dart';
import 'app_icon.dart';
import 'palette_panel.dart';

/// 更多面板的五种形态
enum PanelMode { bubble, capsule, card, array, nine }

/// 面板视图
enum _PanelView { menu, playlist, scenes }

/// 更多面板：上滑控制区触发。
class MorePanel extends ConsumerStatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final double safeBottom;

  const MorePanel({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.safeBottom,
  });

  @override
  ConsumerState<MorePanel> createState() => _MorePanelState();
}

class _MorePanelState extends ConsumerState<MorePanel> {
  _PanelView _view = _PanelView.menu;
  bool _showMore = false;

  static const List<Duration?> _timerChoices = [
    null,
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 60),
  ];
  int _timerIndex = 0;
  Timer? _sleepTimer;

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }

  void _setSleepTimer() {
    _timerIndex = (_timerIndex + 1) % _timerChoices.length;
    _sleepTimer?.cancel();
    final Duration? d = _timerChoices[_timerIndex];
    if (d == null) return;
    _sleepTimer = Timer(d, () {
      final AudioService audio = ref.read(audioServiceProvider);
      if (audio.musicPlaying) {
        audio.togglePlay();
      }
    });
  }

  String get _timerLabel {
    final Duration? d = _timerChoices[_timerIndex];
    if (d == null) return '定时';
    return '${d.inMinutes}分钟';
  }

  Future<void> _playTrack(Track track) async {
    final AudioService audio = ref.read(audioServiceProvider);
    await audio.playMusic(track);
    ref.read(nowPlayingProvider.notifier).state = track;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PanelMode mode = ref.watch(panelModeProvider);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutQuad,
      bottom: widget.isOpen ? 0 : -560,
      left: 0,
      right: 0,
      child: AnimatedScale(
        scale: widget.isOpen ? 1.0 : 0.9,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 200) {
              widget.onClose();
            }
          },
          child: Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 20 + widget.safeBottom,
            ),
            decoration: BoxDecoration(
              color: const Color(0x66101420),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖拽手柄
                Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // 视图头
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_view != _PanelView.menu)
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _view = _PanelView.menu),
                        icon: AppIcon(AppIcons.previous,
                            size: 14, color: theme.colorScheme.onSurfaceVariant),
                        label: Text('返回',
                            style: theme.textTheme.labelSmall),
                      )
                    else
                      const SizedBox(width: 60),
                    Text(
                      _view == _PanelView.playlist
                          ? '曲库'
                          : _view == _PanelView.scenes
                              ? '场景'
                              : '更多',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 2,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final modes = PanelMode.values;
                        final i = (modes.indexOf(mode) + 1) % modes.length;
                        ref.read(panelModeProvider.notifier).state = modes[i];
                      },
                      child: Text('切换形态',
                          style: theme.textTheme.labelSmall),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 内容区
                SizedBox(
                  height: _view == _PanelView.menu ? 168 : 300,
                  child: _view == _PanelView.menu
                      ? _buildMenu(theme, mode)
                      : _view == _PanelView.playlist
                          ? _buildPlaylist(theme)
                          : _buildScenes(theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(ThemeData theme, PanelMode mode) {
    final List<_MenuItem> primary = [
      _MenuItem('playlist', '曲库', AppIcons.music,
          onTap: () => setState(() => _view = _PanelView.playlist)),
      _MenuItem('scene', '场景', AppIcons.mountain,
          onTap: () => setState(() => _view = _PanelView.scenes)),
      _playModeMenuItem(),
    ];
    final List<_MenuItem> secondary = [
      _MenuItem('favorite', '收藏', AppIcons.bookmark, onTap: () {
        // 延迟到帧后弹出，避免 Overlay 布局期创建 SnackBar entry
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('收藏功能正在打磨中喵～'),
              duration: Duration(seconds: 1),
            ),
          );
        });
      }),
      _MenuItem('palette', '调色盘', AppIcons.sun, onTap: _openPalette),
      _MenuItem('volume', '音量', AppIcons.volume, onTap: () {
        ref.read(volumeSliderOpenProvider.notifier).state = true;
      }),
      _MenuItem('timer', _timerLabel, AppIcons.clock, onTap: _setSleepTimer),
      _MenuItem('settings', '设置', AppIcons.settings, onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ServerSettingsPage()),
        );
      }),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final e in primary)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _buildItem(mode, e),
                ),
              ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: _showMore
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      for (final e in secondary)
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 3),
                            child: _buildItem(mode, e),
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => setState(() => _showMore = !_showMore),
          child: Text(_showMore ? '收起' : '更多',
              style: theme.textTheme.labelSmall),
        ),
      ],
    );
  }

  /// 播放方式切换项（顺序 → 倒叙 → 随机 → 单曲循环 → 循环）
  _MenuItem _playModeMenuItem() {
    const Map<PlayMode, String> labels = {
      PlayMode.order: '顺序',
      PlayMode.reverse: '倒叙',
      PlayMode.shuffle: '随机',
      PlayMode.loop: '单曲循环',
    };
    const Map<PlayMode, String> icons = {
      PlayMode.order: 'music',
      PlayMode.reverse: 'mountain',
      PlayMode.shuffle: 'refresh',
      PlayMode.loop: 'play',
    };
    final PlayMode mode = ref.watch(playModeProvider);
    return _MenuItem(
      'playmode',
      labels[mode] ?? '顺序',
      icons[mode] ?? 'refresh',
      onTap: () {
        final PlayMode next = switch (mode) {
          PlayMode.order => PlayMode.reverse,
          PlayMode.reverse => PlayMode.shuffle,
          PlayMode.shuffle => PlayMode.loop,
          PlayMode.loop => PlayMode.order,
        };
        ref.read(playModeProvider.notifier).state = next;
      },
    );
  }

  /// 打开调色盘（独立的简单页面）
  void _openPalette() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(title: const Text('调色盘')),
          body: const Center(child: PalettePanel()),
        ),
      ),
    );
  }

  Widget _buildItem(PanelMode mode, _MenuItem e) {
    switch (mode) {
      case PanelMode.bubble:
        return _BubbleItem(item: e);
      case PanelMode.capsule:
        return _CapsuleItem(item: e);
      case PanelMode.card:
        return _CardItem(item: e);
      case PanelMode.array:
        return _ArrayItem(item: e);
      case PanelMode.nine:
        return _GridItem(item: e);
    }
  }

  /// 曲库界面：按来源分组展示全部曲目，含统计与「管理曲库」入口
  /// 下拉可刷新：重新扫描目录，新加入的音乐立即出现
  Widget _buildPlaylist(ThemeData theme) {
    final AsyncValue<List<Track>> library =
        ref.watch(effectiveMusicLibraryProvider);
    final Track? now = ref.watch(nowPlayingProvider);

    Future<void> refresh() {
      // 使曲库 FutureProvider 失效，触发重新扫描
      ref.invalidate(effectiveMusicLibraryProvider);
      return ref.read(effectiveMusicLibraryProvider.future).then((_) {});
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: library.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 120,
              child: Center(child: Text('正在读取音乐…')),
            ),
          ],
        ),
        error: (_, __) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 120,
              child: Center(child: Text('曲库加载失败，下拉重试')),
            ),
          ],
        ),
        data: (tracks) {
          if (tracks.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(
                  height: 120,
                  child: Center(child: Text('曲库为空，下拉刷新或去「曲库设置」添加本地目录')),
                ),
              ],
            );
          }
          // 按来源分组（保持首次出现顺序）
          final Map<String, List<Track>> groups = <String, List<Track>>{};
          for (final Track t in tracks) {
            final String key = t.sourceId.isEmpty ? 'other' : t.sourceId;
            groups.putIfAbsent(key, () => <Track>[]).add(t);
          }
          final List<Object> items = <Object>[];
          groups.forEach((String key, List<Track> list) {
            items.add(key);
            items.addAll(list);
          });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(
                      '共 ${tracks.length} 首 · ${groups.length} 个来源',
                      style: theme.textTheme.labelSmall,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ServerSettingsPage(),
                        ),
                      ),
                      child: Text('管理曲库', style: theme.textTheme.labelSmall),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final Object e = items[i];
                    if (e is String) {
                      final List<Track> list = groups[e]!;
                      return _groupHeader(_sourceLabel(e), list.length, theme);
                    }
                    return _trackTile(e as Track, now, theme);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _groupHeader(String label, int count, ThemeData theme) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );

  Widget _trackTile(Track t, Track? now, ThemeData theme) {
    final bool active = now?.uri == t.uri;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        onTap: () => _playTrack(t),
        leading: active
            ? AppIcon(AppIcons.play,
                size: 18, color: theme.colorScheme.primary)
            : Text('♪', style: theme.textTheme.bodySmall),
        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(
          t.source == TrackSource.stream
              ? '流'
              : t.source == TrackSource.local
                  ? '本'
                  : '景',
          style: theme.textTheme.labelSmall,
        ),
      ),
    );
  }

  String _sourceLabel(String sourceId) {
    if (sourceId == 'local') return '本地音乐';
    if (sourceId == 'minecraft') return 'Minecraft';
    if (sourceId == 'demo') return '演示';
    if (sourceId == 'other') return '其他';
    if (sourceId.startsWith('dir:')) return '目录 · ${sourceId.substring(4)}';
    return sourceId;
  }

  Widget _buildScenes(ThemeData theme) {
    final List<Scene> scenes = ref.watch(sceneOrderProvider);
    final Scene active = ref.watch(activeSceneProvider);

    return ListView.builder(
      itemCount: scenes.length,
      itemBuilder: (context, i) {
        final Scene s = scenes[i];
        final bool isActive = s.id == active.id;
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            onTap: () {
              ref.read(currentSceneIndexProvider.notifier).state = i;
              widget.onClose();
            },
            leading: AppIcon(s.icon, size: 20, color: s.visual.accent),
            title: Text(s.name),
            subtitle: Text(s.mood),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '自定义场景',
                  icon: const Icon(Icons.tune, size: 18),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SceneEditorPage(sceneId: s.id),
                      ),
                    );
                  },
                ),
                if (isActive)
                  AppIcon(AppIcons.play,
                      size: 16, color: theme.colorScheme.primary),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MenuItem {
  final String id;
  final String label;
  final String icon;
  final VoidCallback onTap;
  const _MenuItem(this.id, this.label, this.icon, {required this.onTap});
}

String panelModeLabel(PanelMode m) => switch (m) {
  PanelMode.bubble => '气泡',
  PanelMode.capsule => '胶囊',
  PanelMode.card => '卡片',
  PanelMode.array => '阵列',
  PanelMode.nine => '九宫格',
};

final panelModeProvider = StateProvider<PanelMode>((ref) => PanelMode.capsule);

// ── 各形态 item（官方 Material + InkWell 水波纹）─────────

class _BubbleItem extends StatelessWidget {
  final _MenuItem item;
  const _BubbleItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: SizedBox(
          height: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(item.icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 3),
              Text(item.label, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapsuleItem extends StatelessWidget {
  final _MenuItem item;
  const _CapsuleItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(item.icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(item.label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardItem extends StatelessWidget {
  final _MenuItem item;
  const _CardItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            children: [
              AppIcon(item.icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(item.label, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrayItem extends StatelessWidget {
  final _MenuItem item;
  const _ArrayItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(item.icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(item.label, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridItem extends StatelessWidget {
  final _MenuItem item;
  const _GridItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(item.icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(item.label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}
