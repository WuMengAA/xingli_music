import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/voxel.dart';

/// 2.5D 音效场景文件格式标识（导出/导入校验用，便于将来扩展）。
const String kSceneFileFormat = 'xingli-voxel-scene';
const int kSceneFileVersion = 1;

/// 把场景序列化为可分享 / 导入的 JSON 包装（带格式标识与版本）。
///
/// 不直接存裸 `VoxelSoundScene.toJson()`，而是包一层 `format/version/scene`，
/// 这样导入时可校验来源、将来还能扩展（如带缩略图、作者信息）。
String encodeSceneFile(VoxelSoundScene scene) => jsonEncode(<String, dynamic>{
      'format': kSceneFileFormat,
      'version': kSceneFileVersion,
      'scene': scene.toJson(),
    });

/// 从分享 / 导入文件内容解析场景。
///
/// 格式不符或解析失败抛 [SceneFileFormatException]（上层据此提示用户）。
VoxelSoundScene decodeSceneFile(String content) {
  try {
    final Map<String, dynamic> root =
        jsonDecode(content) as Map<String, dynamic>;
    if (root['format'] != kSceneFileFormat) {
      throw const SceneFileFormatException('不支持的文件格式');
    }
    final Map<String, dynamic> sceneJson =
        root['scene'] as Map<String, dynamic>;
    return VoxelSoundScene.fromJson(sceneJson);
  } catch (e) {
    throw SceneFileFormatException('解析失败：$e');
  }
}

/// 写入临时文件并返回 [XFile]（供 `share_plus` 分享）。
Future<XFile> sceneToTempXFile(VoxelSoundScene scene) async {
  final Directory dir = await getTemporaryDirectory();
  final File f = File('${dir.path}/${_safeName(scene.name)}.json');
  await f.writeAsString(encodeSceneFile(scene));
  return XFile(f.path, mimeType: 'application/json');
}

/// 文件名安全化：保留字母数字 / 中文 / 连字符 / 空格，其余替换为下划线。
String _safeName(String name) {
  final String cleaned =
      name.replaceAll(RegExp(r'[^\w一-龥\- ]'), '_').trim();
  return cleaned.isEmpty ? 'voxel-scene' : cleaned;
}

/// 生成新的场景 id（导入时避免与现有场景 id 冲突覆盖）。
String newSceneId() => 'scene_${DateTime.now().microsecondsSinceEpoch}';

/// 场景文件格式 / 解析异常。
class SceneFileFormatException implements Exception {
  const SceneFileFormatException(this.message);
  final String message;
  @override
  String toString() => 'SceneFileFormatException: $message';
}
