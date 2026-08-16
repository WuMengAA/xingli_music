/// ════════════════════════════════════════════════════════════════════════
/// 16×16 体素纹理图集（R24c）
/// ════════════════════════════════════════════════════════════════════════
///
/// 每个方块类型对应图集里一格 16×16 像素画瓦片，逐像素程序化生成
/// （基色 + 确定性抖动 + 块种花纹）。渲染时通过 [tileUV] 把面四边形映射到
/// 对应瓦片，走 GPU `drawVertices` 贴图（不拖 CPU）。
///
/// 仅生成一次（[build]），结果 [ui.Image] 跨世界复用。
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'voxel_world_types.dart';

class VoxelTextureAtlas {
  VoxelTextureAtlas._();

  /// 单瓦片像素边长（MC 惯例 16×16）。
  static const int tile = 16;

  /// 图集列数（足够容纳全部枚举值，多余格留空）。
  static const int cols = 8;

  /// 皮肤图（MC 2×，128×128 RGBA）烘焙区域：图集在体素瓦片下方追加 128×128。
  /// 与地形共用同一张 [ui.Image]，实体面以图集像素 UV 采样，免去第二纹理。
  static const int skinW = 128;
  static int _skinExtraH = 0;
  static double _skinOx = 0;
  static double _skinOy = 0;
  static double _skinScale = 2; // 皮肤图宽 / 64（2× → 2）
  static bool _hasSkin = false;

  static int get rows =>
      ((Voxel.values.length * kVoxelVariantSlots + cols - 1) / cols).ceil();

  static int get width => math.max(cols * tile, skinW);

  static int get height => rows * tile + _skinExtraH;

  /// 是否已烘焙皮肤（加载/解码失败则为 false，实体回退纯色）。
  static bool get hasSkin => _hasSkin;

  /// 返回某方块瓦片在图集中的 UV（图集像素坐标，角序对齐 [_fillCorners]：
  /// 0=(minX,minZ) 1=(maxX,minZ) 2=(maxX,maxZ) 3=(minX,maxZ)）。
  static Float32List tileUV(int index, [int variant = 0]) {
    final int slot =
        index * kVoxelVariantSlots + variant.clamp(0, kVoxelVariantSlots - 1);
    final int col = slot % cols;
    final int row = slot ~/ cols;
    final double x0 = (col * tile).toDouble();
    final double y0 = (row * tile).toDouble();
    final double x1 = x0 + tile;
    final double y1 = y0 + tile;
    return Float32List.fromList(<double>[
      x0, y0, //
      x1, y0, //
      x1, y1, //
      x0, y1, //
    ]);
  }

