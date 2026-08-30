// cl15 电台房间协议实测（dart:io WebSocket）。
// 运行：dart run tools/relay_server/test_room_protocol.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _uri = 'ws://127.0.0.1:8092/ws';

Future<WebSocket> connect() => WebSocket.connect(_uri);

/// 自建缓冲队列：持续订阅 socket，帧先进先出，可多次 take。
class _Fifo {
  final List<dynamic> _items = <dynamic>[];
  final List<Completer<dynamic>> _waiters = <Completer<dynamic>>[];

  _Fifo(Stream<dynamic> s) {
    s.listen(
      (dynamic d) {
        if (_waiters.isNotEmpty) {
          _waiters.removeAt(0).complete(d);
        } else {
          _items.add(d);
        }
      },
      onError: (Object e) {
        if (_waiters.isNotEmpty) _waiters.removeAt(0).completeError(e);
      },
    );
  }

  Future<dynamic> take() async {
    if (_items.isNotEmpty) return _items.removeAt(0);
    final Completer<dynamic> c = Completer<dynamic>();
    _waiters.add(c);
    return c.future;
  }
}

_Fifo _queue(WebSocket ws) => _Fifo(ws);

int _fail = 0;
void check(bool cond, String msg) {
  if (cond) {
    stdout.writeln('  [PASS] $msg');
  } else {
    stdout.writeln('  [FAIL] $msg');
    _fail++;
  }
}

Future<Map<String, dynamic>> _read(_Fifo q) async {
  final dynamic s =
      await q.take().timeout(const Duration(seconds: 3));
  return jsonDecode(s as String) as Map<String, dynamic>;
}

Future<void> closeQuiet(WebSocket ws, _Fifo q) async {
  try {
    await ws.close();
  } catch (_) {}
}

Future<void> main() async {
  // 1. 创建公开校园广播房
  stdout.writeln('1) 创建公开校园广播房 ABC123');
  final h1 = await connect();
  final q1 = _queue(h1);
  h1.add(jsonEncode({
    'ctl': 'join', 'room': 'ABC123', 'name': '房主甲',
    'host': true, 'public': true, 'mode': 'campus', 'capacity': 100,
  }));
  final r1 = await _read(q1);
  check(r1['ctl'] == 'ready' && r1['id'] != null, '公开房创建 → ready(id=${r1['id']})');
  final meta1 = r1['meta'] as Map<String, dynamic>;
  check(meta1['mode'] == 'campus' && meta1['capacity'] == 100 && meta1['public'] == true,
      'meta 正确(mode=campus,cap=100,public)');

  // 2. 加入公开房（无需密码），房主应收到 peerJoin
  stdout.writeln('2) 加入公开房 ABC123');
  final c1 = await connect();
  final q2 = _queue(c1);
  c1.add(jsonEncode({'ctl': 'join', 'room': 'ABC123', 'name': '听众乙', 'host': false}));
  final r2 = await _read(q2);
  check(r2['ctl'] == 'ready', '公开房加入 → ready');
  final j1 = await _read(q1); // 房主缓冲里应有 peerJoin
  check(j1['ctl'] == 'peerJoin', '房主收到 peerJoin');

  // 3. 公开房间列表
  stdout.writeln('3) GET /api/rooms');
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse('http://127.0.0.1:8092/api/rooms'));
  final resp = await req.close();
  final body = jsonDecode(await resp.transform(utf8.decoder).join()) as Map<String, dynamic>;
  final rooms = (body['rooms'] as List).cast<Map<String, dynamic>>();
  check(rooms.isNotEmpty, '公开列表 ≥1 房');
  final abc = rooms.firstWhere((r) => r['code'] == 'ABC123', orElse: () => const {});
  check(abc.isNotEmpty && abc['members'] == 2 && abc['public'] == true,
      '列表含 ABC123(members=2)');

  // 4. 创建私密房（带密码 listen 5人）
  stdout.writeln('4) 创建私密房 XYZ999(密码 ab12)');
  final h2 = await connect();
  final q4 = _queue(h2);
  h2.add(jsonEncode({
    'ctl': 'join', 'room': 'XYZ999', 'name': '房主丙', 'host': true,
    'public': false, 'mode': 'listen', 'capacity': 5, 'password': 'ab12',
  }));
  final r4 = await _read(q4);
  check(r4['ctl'] == 'ready', '私密房创建 → ready');
  final meta4 = r4['meta'] as Map<String, dynamic>;
  check(meta4['capacity'] == 5 && meta4['public'] == false, 'meta 正确(listen,cap=5,private)');

  // 5. 错误密码加入
  stdout.writeln('5) 错误密码加入');
  final c2 = await connect();
  final q5 = _queue(c2);
  c2.add(jsonEncode({'ctl': 'join', 'room': 'XYZ999', 'name': '某人', 'host': false, 'password': 'wrong'}));
  final r5 = await _read(q5);
  check(r5['ctl'] == 'error' && r5['msg'] == 'wrong password', '错误密码 → error(wrong password)');

  // 6. 正确密码加入
  stdout.writeln('6) 正确密码加入');
  final c3 = await connect();
  final q6 = _queue(c3);
  c3.add(jsonEncode({'ctl': 'join', 'room': 'XYZ999', 'name': '某人', 'host': false, 'password': 'ab12'}));
  final r6 = await _read(q6);
  check(r6['ctl'] == 'ready', '正确密码 → ready');

  // 7. 私密房不在公开列表
  stdout.writeln('7) 私密房不出现在公开列表');
  final req2 = await client.getUrl(Uri.parse('http://127.0.0.1:8092/api/rooms'));
  final resp2 = await req2.close();
  final body2 = jsonDecode(await resp2.transform(utf8.decoder).join()) as Map<String, dynamic>;
  final rooms2 = (body2['rooms'] as List).cast<Map<String, dynamic>>();
  check(!rooms2.any((r) => r['code'] == 'XYZ999'), '私密房不在公开列表');

  // 8. 重复创建同号 → room exists
  stdout.writeln('8) 重复创建同号 ABC123');
  final h3 = await connect();
  final q8 = _queue(h3);
  h3.add(jsonEncode({'ctl': 'join', 'room': 'ABC123', 'name': '抢号', 'host': true, 'public': true, 'mode': 'campus', 'capacity': 100}));
  final r8 = await _read(q8);
  check(r8['ctl'] == 'error' && r8['msg'] == 'room exists', '重复创建 → error(room exists)');

  // 9. 不存在的房间加入 → room not found
  stdout.writeln('9) 加入不存在房间');
  final c4 = await connect();
  final q9 = _queue(c4);
  c4.add(jsonEncode({'ctl': 'join', 'room': 'NOPE00', 'name': '路人', 'host': false}));
  final r9 = await _read(q9);
  check(r9['ctl'] == 'error' && r9['msg'] == 'room not found', '不存在 → error(room not found)');

  client.close(force: true);
  await closeQuiet(h1, q1);
  await closeQuiet(c1, q2);
  await closeQuiet(h2, q4);
  await closeQuiet(c2, q5);
  await closeQuiet(c3, q6);
  await closeQuiet(h3, q8);
  await closeQuiet(c4, q9);

  stdout.writeln('');
  if (_fail > 0) {
    stdout.writeln('结果：$_fail 项失败');
    exitCode = 1;
  } else {
    stdout.writeln('结果：全部通过');
  }
}
