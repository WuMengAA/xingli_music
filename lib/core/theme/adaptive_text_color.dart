/// ════════════════════════════════════════════════════════════════════════
/// 字体背景颜色自适应：根据背景色亮度自动选择可读的前景色。
///
/// 适用场景：文字 / 图标叠放在**运行时可变背景色**上（玩家名标签底色、
/// 用户自定义色块、封面染色区等）——底亮用深字、底暗用浅字，保证对比度。
///
/// 判定依据：WCAG 2.1 相对亮度（[Color.computeLuminance]），阈值 0.5。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:ui' show Color;

/// 依据背景色亮度返回可读前景色。
///
/// [background] 为叠文字的实际底色（不含透明度的最终混合色）；
/// [light] / [dark] 分别是在暗底 / 亮底上使用的前景色，默认白 / 深灰黑。
Color adaptiveForeground(
  Color background, {
  Color light = const Color(0xFFFFFFFF),
  Color dark = const Color(0xFF1C1C1E),
}) =>
    background.computeLuminance() > 0.5 ? dark : light;