  /// 构建图集图像（异步：PictureRecorder → toImage）。
  ///
  /// [skinBytes] 为可选 MC 2× 皮肤 PNG；非空则解码后烘焙到图集下方 128×128 区域，
  /// 实体面经 [skinRectFor] 取该区域 UV 采样。解码失败安全回退（无皮肤）。
  static Future<ui.Image?> build({Uint8List? skinBytes}) async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(rec);
    _hasSkin = false;
    _skinExtraH = 0;
    final int n = Voxel.values.length;
    for (int i = 0; i < n; i++) {
      final Voxel v = Voxel.values[i];
      final int vc = variantCountOf(v);
      for (int k = 0; k < kVoxelVariantSlots; k++) {
        final int slot = i * kVoxelVariantSlots + k;
        // 超出实际变体数的槽位复用变体 0（永不采样，仅占位避免空洞）。
        _drawTile(canvas, slot % cols, slot ~/ cols, v, k < vc ? k : 0);
      }
    }
    if (skinBytes != null) {
      try {
        final ui.Codec codec = await ui.instantiateImageCodec(skinBytes);
        final ui.Image skin = (await codec.getNextFrame()).image;
        _skinOx = 0;
        _skinOy = rows * tile.toDouble();
        _skinScale = skin.width / 64.0;
        _skinExtraH = skin.height;
        canvas.drawImageRect(
          skin,
          ui.Rect.fromLTWH(0, 0, skin.width.toDouble(), skin.height.toDouble()),
          ui.Rect.fromLTWH(
              _skinOx, _skinOy, skin.width.toDouble(), skin.height.toDouble()),
          ui.Paint(),
        );
        skin.dispose();
        _hasSkin = true;
      } catch (_) {
        _hasSkin = false;
        _skinExtraH = 0;
      }
    }
    final ui.Picture pic = rec.endRecording();
    final ui.Image raw = await pic.toImage(width, height);
    // R26x：经原始 RGBA 像素重新解码，得到跨渲染后端（含 Impeller/D3D11）
    // 可靠采样的位图。直接以 PictureRecorder 图像作 ImageShader 源在 Impeller
    // 下会整批采样为黑（用户反馈「默认画质全黑方块」），重解码后修复。
    final ByteData? rgba =
        await raw.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      raw.dispose();
      return null; // 极端回退：视图回落纯色
    }
    raw.dispose();
    // R26r34：跨后端可靠采样——把 RGBA 像素手编为 32 位 BMP，再经
    // [ui.instantiateImageCodec] 解码（与皮肤图同路径）。直接以 PictureRecorder 图
    // 或 [ui.decodeImageFromPixels] 的 GPU 图作 ImageShader 源在 Impeller/D3D11 下
    // 会整批采样为黑（用户报「高清档方块黑」）；codec 解码图 Impeller 可正常采样。
    // 手编 BMP 避开额外依赖与平台编解码差异，逻辑完全自控。
    try {
      final Uint8List src =
          rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
      final int stride = width * 4;
      final int pixelBytes = stride * height;
      final int fileSize = 54 + pixelBytes;
      final ByteData bmp = ByteData(fileSize);
      int o = 0;
      // ── BITMAPFILEHEADER（14B）──
      bmp.setUint8(o++, 0x42); // 'B'
      bmp.setUint8(o++, 0x4D); // 'M'
      bmp.setUint32(o, fileSize, Endian.little);
      o += 4;
      bmp.setUint32(o, 0, Endian.little);
      o += 4; // reserved
      bmp.setUint32(o, 54, Endian.little);
      o += 4; // pixel data offset
      // ── BITMAPINFOHEADER（40B, BI_RGB）──
      bmp.setUint32(o, 40, Endian.little);
      o += 4; // header size
      bmp.setUint32(o, width, Endian.little);
      o += 4;
      bmp.setUint32(o, height, Endian.little);
      o += 4; // 正高 = 自下而上
      bmp.setUint16(o, 1, Endian.little);
      o += 2; // planes
      bmp.setUint16(o, 32, Endian.little);
      o += 2; // bpp
      bmp.setUint32(o, 0, Endian.little);
      o += 4; // compression = 0
      bmp.setUint32(o, pixelBytes, Endian.little);
      o += 4; // image size
      bmp.setUint32(o, 0, Endian.little);
      o += 4; // xppm
      bmp.setUint32(o, 0, Endian.little);
      o += 4; // yppm
      bmp.setUint32(o, 0, Endian.little);
      o += 4; // colors used
      bmp.setUint32(o, 0, Endian.little);
      o += 4; // colors important
      // ── 像素：自下而上、BGR(A) ──
      for (int y = height - 1; y >= 0; y--) {
        int s = y * stride;
        for (int x = 0; x < width; x++) {
          bmp.setUint8(o++, src[s + 2]); // B
          bmp.setUint8(o++, src[s + 1]); // G
          bmp.setUint8(o++, src[s + 0]); // R
          bmp.setUint8(o++, src[s + 3]); // A
          s += 4;
        }
      }
      final ui.Codec codec =
          await ui.instantiateImageCodec(bmp.buffer.asUint8List(0, fileSize));
      final ui.Image decoded = (await codec.getNextFrame()).image;
      return decoded;
    } catch (_) {
      return null; // 解码失败回落纯色（无害、无黑块）
    }
  }

  /// MC 2× 皮肤各部位 6 面在 64×64 基准图中的像素矩形 [x,y,w,h]。
  /// 仅用于 2× 单图层皮肤；面索引对齐 [BlockFace] 序：0=top 1=bottom
  /// 2=north 3=south 4=west 5=east（south=正面+Z / north=背面 / east=右+X / west=左）。
  static const Map<String, Map<int, List<double>>> _skinLayout =
      <String, Map<int, List<double>>>{
    'head': <int, List<double>>{
      0: <double>[8, 0, 8, 8],
      1: <double>[16, 0, 8, 8],
      3: <double>[8, 8, 8, 8], // 正面（脸）
      2: <double>[24, 8, 8, 8],
      5: <double>[0, 8, 8, 8],
      4: <double>[16, 8, 8, 8],
    },
    'torso': <int, List<double>>{
      0: <double>[20, 16, 8, 4],
      1: <double>[28, 16, 8, 4],
      3: <double>[20, 20, 8, 12],
      2: <double>[32, 20, 8, 12],
      5: <double>[16, 20, 4, 12],
      4: <double>[24, 20, 4, 12],
    },
    'armL': <int, List<double>>{
      0: <double>[44, 16, 4, 4],
      1: <double>[48, 16, 4, 4],
      3: <double>[44, 20, 4, 12],
      2: <double>[48, 20, 4, 12],
      5: <double>[40, 20, 4, 12],
      4: <double>[52, 20, 4, 12],
    },
    'armR': <int, List<double>>{
      // R26r12：armR = 左臂（+X）→ 用 64×64 新版「左臂」区域 (32,48)…；
      // 此前误用右臂区 (44,16)…，贴图错位/镜像。
      0: <double>[32, 48, 4, 4],
      1: <double>[36, 48, 4, 4],
      3: <double>[36, 52, 4, 12],
      2: <double>[44, 52, 4, 12],
      5: <double>[32, 52, 4, 12],
      4: <double>[40, 52, 4, 12],
    },
    'legL': <int, List<double>>{
      0: <double>[4, 16, 4, 4],
      1: <double>[8, 16, 4, 4],
      3: <double>[4, 20, 4, 12],
      2: <double>[12, 20, 4, 12],
      5: <double>[0, 20, 4, 12],
      4: <double>[8, 20, 4, 12],
    },
    'legR': <int, List<double>>{
      // R26r12：顶/底修正为 64×64 左腿区 (16,48)/(20,48)（此前偏移 4px）。
      0: <double>[16, 48, 4, 4],
      1: <double>[20, 48, 4, 4],
      3: <double>[20, 52, 4, 12],
      2: <double>[28, 52, 4, 12],
      5: <double>[16, 52, 4, 12],
      4: <double>[24, 52, 4, 12],
    },
  };

  /// 返回某部位某面（[BlockFace.index]）在「图集像素坐标」中的矩形 [x,y,w,h]；
  /// 无皮肤/未知返回 null。
  static Float32List? skinRectFor(String part, int faceIndex) {
    if (!_hasSkin) return null;
    final Map<int, List<double>>? m = _skinLayout[part];
    final List<double>? r = m == null ? null : m[faceIndex];
    if (r == null) return null;
    return Float32List.fromList(<double>[
      _skinOx + r[0] * _skinScale,
      _skinOy + r[1] * _skinScale,
      r[2] * _skinScale,
      r[3] * _skinScale,
    ]);
  }

  static void _drawTile(ui.Canvas c, int col, int row, Voxel v, int variant) {
    final double ox = col * tile.toDouble();
    final double oy = row * tile.toDouble();
    for (int py = 0; py < tile; py++) {
      for (int px = 0; px < tile; px++) {
        final ui.Color pix = _pixel(v, px, py, variant);
        c.drawRect(
          ui.Rect.fromLTWH(ox + px, oy + py, 1, 1),
          ui.Paint()..color = pix,
        );
      }
    }
  }

  /// 单像素颜色（确定性：同坐标恒同，避免闪烁）。
  static ui.Color _pixel(Voxel v, int px, int py, int variant) {
    // 变体影响散列种子 → 每种变体纹理/抖动 pattern 不同（纹理变体）。
    final double n = _noise(px, py, v.index * 131 + 7 + variant * 917);
    final double f = 1.0 + (n - 0.5) * 0.18; // ±9% 亮度抖动，去平涂感
    switch (v) {
      case Voxel.grass:
        if (py < 4) return _shade(const ui.Color(0xFF6A4A2B), 1.0); // 顶边土
        return _shade(const ui.Color(0xFF5BA83A), f);
      case Voxel.dirt:
        return _shade(const ui.Color(0xFF6A4A2B), f);
      case Voxel.stone:
        return _shade(const ui.Color(0xFF8A8A8E), f);
      case Voxel.cobble:
        return _shade(const ui.Color(0xFF7C7C80), f * (n > 0.7 ? 0.85 : 1.1));
      case Voxel.sand:
        return _shade(const ui.Color(0xFFE0D2A0), f);
      case Voxel.snow:
        return _shade(const ui.Color(0xFFF2F6FB), f);
      case Voxel.wood:
        final double bark = (px % 4 == 0) ? 0.82 : 1.0; // 竖纹
        return _shade(const ui.Color(0xFF6E4B27), f * bark);
      case Voxel.leaves:
        return _shade(const ui.Color(0xFF3C7A2E), f);
      case Voxel.planks:
        final double plank = (py % 4 == 0) ? 0.82 : 1.0; // 横纹
        return _shade(const ui.Color(0xFFB8894E), f * plank);
      case Voxel.brick:
        final bool rowLine = (py % 4 == 0);
        final bool colLine = ((py ~/ 4) % 2 == 0)
            ? (px % 8 == 0)
            : (px % 8 == 4); // 错缝
        final double bf = (rowLine || colLine) ? 0.8 : 1.0;
        return _shade(const ui.Color(0xFF9E4B3B), f * bf);
      case Voxel.glass:
        return _shade(const ui.Color(0xFFBFE6F2), f);
      case Voxel.water:
        final double w = math.sin((px + py) * 0.8) * 0.5 + 0.5;
        return _shade(const ui.Color(0xFF3A6EA5), 0.85 + w * 0.2);
      case Voxel.slab:
      case Voxel.stairs:
        return _shade(const ui.Color(0xFF9A9A9E), f);
      case Voxel.fence:
        return _shade(const ui.Color(0xFF7A5230), f);
      case Voxel.furnace:
        return (py > 8)
            ? _shade(const ui.Color(0xFF3A2A22), 1.0)
            : _shade(const ui.Color(0xFF6E6E72), f);
      case Voxel.campfire:
        return (py > 8)
            ? _shade(const ui.Color(0xFFE0642A), 1.0)
            : _shade(const ui.Color(0xFF5A4030), f);
      case Voxel.torch:
        return _shade(const ui.Color(0xFFFFC56B), f);
      case Voxel.chest:
        return _shade(const ui.Color(0xFF8A5A2B), f);
      case Voxel.apple:
        return _shade(const ui.Color(0xFFD8392F), f);
      case Voxel.bread:
        return _shade(const ui.Color(0xFFC98A3A), f);
      case Voxel.gold:
        return _shade(const ui.Color(0xFFF2C94C), f);
      case Voxel.diamond:
        return _shade(const ui.Color(0xFF5FE0D0), f);
      case Voxel.coalOre:
        return _shade(n > 0.6 ? const ui.Color(0xFF1A1A1A) : const ui.Color(0xFF6E6E72), f);
      case Voxel.ironOre:
        return _shade(n > 0.72 ? const ui.Color(0xFFD9A066) : const ui.Color(0xFF8A8A8E), f);
      case Voxel.redstoneOre:
        return _shade(n > 0.62 ? const ui.Color(0xFFC0392B) : const ui.Color(0xFF6E6E72), f);
      case Voxel.lapisOre:
        return _shade(n > 0.62 ? const ui.Color(0xFF2E5BC4) : const ui.Color(0xFF6E6E72), f);
      case Voxel.emeraldOre:
        return _shade(n > 0.62 ? const ui.Color(0xFF2ECC71) : const ui.Color(0xFF6E6E72), f);
      case Voxel.diamondOre:
        return _shade(n > 0.62 ? const ui.Color(0xFF5FE0D0) : const ui.Color(0xFF6E6E72), f);
      case Voxel.redstone:
        return _shade(const ui.Color(0xFFC0392B), f);
      case Voxel.lapis:
        return _shade(const ui.Color(0xFF2E5BC4), f);
      case Voxel.emerald:
        return _shade(const ui.Color(0xFF2ECC71), f);
      default:
        final ui.Color base =
            ui.Color(v.spec.base.toARGB32() | 0xFF000000);
        return _shade(base, f);
    }
  }

  static double _noise(int x, int y, int seed) {
    int k = (x * 374761393 + y * 668265263 + seed * 982451653) & 0x7fffffff;
    k = (k ^ (k >> 13)) * 1274126177;
    k = k ^ (k >> 16);
    return ((k & 0xffff) / 0xffff).toDouble();
  }

  static ui.Color _shade(ui.Color c, double f) {
    final int r = (c.r * f).round().clamp(0, 255);
    final int g = (c.g * f).round().clamp(0, 255);
    final int b = (c.b * f).round().clamp(0, 255);
    return ui.Color.fromARGB(255, r, g, b);
  }
}
