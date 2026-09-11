import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/audio/visualizer_providers.dart';

/// 频谱条可视化（消费 [visualizerBandsProvider] 的 16 段合成能量）。
///
/// 数据源：播放进度 + 时长 + 播放态经节奏包络模型合成的「音乐反应」层
/// （[VisualizerService]）。非真实 FFT，但随播放「活」起来，契合「意境优先」。
///
/// 在 now_playing 页挂载即启动该服务，离页自动释放（provider 生命周期）。
class SpectrumBars extends ConsumerWidget {
  const SpectrumBars({super.key, this.height = 48, this.maxBars});

  /// 条带最大高度（逻辑像素）。
  final double height;

  /// 显示条数上限（默认取数据源分辨率 16 段）。
  final int? maxBars;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<double>> bands = ref.watch(visualizerBandsProvider);
    final AppThemeColors c = context.appColors;
    return SizedBox(
      height: height,
      child: bands.when(
        data: (List<double> vals) {
          final int n = maxBars ?? vals.length;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List<Widget>.generate(n, (int i) {
              final double v = i < vals.length ? vals[i].clamp(0.0, 1.0) : 0.0;
              final double h = (3 + v * (height - 3)).clamp(2.0, height);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 70),
                    curve: Curves.easeOut,
                    height: h,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[
                          c.accent.withValues(alpha: 0.95),
                          c.accent.withValues(alpha: 0.30),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
        loading: () => _IdleBars(height: height, color: c.accent),
        error: (_, __) => _IdleBars(height: height, color: c.accent),
      ),
    );
  }
}

/// 静态占位条（无数据 / 未播放时）。
class _IdleBars extends StatelessWidget {
  const _IdleBars({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(16, (int i) {
          // 轻微起伏，避免完全平直的死板感。
          final double h = 3 + ((i * 7) % 5).toDouble();
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: color.withValues(alpha: 0.22),
                ),
              ),
            ),
          );
        }),
      );
}
