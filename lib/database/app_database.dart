import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';
import '../models/download_models.dart';
import '../utils/app_logger.dart';

part 'app_database.g.dart';

// 简化数据库，带有用于离线支持的 API 缓存
@DriftDatabase(tables: [DownloadedMedia, DownloadQueue, ApiCache, OfflineWatchProgress])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 7; // 增加了 OfflineWatchProgress 表

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // 架构版本 7 的增量迁移
        if (from < 7) {
          appLogger.i('正在添加 OfflineWatchProgress 表 (v7 迁移)');
          await m.createTable(offlineWatchProgress);
        }
      },
    );
  }

  // ============================================================
  // 离线观看进度操作
  // ============================================================

  /// 获取所有待同步的离线观看操作
  Future<List<OfflineWatchProgressItem>> getPendingWatchActions() {
    return (select(offlineWatchProgress)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
  }

  /// 获取特定服务器的待处理观看操作
  Future<List<OfflineWatchProgressItem>> getPendingWatchActionsForServer(String serverId) {
    return (select(offlineWatchProgress)
          ..where((t) => t.serverId.equals(serverId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// 获取特定项目的最新操作
  Future<OfflineWatchProgressItem?> getLatestWatchAction(String globalKey) {
    return (select(offlineWatchProgress)
          ..where((t) => t.globalKey.equals(globalKey))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 在单个查询中获取多个项目的最新操作
  ///
  /// 返回 globalKey -> 每个键的最新操作的映射。
  /// 没有操作的键将不会出现在返回的映射中。
  Future<Map<String, OfflineWatchProgressItem>> getLatestWatchActionsForKeys(Set<String> globalKeys) async {
    if (globalKeys.isEmpty) return {};

    // 查询给定键的所有操作
    final allActions =
        await (select(offlineWatchProgress)
              ..where((t) => t.globalKey.isIn(globalKeys))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get();

    // 按 globalKey 分组并取最新的 (由于排序，取第一个)
    final result = <String, OfflineWatchProgressItem>{};
    for (final action in allActions) {
      // 每个键仅保留第一个 (最新的) 操作
      result.putIfAbsent(action.globalKey, () => action);
    }

    return result;
  }

  /// 插入或更新进度操作 (与现有操作合并)
  Future<void> upsertProgressAction({
    required String serverId,
    required String ratingKey,
    required int viewOffset,
    required int duration,
    required bool shouldMarkWatched,
  }) async {
    final globalKey = '$serverId:$ratingKey';
    final now = DateTime.now().millisecondsSinceEpoch;

    // 检查是否存在进度条目
    final existing =
        await (select(offlineWatchProgress)
              ..where((t) => t.globalKey.equals(globalKey) & t.actionType.equals('progress'))
              ..limit(1))
            .getSingleOrNull();

    if (existing != null) {
      // 更新现有进度条目
      await (update(offlineWatchProgress)..where((t) => t.id.equals(existing.id))).write(
        OfflineWatchProgressCompanion(
          viewOffset: Value(viewOffset),
          duration: Value(duration),
          shouldMarkWatched: Value(shouldMarkWatched),
          updatedAt: Value(now),
        ),
      );
    } else {
      // 插入新进度条目
      await into(offlineWatchProgress).insert(
        OfflineWatchProgressCompanion.insert(
          serverId: serverId,
          ratingKey: ratingKey,
          globalKey: globalKey,
          actionType: 'progress',
          viewOffset: Value(viewOffset),
          duration: Value(duration),
          shouldMarkWatched: Value(shouldMarkWatched),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  /// 插入手动观看操作 (已看或未看)
  /// 移除同一项目的冲突操作
  Future<void> insertWatchAction({
    required String serverId,
    required String ratingKey,
    required String actionType, // 'watched' 或 'unwatched'
  }) async {
    final globalKey = '$serverId:$ratingKey';
    final now = DateTime.now().millisecondsSinceEpoch;

    // 移除冲突操作 (相反的操作类型和进度)
    await (delete(offlineWatchProgress)..where((t) => t.globalKey.equals(globalKey))).go();

    // 插入新操作
    await into(offlineWatchProgress).insert(
      OfflineWatchProgressCompanion.insert(
        serverId: serverId,
        ratingKey: ratingKey,
        globalKey: globalKey,
        actionType: actionType,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// 同步成功后删除特定的观看操作
  Future<void> deleteWatchAction(int id) {
    return (delete(offlineWatchProgress)..where((t) => t.id.equals(id))).go();
  }

  /// 更新同步尝试次数和错误消息
  Future<void> updateSyncAttempt(int id, String? errorMessage) async {
    final existing = await (select(offlineWatchProgress)..where((t) => t.id.equals(id))).getSingleOrNull();

    if (existing != null) {
      await (update(offlineWatchProgress)..where((t) => t.id.equals(id))).write(
        OfflineWatchProgressCompanion(syncAttempts: Value(existing.syncAttempts + 1), lastError: Value(errorMessage)),
      );
    }
  }

  /// 获取待同步项目的数量
  Future<int> getPendingSyncCount() async {
    final count = await (selectOnly(offlineWatchProgress)..addColumns([offlineWatchProgress.id.count()]))
        .map((row) => row.read(offlineWatchProgress.id.count()))
        .getSingle();
    return count ?? 0;
  }

  /// 清除所有待处理的观看操作 (例如，退出登录后)
  Future<void> clearAllWatchActions() {
    return delete(offlineWatchProgress).go();
  }

  // ============================================================
  // 用于观看状态同步的已下载媒体查询
  // ============================================================

  /// 获取所有已下载的媒体项目 (用于同步观看状态)
  Future<List<DownloadedMediaItem>> getAllDownloadedMetadata() {
    return (select(downloadedMedia)..where((t) => t.status.equals(DownloadStatus.completed.index))).get();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'plezy_downloads.db'));
    return NativeDatabase(file);
  });
}
