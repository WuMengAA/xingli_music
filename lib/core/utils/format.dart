/// 通用格式化工具（浅色 UI 层共享，无任何 Flutter 依赖）
library;

/// 把时长格式化为 `m:ss` / `h:mm:ss`。
///
/// [d] 为 null（电台直播流 / 元数据缺失）时返回 `--:--`。
String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final int totalSeconds = d.inSeconds;
  if (totalSeconds < 0) return '--:--';
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final String ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}
