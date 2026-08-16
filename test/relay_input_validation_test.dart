/// 中转模式输入校验（cl79）· 纯函数单测。
///
/// 覆盖：地址非空/前缀、房间号格式（房主可留空）、relay 英文错误 → 中文映射。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/pages/voxel/relay_input_validation.dart';

void main() {
  group('validateRelayInput（加入模式）', () {
    test('地址为空 → 提示输入地址', () {
      expect(validateRelayInput('', 'ABC234'), '请输入中转服务器地址');
      expect(validateRelayInput(null, 'ABC234'), '请输入中转服务器地址');
    });

    test('地址前缀非 ws(s):// → 提示前缀错误', () {
      expect(
        validateRelayInput('http://relay.xingli.app/ws', 'ABC234'),
        '中转地址需以 ws:// 或 wss:// 开头',
      );
      expect(
        validateRelayInput('ftp://x', 'ABC234'),
        '中转地址需以 ws:// 或 wss:// 开头',
      );
    });

    test('ws:// 与 wss:// 均合法', () {
      expect(validateRelayInput('ws://192.168.1.248:8765/ws', 'ABC234'), isNull);
      expect(validateRelayInput('wss://relay.xingli.app/ws', 'ABC234'), isNull);
    });

    test('房间号为空 / 非 6 位 → 提示', () {
      expect(validateRelayInput('ws://x/ws', ''), '请输入 6 位房间号');
      expect(validateRelayInput('ws://x/ws', 'AB3'), '房间号需为 6 位字母数字（如 ABC234）');
      expect(validateRelayInput('ws://x/ws', 'ABCD2345'), '房间号需为 6 位字母数字（如 ABC234）');
    });

    test('6 位房间号合法（含小写，大小写不敏感由调用方转大写）', () {
      expect(validateRelayInput('ws://x/ws', 'abc234'), isNull);
    });
  });

  group('validateRelayInput（房主模式：房间号可留空自动生成）', () {
    test('地址合法、房间号留空 → 合法', () {
      expect(
        validateRelayInput('ws://x/ws', '', isHost: true),
        isNull,
      );
    });

    test('地址非法仍报错', () {
      expect(
        validateRelayInput('', '', isHost: true),
        '请输入中转服务器地址',
      );
    });
  });

  group('mapRelayErrorText（relay 英文错误 → 中文人话）', () {
    test('room full → 房间已满', () {
      expect(mapRelayErrorText('room full'), '房间已满，请稍后再试或换一间');
    });

    test('room required → 房间号无效', () {
      expect(
        mapRelayErrorText('room required'),
        '房间号无效，请确认房主提供的 6 位房间号',
      );
    });

    test('包裹在连接失败文案里也能识别', () {
      expect(
        mapRelayErrorText('连接失败：Exception: room full'),
        '房间已满，请稍后再试或换一间',
      );
    });

    test('未识别错误 / null → null（沿用原文案）', () {
      expect(mapRelayErrorText('server exploded'), isNull);
      expect(mapRelayErrorText(null), isNull);
    });
  });
}
