import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/services/audio/spatial/spatial_models.dart';
import 'package:xingli_music/services/audio/spatial/spatial_synth.dart';

void main() {
  group('Spatial · 空间音效引擎', () {
    test('音轨数量上限 4，空音轨非法', () {
      const SpatialSound ok = SpatialSound(
        id: 'a',
        name: 'A',
        tracks: <SpatialTrack>[
          SpatialTrack(id: 't1', channel: SpatialChannel.center),
          SpatialTrack(id: 't2', channel: SpatialChannel.left),
          SpatialTrack(id: 't3', channel: SpatialChannel.right),
          SpatialTrack(id: 't4', channel: SpatialChannel.back),
        ],
      );
      expect(ok.valid, isTrue);
      expect(SpatialSound.maxTracks, 4);

      const SpatialSound empty = SpatialSound(id: 'b', name: 'B', tracks: <SpatialTrack>[]);
      expect(empty.valid, isFalse);
    });

    test('声道增益：单声道降级为 L=R=1', () {
      const SpatialTrack t = SpatialTrack(id: 't', channel: SpatialChannel.left);
      final ChannelGains mono = t.gainsFor(ChannelLayout.mono);
      expect(mono.left, 1);
      expect(mono.right, 1);

      final ChannelGains stereo = t.gainsFor(ChannelLayout.stereo);
      expect(stereo.left, greaterThan(stereo.right), reason: '左声道偏左');
    });

    test('材料隔音：羊毛吸音项远大于石质（吸收主导）', () {
      final double wool = transmissionLoss(SoundMaterial.wool, 3);
      final double stone = transmissionLoss(SoundMaterial.stone, 3);
      // 石质 Rw 高（隔音主导），羊毛 Rw 低但吸音极佳；
      // 断言：羊毛的吸收分量贡献显著
      final MaterialAcoustics woolA = MaterialAcoustics.of(SoundMaterial.wool);
      final MaterialAcoustics stoneA = MaterialAcoustics.of(SoundMaterial.stone);
      expect(woolA.absorption, greaterThan(0.7));
      expect(stoneA.absorption, lessThan(0.1));
      expect(woolA.rwDb, lessThan(stoneA.rwDb));
      // 且隔墙越多，两种材料衰减都增大（单调）
      expect(transmissionLoss(SoundMaterial.wool, 6), greaterThan(wool));
      expect(transmissionLoss(SoundMaterial.stone, 6), greaterThan(stone));
    });

    test('隔墙越多衰减越大（单调）', () {
      final double w1 = transmissionLoss(SoundMaterial.metal, 1);
      final double w3 = transmissionLoss(SoundMaterial.metal, 3);
      expect(w3, greaterThan(w1));
      expect(dbToGain(w3), lessThan(dbToGain(w1)));
    });

    test('水方块流动：无障碍物时覆盖曼哈顿距离 ≤9 的菱形', () {
      final Set<(int, int)> reachable = waterFlow(
        0,
        0,
        (x, y) => false,
      );
      // 曼哈顿距离 ≤9 的格数 = 1 + 4×(1+2+...+9) = 181
      const int diamond = 1 + 4 * 45;
      expect(reachable.length, diamond);
      expect(reachable.contains((0, 0)), isTrue);
      expect(reachable.contains((9, 0)), isTrue);
      expect(reachable.contains((-9, 0)), isTrue);
      expect(reachable.contains((0, 9)), isTrue);
      expect(reachable.contains((0, -9)), isTrue);
      // 超过 9 格的不可达
      expect(reachable.contains((10, 0)), isFalse);
      expect(reachable.contains((9, 9)), isFalse, reason: '对角线距离 18 > 9');
    });

    test('水方块流动：有障碍物时被阻断', () {
      // 右侧 (1,0) 是墙 → 右路不通，但其它方向可达
      final Set<(int, int)> reachable = waterFlow(
        0,
        0,
        (x, y) => x == 1 && y == 0,
      );
      expect(reachable.contains((0, 0)), isTrue);
      expect(reachable.contains((1, 0)), isFalse);
      expect(reachable.contains((-9, 0)), isTrue, reason: '左路不受阻');
      expect(reachable.contains((0, 9)), isTrue, reason: '上/下路不受阻');
    });

    test('合成器：water/fireplace/furnace 输出合法 WAV', () {
      for (final String id in <String>['water', 'fireplace', 'furnace']) {
        final wav = SpatialSynth.synthesizeWav(id, seed: 42);
        expect(wav.length, greaterThan(44), reason: 'WAV 头 + 数据');
        // RIFF 头
        expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      }
    });
  });
}
