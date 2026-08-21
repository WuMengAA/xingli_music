import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 主页面滚动磨砂边 · 进度 Provider（批3 #580 · A）
/// ════════════════════════════════════════════════════════════════════════
///
/// `AppShell` 在 `IndexedStack` 外包一层 `NotificationListener<ScrollNotification>`
/// 捕获「当前活动页」的滚动（滚动通知沿 widget 树冒泡，仅活动页在滚），
/// 把滚动像素换算成 0..1 进度写入本 provider；顶部/底部磨砂边条消费它，
/// 实现「滑动模糊过渡」——内容滑入/滑出边缘时磨砂条边随滚动淡入。
///
/// 切 Tab 时由 `AppShell` 复位为 0（新页尚未滚动时条边隐藏，保持干净视图）。
final pageScrollBlurProvider = StateProvider<double>((ref) => 0.0);

/// 滚动多少像素后磨砂边达到满强度（淡入阈值）。
const double kScrollBlurThreshold = 48.0;

/// 由滚动像素换算 0..1 进度（用于驱动磨砂边不透明度）。
double scrollBlurProgress(double pixels) =>
    (pixels / kScrollBlurThreshold).clamp(0.0, 1.0);
