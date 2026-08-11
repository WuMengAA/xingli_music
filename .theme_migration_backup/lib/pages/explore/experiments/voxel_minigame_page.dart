import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/light_tokens.dart';
import '../../../models/voxel.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_chip.dart';
import '../../../widgets/voxel/voxel_canvas_controller.dart';
import '../../../widgets/voxel/voxel_canvas_view.dart';

/// 实验 D · 2.5D 小游戏（v2 M2-D · Q3 已裁决：可玩原型）。
///
/// 与音效编辑器共享 [VoxelCanvasController] + [VoxelCanvasView]（纯 CustomPaint）。
/// 玩家方块 + Ticker 循环：移动 / 收集音效块 / 计分。
/// 控制：桌面方向键 / WASD；移动端屏幕 D-pad。
class VoxelMinigamePage extends StatefulWidget {
  const VoxelMinigamePage({super.key});

  @override
  State<VoxelMinigamePage> createState() => _VoxelMinigamePageState();
}

class _VoxelMinigamePageState extends State<VoxelMinigamePage>
    with SingleTickerProviderStateMixin {
  static const int _cols = 8;
  static const int _rows = 8;

  final VoxelCanvasController _controller =
      VoxelCanvasController(cols: _cols, rows: _rows);
  late final Ticker _ticker;

  int _playerCol = 3;
  int _playerRow = 3;
  int _dirCol = 0;
  int _dirRow = 0;
  int _score = 0;
  int _ticks = 0;
  bool _running = false;
  bool _gameOver = false;

  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _seedBlocks();
    _ticker.start();
    _running = true;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 随机撒一些音效块作为收集品。
  void _seedBlocks() {
    for (int i = 0; i < 10; i++) {
      final int c = _rng.nextInt(_cols);
      final int r = _rng.nextInt(_rows);
      if (c == _playerCol && r == _playerRow) continue;
      final VoxelBlockType type =
          kVoxelBlockTypes[_rng.nextInt(kVoxelBlockTypes.length)];
      _controller.blocks[VoxelCanvasController.keyOf(c, r)] = type.id;
    }
  }

  void _onTick(Duration elapsed) {
    if (!_running || _gameOver) return;
    _ticks++;
    // 每 8 tick 移动一格（约 0.5 秒一步）
    if (_ticks % 8 == 0) {
      setState(() {
        final int nc = _playerCol + _dirCol;
        final int nr = _playerRow + _dirRow;
        if (_controller.inBounds(nc, nr)) {
          _playerCol = nc;
          _playerRow = nr;
        }
        _tryCollect();
      });
    }
  }

  void _tryCollect() {
    final String key = VoxelCanvasController.keyOf(_playerCol, _playerRow);
    if (_controller.blocks.containsKey(key)) {
      _controller.removeBlock(_playerCol, _playerRow);
      _score += 10;
    }
    if (_controller.blocks.isEmpty) {
      _gameOver = true;
    }
  }

  void _setDir(int dc, int dr) {
    setState(() {
      _dirCol = dc;
      _dirRow = dr;
    });
  }

  void _restart() {
    setState(() {
      _playerCol = 3;
      _playerRow = 3;
      _dirCol = 0;
      _dirRow = 0;
      _score = 0;
      _ticks = 0;
      _gameOver = false;
      _controller.clear();
      _seedBlocks();
      _running = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '2.5D 小游戏',
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 4),
              child: StateChip(tone: ChipTone.experimenting, label: '实验'),
            ),
          ],
          body: Column(
            children: <Widget>[
              // 计分板
              Row(
                children: <Widget>[
                  Text('得分', style: AppTextStyles.bodyMuted),
                  const SizedBox(width: AppSpace.sm),
                  Text('$_score', style: AppTextStyles.subtitle),
                  const Spacer(),
                  if (_gameOver)
                    const Text('🎉 全部收集完毕！', style: AppTextStyles.bodyMuted),
                  TextButton(onPressed: _restart, child: const Text('重新开始')),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    // 画布（共享 2.5D 渲染基础）
                    IgnorePointer(
                      child: VoxelCanvasView(
                        controller: _controller,
                        height: 320,
                        tileW: 46,
                        tileH: 28,
                      ),
                    ),
                    // 玩家方块（等距投影定位）
                    LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints c) {
                        final double tileW = 46;
                        final double tileH = 28;
                        final double offsetX = c.maxWidth / 2;
                        final double offsetY = 320 / 2 -
                            (_cols + _rows) * tileH / 4;
                        final double px =
                            (_playerCol - _playerRow) * tileW / 2 + offsetX;
                        final double py =
                            (_playerCol + _playerRow) * tileH / 2 + offsetY;
                        return Positioned(
                          left: px - 14,
                          top: py - 18,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.accent,
                              border: Border.all(
                                  color: AppColors.onAccent, width: 2),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: AppColors.accent,
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.navigation_rounded,
                              size: 16,
                              color: AppColors.onAccent,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              _buildDpad(),
              const SizedBox(height: AppSpace.sm),
              const Text(
                '方向键 / WASD 移动，碰到音效块即可收集',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDpad() {
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          switch (event.logicalKey) {
            case LogicalKeyboardKey.arrowUp:
            case LogicalKeyboardKey.keyW:
              _setDir(0, -1);
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowDown:
            case LogicalKeyboardKey.keyS:
              _setDir(0, 1);
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowLeft:
            case LogicalKeyboardKey.keyA:
              _setDir(-1, 0);
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowRight:
            case LogicalKeyboardKey.keyD:
              _setDir(1, 0);
              return KeyEventResult.handled;
            default:
              break;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _dpadButton(Icons.arrow_upward_rounded, () => _setDir(0, -1)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _dpadButton(Icons.arrow_left_rounded, () => _setDir(-1, 0)),
              const SizedBox(width: AppSpace.sm),
              _dpadButton(Icons.arrow_downward_rounded, () => _setDir(0, 1)),
              const SizedBox(width: AppSpace.sm),
              _dpadButton(Icons.arrow_right_rounded, () => _setDir(1, 0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dpadButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.bgSurfaceSunken,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: 56,
          height: 44,
          child: Icon(icon, size: AppSize.icon, color: AppColors.iconPrimary),
        ),
      ),
    );
  }
}
