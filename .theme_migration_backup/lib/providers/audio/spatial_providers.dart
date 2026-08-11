import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/audio/spatial/spatial_mixer.dart';
import '../../services/audio/spatial/spatial_models.dart';

/// 空间音效调度器（全局单例）。
final Provider<SpatialMixer> spatialMixerProvider = Provider<SpatialMixer>(
  (ref) {
    final SpatialMixer mixer = SpatialMixer();
    ref.onDispose(mixer.dispose);
    return mixer;
  },
);

/// 当前声道布局（按设备能力；此处默认立体声，真机可探测后切换）。
final StateProvider<ChannelLayout> channelLayoutProvider =
    StateProvider<ChannelLayout>((ref) => ChannelLayout.stereo);

/// 内置空间音效示例（供 2.5D 编辑器 / 测试使用）。
///
/// - 水：3 轨（左/中/右水流），篝火：2 轨（底噪 + 噼啪）
abstract final class SpatialPresets {
  static const SpatialSound water = SpatialSound(
    id: 'water',
    name: '水',
    material: SoundMaterial.glass,
    tracks: <SpatialTrack>[
      SpatialTrack(id: 'w_l', channel: SpatialChannel.left, volume: 0.7, synthesisId: 'water'),
      SpatialTrack(id: 'w_c', channel: SpatialChannel.center, volume: 0.85, synthesisId: 'water'),
      SpatialTrack(id: 'w_r', channel: SpatialChannel.right, volume: 0.7, synthesisId: 'water'),
    ],
  );

  static const SpatialSound fireplace = SpatialSound(
    id: 'fireplace',
    name: '篝火',
    material: SoundMaterial.wood,
    tracks: <SpatialTrack>[
      SpatialTrack(id: 'f_bed', channel: SpatialChannel.center, volume: 0.8, synthesisId: 'fireplace'),
      SpatialTrack(id: 'f_crack', channel: SpatialChannel.front, volume: 0.6, synthesisId: 'fireplace'),
    ],
  );

  static const SpatialSound furnace = SpatialSound(
    id: 'furnace',
    name: '熔炉',
    material: SoundMaterial.metal,
    tracks: <SpatialTrack>[
      SpatialTrack(id: 'fu_hum', channel: SpatialChannel.center, volume: 0.75, synthesisId: 'furnace'),
      SpatialTrack(id: 'fu_glug', channel: SpatialChannel.back, volume: 0.5, synthesisId: 'furnace'),
    ],
  );
}
