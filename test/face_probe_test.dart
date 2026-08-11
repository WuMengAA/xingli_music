import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../lib/widgets/voxel/voxel_camera.dart';
import '../lib/widgets/voxel/voxel_renderer.dart';
import '../lib/widgets/voxel/voxel_world.dart';

void main() {
  test('face probe', () {
    final VoxelWorld world = VoxelWorld();
    final VoxelCamera camera = VoxelCamera.overview(world);
    for (int i = 0; i < 5; i++) {
      final VoxelFrame f = VoxelRenderer.buildFrame(
        world: world, camera: camera, viewport: const Size(800, 500));
      debugPrint('run$i faceCount=${f.faceCount} cols=${f.columnsVisited} collected=${f.facesCollected}');
    }
  });
}
