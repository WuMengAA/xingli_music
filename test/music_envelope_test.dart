/// MusicEnvelope 序列化 / 采样单元测试（Module "MusicViz-2.5D" · A）。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/services/audio/music_envelope.dart';

void main() {
  group('encode/decode 往返', () {
    test('字段与数值完全一致', () {
      final Float32List bands = Float32List(4 * 2);
      for (int i = 0; i < bands.length; i++) {
        bands[i] = (i % 5) * 0.2;
      }
      final Float32List beat = Float32List(4)
        ..[0] = 0.1
        ..[1] = 0.5
        ..[2] = 0.9
        ..[3] = 0.3;
      final MusicEnvelope env = MusicEnvelope(
        durationMs: 2000,
        fps: 2,
        bandCount: 2,
        bands: bands,
        beat: beat,
      );

      final Uint8List bytes = env.encode();
      final MusicEnvelope? dec = MusicEnvelope.decode(bytes);

      expect(dec, isNotNull);
      dec!;
      expect(dec.durationMs, 2000);
      expect(dec.fps, 2);
      expect(dec.bandCount, 2);
      expect(dec.frameCount, 4);
      for (int i = 0; i < bands.length; i++) {
        expect(dec.bands[i], closeTo(bands[i], 1e-5));
      }
      for (int i = 0; i < beat.length; i++) {
        expect(dec.beat[i], closeTo(beat[i], 1e-5));
      }
    });

    test('损坏 / 过短数据返回 null（不抛）', () {
      expect(MusicEnvelope.decode(Uint8List.fromList(<int>[1, 2, 3])), isNull);
      expect(MusicEnvelope.decode(Uint8List(0)), isNull);
    });
  });

  group('采样插值', () {
    // frame0: band0=0 band1=0 ; frame1: band0=1 band1=1 。fps=2 → frameMs=500。
    final MusicEnvelope env = MusicEnvelope(
      durationMs: 1000,
      fps: 2,
      bandCount: 2,
      bands: Float32List.fromList(<double>[0, 0, 1, 1]),
      beat: Float32List.fromList(<double>[0.0, 1.0]),
    );

    test('sampleBands 帧边界与中点插值', () {
      expect(env.sampleBands(0), <double>[0, 0]);
      expect(env.sampleBands(500), <double>[1, 1]);
      // ms=250 → t=0.5 → 两帧均值 [0.5, 0.5]
      final List<double> mid = env.sampleBands(250);
      expect(mid[0], closeTo(0.5, 1e-6));
      expect(mid[1], closeTo(0.5, 1e-6));
    });

    test('sampleBeat 插值', () {
      expect(env.sampleBeat(0), closeTo(0.0, 1e-6));
      expect(env.sampleBeat(500), closeTo(1.0, 1e-6));
      expect(env.sampleBeat(250), closeTo(0.5, 1e-6));
    });

    test('sampleBands 越界 clamp', () {
      expect(env.sampleBands(-100), <double>[0, 0]);
      expect(env.sampleBands(99999), <double>[1, 1]);
    });

    test('sampleLevel 为各频段均值', () {
      // 帧0 全 0 → 0；帧1 全 1 → 1；中点 → 0.5
      expect(env.sampleLevel(0), closeTo(0.0, 1e-6));
      expect(env.sampleLevel(250), closeTo(0.5, 1e-6));
      expect(env.sampleLevel(500), closeTo(1.0, 1e-6));
    });
  });
}
