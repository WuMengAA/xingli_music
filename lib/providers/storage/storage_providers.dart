import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../services/storage/storage_service.dart';
import '../../services/storage/usage_repository.dart';

/// SharedPreferences 实例（main() 启动时注入，见 main.dart）
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider 需在 main() 中 override'),
);

/// Module 6：存储层 Provider
///
/// - [storageServiceProvider]：SharedPreferences 类型化封装（键值层）
/// - [usageRepositoryProvider]：sqflite 结构化存储（使用行为层）

/// 结构化存储数据库（首次访问时打开）
final usageDbProvider = FutureProvider<Database>((ref) async {
  final Database db = await UsageRepository.open();
  ref.onDispose(db.close);
  return db;
});

/// 使用行为仓储
final usageRepositoryProvider = Provider<UsageRepository>((ref) {
  final Database db = ref.watch(usageDbProvider).requireValue;
  return UsageRepository(db);
});

/// 键值存储服务（复用既有 prefsProvider，统一入口）
final storageServiceProvider = Provider<StorageService>((ref) {
  final StorageService svc = StorageService(ref.watch(prefsProvider));
  return svc;
});
