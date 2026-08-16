import 'dart:io';
import 'package:xingli_music/services/ota/bspatch.dart';

void main() async {
  final dir = Directory.current.path + '/release';
  final base = '$dir/星璃音乐_0.26.8.15_alpha_cl76_hotfix4.apk';
  final patch = '$dir/cl76_hotfix4_to_hotfix6.patch';
  final out = '$dir/_verify_h6b_dart.apk';
  final f = File(out);
  if (f.existsSync()) f.deleteSync();
  await bspatch(base, out, patch);
  print('Dart synth done: ${File(out).lengthSync()} bytes');
}
