// ════════════════════════════════════════════════════════════════════════
// 电台 relay 性能基准测试（dart:io WebSocket）。
// 覆盖电台自动化方案的性能目标：
//   - NF-1 同步窗口：DJ 广播 listenState → 听众收到的端到端延迟（弱网容忍 3s）
//   - NF-2 点歌往返：听众 orderSubmit → DJ orderDecision 的 RTT（局域网 <1s / relay <3s）
//   - 百人扇出：campus 房主广播到 100 听众的吞吐与尾延迟
// 运行：dart run tools/relay_server/benchmark_relay.dart [--uri ws://127.0.0.1:8092/ws]
//       [--clients N] [--rounds M]
// ════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:io';

String _uri = 'ws://127.0.0.1:8092/ws';
int _clients = 20; // 扇出/点歌并发听众数（campus 全量 100 可自行调大）
int _rounds = 50; // 扇出广播轮数

Future<WebSocket> connect() => WebSocket.connect(_uri);

/// 自建缓冲队列：持续订阅 socket，帧先进先出，可多次 take（与 test_room_protocol 一致）。
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

class _Stat {
  final List<int> samples = <int>[]; // 毫秒
  void add(int ms) => samples.add(ms);
  int get count => samples.length;
  double get mean => samples.isEmpty
      ? 0
      : samples.reduce((a, b) => a + b) / samples.length;
  int pct(int p) {
    if (samples.isEmpty) return 0;
    final List<int> s = List<int>.of(samples)..sort();
    return s[((s.length - 1) * p / 100).round()];
  }
  int get p50 => pct(50);
  int get p95 => pct(95);
  int get p99 => pct(99);
  int get max => samples.isEmpty ? 0 : _maxOf(samples);
  int get min => samples.isEmpty ? 0 : _minOf(samples);
}

int _maxOf(List<int> s) => s.reduce((a, b) => a > b ? a : b);
int _minOf(List<int> s) => s.reduce((a, b) => a < b ? a : b);

void _printStat(String label, _Stat st) {
  stdout.writeln(
      '  $label: n=${st.count}  min=${st.min}ms  p50=${st.p50}ms  '
      'p95=${st.p95}ms  p99=${st.p99}ms  max=${st.max}ms  mean=${st.mean.toStringAsFixed(1)}ms');
}

Future<void> _close(WebSocket ws) async {
  try {
    await ws.close();
  } catch (_) {}
}

