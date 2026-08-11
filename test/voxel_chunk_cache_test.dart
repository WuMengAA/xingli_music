import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../lib/widgets/voxel/voxel_camera.dart';
import '../lib/widgets/voxel/voxel_renderer.dart';
import '../lib/widgets/voxel/voxel_world.dart';

void main() {
  group('VoxelChunkCache 直接语义', () {
    test('put / get / clear / invalidate', () {
      final VoxelChunkCache cache = VoxelChunkCache();
      final ChunkMesh m = ChunkMesh(<CachedFace>[], 7);
      cache.put(3, 5, 0, m);
      expect(cache.get(3, 5, 0), same(m));
      expect(cache.get(3, 5, 1), isNull); // 不同 lod → 未命中

      cache.invalidate(3, 5); // 删该 chunk 所有 lod
      expect(cache.get(3, 5, 0), isNull);

      cache.put(1, 1, 0, m);
      cache.clear();
      expect(cache.get(1, 1, 0), isNull);
    });

    test('LRU 容量上限：超额淘汰最老', () {
      final VoxelChunkCache cache = VoxelChunkCache(maxChunks: 4);
      final ChunkMesh m = ChunkMesh(<CachedFace>[], 1);
      for (int i = 0; i < 6; i++) {
        cache.put(i, 0, 0, m);
      }
      // 6 个写入、容量 4 → 最老的 0,1 被淘汰。
      expect(cache.get(0, 0, 0), isNull);
      expect(cache.get(1, 0, 0), isNull);
      expect(cache.get(5, 0, 0), isNotNull);
    });
  });

  group('VoxelChunkCache（R23s 区块几何缓存）集成', () {
    test('无缓存时 hits/misses 均为 0', () {
      final VoxelWorld world = VoxelWorld();
      final VoxelCamera camera = VoxelCamera.overview(world);
      final VoxelFrame f = VoxelRenderer.buildFrame(
        world: world,
        camera: camera,
        viewport: const Size(800, 500),
        cache: null,
        // R26f：测试锁缓存语义，分帧预算给极大值（生产默认 4 由配置控制）
        config: const RenderConfig(maxChunkBuildsPerFrame: 9999),
      );
      expect(f.chunkHits, 0);
      expect(f.chunkMisses, 0);
      expect(f.faceCount, greaterThan(0));
    });

    test('同相机两帧：第二帧命中且面数与首帧一致（缓存等价）', () {
      final VoxelWorld world = VoxelWorld();
      final VoxelCamera camera = VoxelCamera.overview(world);
      final VoxelChunkCache cache = VoxelChunkCache();

      final VoxelFrame f1 = VoxelRenderer.buildFrame(
        world: world,
        camera: camera,
        viewport: const Size(800, 500),
        cache: cache,
        // R26f：测试锁缓存语义，分帧预算给极大值（生产默认 4 由配置控制）
        config: const RenderConfig(maxChunkBuildsPerFrame: 9999),
      );
      final VoxelFrame f2 = VoxelRenderer.buildFrame(
        world: world,
        camera: camera,
        viewport: const Size(800, 500),
        cache: cache,
        // R26f：测试锁缓存语义，分帧预算给极大值（生产默认 4 由配置控制）
        config: const RenderConfig(maxChunkBuildsPerFrame: 9999),
      );

      // 首帧全未命中、第二帧有命中。
      expect(f1.chunkHits, 0);
      expect(f1.chunkMisses, greaterThan(0));
      expect(f2.chunkHits, greaterThan(0));

      // 缓存几何与首帧输出等价：面数一致。
      expect(f2.faceCount, f1.faceCount);
      expect(f2.columnsVisited, f1.columnsVisited);
    });

    test('clear 后下一次构建重新未命中（至少部分重建）', () {
      final VoxelWorld world = VoxelWorld();
      final VoxelCamera camera = VoxelCamera.overview(world);
      final VoxelChunkCache cache = VoxelChunkCache();

      final VoxelFrame f1 = VoxelRenderer.buildFrame(
        world: world,
        camera: camera,
        viewport: const Size(800, 500),
        cache: cache,
        // R26f：测试锁缓存语义，分帧预算给极大值（生产默认 4 由配置控制）
        config: const RenderConfig(maxChunkBuildsPerFrame: 9999),
      );
      cache.clear();
      final VoxelFrame f2 = VoxelRenderer.buildFrame(
        world: world,
        camera: camera,
        viewport: const Size(800, 500),
        cache: cache,
        // R26f：测试锁缓存语义，分帧预算给极大值（生产默认 4 由配置控制）
        config: const RenderConfig(maxChunkBuildsPerFrame: 9999),
      );
      // 清空后第二帧至少重新生成了部分区块（未命中 > 0）。
      expect(f2.chunkMisses, greaterThan(0));
      // 且面数仍与首帧一致（几何确定性）。
      expect(f2.faceCount, f1.faceCount);
    });

    test('相机小幅平移后几何大量复用（同 lod）：命中率仍高', () {
      final VoxelWorld world = VoxelWorld();
      final VoxelChunkCache cache = VoxelChunkCache();
      final VoxelCamera c1 = VoxelCamera.overview(world);
      final VoxelCamera c2 = c1.move(forward: 2, world: world);

      VoxelRenderer.buildFrame(
        world: world,
        camera: c1,
        viewport: const Size(800, 500),
        cache: cache,
        // R26f：测试锁缓存语义，分帧预算给极大值（生产默认 4 由配置控制）
        config: const RenderConfig(maxChunkBuildsPerFrame: 9999),
      );
      final VoxelFrame f2 = VoxelRenderer.buildFrame(
        world: world,
        camera: c2,
        viewport: const Size(800, 500),
        cache: cache,
        // R26f：测试锁缓存语义，分帧预算给极大值（生产默认 4 由配置控制）
        config: const RenderConfig(maxChunkBuildsPerFrame: 9999),
      );
      // 仅窗口边缘少量 chunk 因进入视野变化而重建，大部分命中。
      expect(f2.chunkHits, greaterThan(f2.chunkMisses));
    });
  });
}
