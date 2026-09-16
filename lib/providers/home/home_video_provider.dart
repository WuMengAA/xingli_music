/// ════════════════════════════════════════════════════════════════════════
/// 主页沉浸播放器 · 视频背景设置
/// ════════════════════════════════════════════════════════════════════════
///
/// 用户需求：主页最底层用「哔站视频」做模糊背景，模糊强度可调，默认开启。
/// 这里仅存放三个可编辑的 Riverpod 状态；具体渲染见
/// [lib/widgets/playback/video_background.dart]。

library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 是否启用 Bilibili 视频背景（作为主页最底层背景层）。
///
/// 默认开启；关闭时 [VideoBackground] 直接返回 [SizedBox.shrink]，
/// 退回原来的纯色 / 音景动态背景。
final StateProvider<bool> homeVideoEnabledProvider =
    StateProvider<bool>((Ref<bool> ref) => true);

/// 视频背景模糊强度（像素 sigma），范围 0–40。
///
/// 0 表示完全不模糊；数值越大越朦胧。默认 18.0，介于「隐约可见」与
/// 「纯色氛围」之间，既能透出画面又不抢前景。
final StateProvider<double> homeVideoBlurProvider =
    StateProvider<double>((Ref<double> ref) => 18.0);

/// 默认 Bilibili 视频 BV 号（用户可编辑，未来可放进设置页）。
///
/// 默认选曲：雨声场景白噪音 / 清幽山林与泥土的雨天氛围助眠
/// （纯环境音、无剧烈画面，最适合做慢节奏模糊背景）。
const String _kDefaultBv = 'BV1FpqnBUEmv';

final StateProvider<String> homeVideoBvProvider =
    StateProvider<String>((Ref<String> ref) => _kDefaultBv);