Future<void> main(List<String> args) async {
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--uri' && i + 1 < args.length) _uri = args[++i];
    if (args[i] == '--clients' && i + 1 < args.length) {
      _clients = int.tryParse(args[++i]) ?? _clients;
    }
    if (args[i] == '--rounds' && i + 1 < args.length) {
      _rounds = int.tryParse(args[++i]) ?? _rounds;
    }
  }
  final String room =
      'BENCH${DateTime.now().millisecondsSinceEpoch % 100000}';
  stdout.writeln('基准: uri=$_uri room=$room clients=$_clients rounds=$_rounds');

  // ── 建房（host 端）─────────────────────────────────────────────
  final WebSocket host = await connect();
  final _Fifo qh = _Fifo(host);
  host.add(jsonEncode({
    'ctl': 'join', 'room': room, 'name': '基准房主', 'host': true,
    'public': false, 'mode': 'campus', 'capacity': 100,
  }));
  final Map<String, dynamic> readyH =
      jsonDecode(await qh.take()) as Map<String, dynamic>;
  if (readyH['ctl'] != 'ready') {
    stdout.writeln('建房失败: $readyH');
    exitCode = 1;
    return;
  }
  final String hostId = readyH['id'] as String;

  // ── 1) 并发加入延迟 ─────────────────────────────────────────────
  stdout.writeln('\n[1] 并发加入（${_clients} 听众同时 join）');
  final List<WebSocket> clients = <WebSocket>[];
  final List<_Fifo> qs = <_Fifo>[];
  final _Stat joinStat = _Stat();
  // 并发发起 join，逐个等 ready
  final List<Future<void>> joiners = <Future<void>>[];
  for (int i = 0; i < _clients; i++) {
    joiners.add(() async {
      final WebSocket c = await connect();
      final _Fifo q = _Fifo(c);
      final Stopwatch sw = Stopwatch()..start();
      c.add(jsonEncode({
        'ctl': 'join', 'room': room, 'name': '听众$i', 'host': false,
      }));
      final Map<String, dynamic> r =
          jsonDecode(await q.take()) as Map<String, dynamic>;
      sw.stop();
      if (r['ctl'] == 'ready') {
        clients.add(c);
        qs.add(q);
        joinStat.add(sw.elapsedMilliseconds);
      }
    }());
  }
  await Future.wait(joiners);
  _printStat('join→ready', joinStat);
  if (clients.isEmpty) {
    stdout.writeln('无客户端加入成功');
    await _close(host);
    exitCode = 1;
    return;
  }
  final int n = clients.length;
  stdout.writeln('  成功加入 $n / $_clients');

  // ── 2) 扇出广播（listenState 跟随，NF-1 同步窗口）───────────────
  stdout.writeln('\n[2] 扇出广播（host → $n 听众，$_rounds 轮 listenState）');
  final _Stat fanStat = _Stat(); // 每轮：host 发帧到所有听众都收到
  final List<_Stat> perClient = <_Stat>[
    for (int i = 0; i < n; i++) _Stat()
  ];
  // 每个听众一个读取协程，计收到时间
  final List<Future<void>> readers = <Future<void>>[];
  for (int i = 0; i < n; i++) {
    final int idx = i;
    readers.add(() async {
      for (int r = 0; r < _rounds; r++) {
        final Stopwatch sw = Stopwatch()..start();
        await qs[idx].take(); // listenState 信封（t=8）
        sw.stop();
        perClient[idx].add(sw.elapsedMilliseconds);
      }
    }());
  }
  for (int r = 0; r < _rounds; r++) {
    final Stopwatch sw = Stopwatch()..start();
    final int ts = DateTime.now().millisecondsSinceEpoch;
    host.add(jsonEncode({
      't': 8, // listenState
      'f': hostId,
      'p': <String, dynamic>{
        'uri': 'https://example.com/track$r.mp3',
        'title': '基准曲目$r',
        'artist': '基准歌手',
        'playing': true,
        'pos': 0,
      },
      // 附带发送时间戳供端到端精确测量
      '_ts': ts,
    }));
    // 本轮等所有听众收齐（读协程会各自计）——这里用一个小等待让帧送达
    await Future<void>.delayed(const Duration(milliseconds: 1));
    sw.stop();
    fanStat.add(sw.elapsedMilliseconds);
  }
  await Future.wait(readers);
  // 端到端：统一合并所有听众样本
  final _Stat e2e = _Stat();
  for (final _Stat s in perClient) {
    e2e.samples.addAll(s.samples);
  }
  _printStat('端到端 听众侧接收延迟（目标 p95≤3000ms）', e2e);

  // ── 3) 点歌往返（NF-2：听众 orderSubmit → DJ orderDecision）────────
  stdout.writeln('\n[3] 点歌往返（$n 听众同时提交 → 房主逐一审批回执）');
  final _Stat orderStat = _Stat();
  // 房主读取协程：每收到一条 orderSubmit(t=13) 就回 orderDecision(t=15)
  final List<Future<void>> hostReader = <Future<void>>[
    () async {
      for (int i = 0; i < n; i++) {
        final dynamic raw = await qh.take();
        final Map<String, dynamic> m =
            jsonDecode(raw as String) as Map<String, dynamic>;
        if ((m['t'] as int?) == 13) {
          final String fromId = m['f'] as String;
          host.add(jsonEncode({
            't': 15, // orderDecision
            'f': hostId,
            'to': fromId,
            'p': <String, dynamic>{'id': m['p']?['id'], 'decision': 'approve'},
          }));
        }
      }
    }()
  ];
  // 听众读取协程：收到 orderDecision 即计 RTT
  final List<Future<void>> orderReaders = <Future<void>>[];
  for (int i = 0; i < n; i++) {
    final int idx = i;
    orderReaders.add(() async {
      final Stopwatch sw = Stopwatch()..start();
      clients[idx].add(jsonEncode({
        't': 13, // orderSubmit
        'f': clients[idx].hashCode.toString(),
        'p': <String, dynamic>{
          'id': 'req$idx',
          'trackJson': <String, dynamic>{
            'title': '点歌$idx', 'artist': 'A', 'uri': 'https://e/$idx',
          },
        },
      }));
      await qs[idx].take(); // orderDecision 回执
      sw.stop();
      orderStat.add(sw.elapsedMilliseconds);
    }());
  }
  await Future.wait(orderReaders);
  await Future.wait(hostReader);
  _printStat('orderSubmit→orderDecision RTT（目标 p95≤3000ms）', orderStat);

  // ── 收尾 ───────────────────────────────────────────────────────
  for (final WebSocket c in clients) {
    await _close(c);
  }
  await _close(host);

  final bool pass = e2e.p95 <= 3000 && orderStat.p95 <= 3000;
  stdout.writeln('');
  stdout.writeln(pass
      ? '结果：基准通过（同步窗口 p95 ≤ 3s，点歌往返 p95 ≤ 3s）'
      : '结果：基准未达标（同步/点歌尾延迟超过 3s 目标）');
  exitCode = pass ? 0 : 1;
}
