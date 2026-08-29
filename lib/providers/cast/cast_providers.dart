import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/cast/cast_stream_server.dart';

/// 投屏服务 UI 状态。
class CastUiState {
  const CastUiState({
    this.running = false,
    this.port = CastStreamServer.defaultPort,
    this.ips = const <String>[],
  });

  final bool running;
  final int port;
  final List<String> ips;

  CastUiState copyWith({bool? running, int? port, List<String>? ips}) =>
      CastUiState(
        running: running ?? this.running,
        port: port ?? this.port,
        ips: ips ?? this.ips,
      );

  /// 生成「打开网页播端」的完整地址（携带当前曲目 uri）。
  List<String> entryUrls(String? currentUri) {
    final String base = ips.isEmpty
        ? 'http://<本机IP>:$port'
        : 'http://${ips.first}:$port';
    if (currentUri == null || currentUri.isEmpty) {
      return <String>[base];
    }
    final String enc =
        Uri.encodeComponent(currentUri).replaceAll('%2F', '/').replaceAll('%3A', ':');
    return <String>[
      '$base/?uri=$enc',
      '$base/track?uri=$enc',
    ];
  }
}

/// 投屏服务控制器：启停 + 端口 + 本机 IP 列表。
class CastServerController extends StateNotifier<CastUiState> {
  CastServerController() : super(const CastUiState());

  bool _busy = false;

  Future<void> toggle() async {
    if (_busy) return;
    _busy = true;
    try {
      final CastStreamServer srv = CastStreamServer.instance;
      if (state.running) {
        await srv.stop();
        state = state.copyWith(running: false);
      } else {
        final int port = await srv.start();
        final List<String> ips = await srv.localIPv4();
        state = state.copyWith(running: true, port: port, ips: ips);
      }
    } finally {
      _busy = false;
    }
  }
}

final castServerProvider =
    StateNotifierProvider<CastServerController, CastUiState>(
  (ref) => CastServerController(),
);