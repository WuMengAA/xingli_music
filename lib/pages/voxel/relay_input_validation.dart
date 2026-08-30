/// ════════════════════════════════════════════════════════════════════════
/// 中转模式输入校验（cl79）：纯 Dart，无 Flutter 依赖，可单测。
///
/// 背景（记忆 2026-08-17 路线图②「修地址易填错」收尾）：此前中转模式
/// 无前端校验，错误直接透传 relay 英文文案（room required / room full）。
/// 本文件把「前置校验 + 英文错误 → 中文人话」抽成纯函数，供大厅页复用与回归保护。
/// ════════════════════════════════════════════════════════════════════════
library;

/// 中转模式前置校验：地址非空且为 `ws://` / `wss://` 前缀；
/// 加入模式房间号需 6 位（房主可留空，由会话层自动随机生成）。
///
/// 返回中文错误提示；合法返回 `null`。
String? validateRelayInput(String? url, String? room, {bool isHost = false}) {
  final String u = (url ?? '').trim();
  if (u.isEmpty) return '请输入中转服务器地址';
  if (!(u.startsWith('ws://') || u.startsWith('wss://'))) {
    return '中转地址需以 ws:// 或 wss:// 开头';
  }
  if (isHost) return null; // 房主房间号留空时自动随机生成
  final String r = (room ?? '').trim();
  if (r.isEmpty) return '请输入 6 位房间号';
  if (r.length != 6) return '房间号需为 6 位字母数字（如 ABC234）';
  return null;
}

/// 把中转服务器返回的错误（可能包裹在「连接失败：…」文案里）映射为中文人话提示。
/// 未识别也返回中文兜底（2026-08-17 定规：消息框不得出现成片英文），不再透传英文原文。
String? mapRelayErrorText(String? raw) {
  if (raw == null) return null;
  if (raw.contains('room full')) return '房间已满，请稍后再试或换一间';
  if (raw.contains('room required')) return '房间号无效，请确认房主提供的 6 位房间号';
  if (raw.contains('room exists')) return '房间号已被占用，请换一个房间号';
  if (raw.contains('wrong password')) return '密码错误，请确认后重试';
  if (raw.contains('room not found')) return '房间不存在或已结束，请确认房间号';
  return '连接中转服务器出错，请检查房间号与地址后重试';
}
