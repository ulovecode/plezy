import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// 使用 Drift/SQLite 的 Plex API 响应键值缓存。
/// 存储原始 JSON 响应，以 serverId:endpoint 格式为键。
class PlexApiCache {
  static PlexApiCache? _instance;
  static PlexApiCache get instance {
    if (_instance == null) {
      throw StateError('PlexApiCache 未初始化。请先调用 PlexApiCache.initialize()。');
    }
    return _instance!;
  }

  final AppDatabase _db;

  PlexApiCache._(this._db);

  /// 使用 AppDatabase 实例初始化单例
  static void initialize(AppDatabase db) {
    _instance = PlexApiCache._(db);
  }

  /// 获取数据库实例 (用于需要直接访问数据库的服务)
  AppDatabase get database => _db;

  /// 从 serverId 和 endpoint 构建缓存键
  String _buildKey(String serverId, String endpoint) {
    return '$serverId:$endpoint';
  }

  /// 获取 endpoint 的缓存响应
  Future<Map<String, dynamic>?> get(String serverId, String endpoint) async {
    final key = _buildKey(serverId, endpoint);
    final result = await (_db.select(_db.apiCache)..where((t) => t.cacheKey.equals(key))).getSingleOrNull();

    if (result != null) {
      return jsonDecode(result.data) as Map<String, dynamic>;
    }
    return null;
  }

  /// 缓存 endpoint 的响应
  Future<void> put(String serverId, String endpoint, Map<String, dynamic> data) async {
    final key = _buildKey(serverId, endpoint);
    await _db
        .into(_db.apiCache)
        .insertOnConflictUpdate(
          ApiCacheCompanion(cacheKey: Value(key), data: Value(jsonEncode(data)), cachedAt: Value(DateTime.now())),
        );
  }

  /// 删除服务器的所有缓存数据
  Future<void> deleteForServer(String serverId) async {
    await (_db.delete(_db.apiCache)..where((t) => t.cacheKey.like('$serverId:%'))).go();
  }

  /// 删除特定项目的缓存数据 (删除下载时调用)
  Future<void> deleteForItem(String serverId, String ratingKey) async {
    // 删除元数据端点
    final metadataKey = _buildKey(serverId, '/library/metadata/$ratingKey');
    final childrenKey = _buildKey(serverId, '/library/metadata/$ratingKey/children');

    await (_db.delete(
      _db.apiCache,
    )..where((t) => t.cacheKey.equals(metadataKey) | t.cacheKey.equals(childrenKey))).go();
  }

  /// 将项目标记为已固定，以便离线访问
  Future<void> pinForOffline(String serverId, String ratingKey) async {
    final metadataKey = _buildKey(serverId, '/library/metadata/$ratingKey');
    await (_db.update(
      _db.apiCache,
    )..where((t) => t.cacheKey.equals(metadataKey))).write(const ApiCacheCompanion(pinned: Value(true)));
  }

  /// 取消固定项目
  Future<void> unpinForOffline(String serverId, String ratingKey) async {
    final metadataKey = _buildKey(serverId, '/library/metadata/$ratingKey');
    await (_db.update(
      _db.apiCache,
    )..where((t) => t.cacheKey.equals(metadataKey))).write(const ApiCacheCompanion(pinned: Value(false)));
  }

  /// 检查项目是否已固定以便离线使用
  Future<bool> isPinned(String serverId, String ratingKey) async {
    final metadataKey = _buildKey(serverId, '/library/metadata/$ratingKey');
    final result = await (_db.select(_db.apiCache)..where((t) => t.cacheKey.equals(metadataKey))).getSingleOrNull();
    return result?.pinned ?? false;
  }

  /// 获取服务器的所有已固定 rating key
  Future<Set<String>> getPinnedKeys(String serverId) async {
    final results = await (_db.select(
      _db.apiCache,
    )..where((t) => t.cacheKey.like('$serverId:%') & t.pinned.equals(true))).get();

    final keys = <String>{};
    for (final row in results) {
      // 从缓存键中提取 ratingKey，例如 "serverId:/library/metadata/12345"
      // Rating key 可以是字母数字，不仅是数字
      final match = RegExp(r'/library/metadata/([^/]+)$').firstMatch(row.cacheKey);
      if (match != null) {
        keys.add(match.group(1)!);
      }
    }
    return keys;
  }

  /// 清除所有缓存数据 (用于调试/测试)
  Future<void> clearAll() async {
    await _db.delete(_db.apiCache).go();
  }
}
