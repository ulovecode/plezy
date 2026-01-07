import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../providers/offline_mode_provider.dart';
import '../utils/app_logger.dart';
import 'multi_server_manager.dart';
import 'plex_api_cache.dart';
import 'plex_client.dart';

/// 用于管理离线观看进度并同步到 Plex 服务器的服务。
///
/// 处理：
/// - 离线时排队进度更新
/// - 排队手动标记已看/未看操作
/// - 进度达到 90% 阈值时自动标记为已看
/// - 恢复连接时同步排队的操作
class OfflineWatchSyncService extends ChangeNotifier {
  final AppDatabase _database;
  final MultiServerManager _serverManager;

  OfflineModeProvider? _offlineModeProvider;
  VoidCallback? _offlineModeListener;
  bool _isSyncing = false;
  bool _isBidirectionalSyncing = false;
  DateTime? _lastSyncTime;
  bool _hasPerformedStartupSync = false;

  /// 同步后刷新下载提供者元数据的回调
  VoidCallback? onWatchStatesRefreshed;

  /// 观看阈值 - 当进度超过此百分比时标记为已看
  static const double watchedThreshold = 0.90;

  /// 同步之间的最小间隔 (10 分钟)
  static const Duration minSyncInterval = Duration(minutes: 10);

  /// 放弃同步项目前的最大尝试次数
  static const int maxSyncAttempts = 5;

  OfflineWatchSyncService({required AppDatabase database, required MultiServerManager serverManager})
    : _database = database,
      _serverManager = serverManager;

  /// 是否正在进行同步
  bool get isSyncing => _isSyncing;

  /// 开始监控连接变化以进行自动同步
  void startConnectivityMonitoring(OfflineModeProvider offlineModeProvider) {
    // 移除之前的监听器（如果有）
    if (_offlineModeProvider != null && _offlineModeListener != null) {
      _offlineModeProvider!.removeListener(_offlineModeListener!);
    }

    _offlineModeProvider = offlineModeProvider;
    _offlineModeListener = () {
      if (!offlineModeProvider.isOffline) {
        // 刚上线 - 触发双向同步
        appLogger.i('连接已恢复 - 开始双向观看同步');
        _performBidirectionalSync();
      }
    };

    offlineModeProvider.addListener(_offlineModeListener!);

    // 不要在启动时同步 - 服务器尚未连接。
    // 同步将在以下情况发生：
    // - 连接恢复 (监听器触发)
    // - 应用从后台恢复 (onAppResumed)
  }

  /// 执行双向同步：推送本地更改，然后拉取服务器状态。
  ///
  /// 推送总是立即发生。拉取遵循 [minSyncInterval]，除非 [force] 为 true。
  Future<void> _performBidirectionalSync({bool force = false}) async {
    // 防止重叠的双向同步
    if (_isBidirectionalSyncing) {
      appLogger.d('双向同步已在进行中，跳过');
      return;
    }

    if (_serverManager.onlineClients.isEmpty) {
      appLogger.d('跳过观看同步 - 尚无连接的服务器可用');
      return;
    }

    _isBidirectionalSyncing = true;
    try {
      // 始终将本地更改推送到服务器 (从不节流出站同步)
      await syncPendingItems();

      // 仅节流从服务器拉取的操作
      if (!force && _lastSyncTime != null) {
        final elapsed = DateTime.now().difference(_lastSyncTime!);
        if (elapsed < minSyncInterval) {
          appLogger.d(
            '跳过服务器拉取 - 上次同步是在 ${elapsed.inMinutes} 分钟前 (最小间隔: ${minSyncInterval.inMinutes} 分钟)',
          );
          return;
        }
      }

      // 从服务器拉取最新状态
      await syncWatchStatesFromServer();
      _lastSyncTime = DateTime.now();
    } finally {
      _isBidirectionalSyncing = false;
    }
  }

  /// 当应用变为活跃状态时调用 - 如果间隔已过则进行同步。
  void onAppResumed() {
    if (_offlineModeProvider?.isOffline != true) {
      appLogger.d('应用已恢复 - 检查是否需要同步');
      _performBidirectionalSync();
    }
  }

  /// 在应用启动服务器连接时调用。
  ///
  /// 既然 PlexClient 已可用，触发初始同步。
  /// 每个应用会话仅运行一次。
  void onServersConnected() {
    if (_hasPerformedStartupSync) return;
    _hasPerformedStartupSync = true;

    if (_offlineModeProvider?.isOffline != true) {
      appLogger.i('服务器已连接 - 执行启动同步');
      _performBidirectionalSync();
    }
  }

  /// 排队一个进度更新以便稍后同步。
  ///
  /// 这在离线播放期间调用以跟踪观看位置。
  /// 如果进度超过 90%，shouldMarkWatched 将设置为 true。
  Future<void> queueProgressUpdate({
    required String serverId,
    required String ratingKey,
    required int viewOffset,
    required int duration,
  }) async {
    final shouldMarkWatched = isWatchedByProgress(viewOffset, duration);

    await _database.upsertProgressAction(
      serverId: serverId,
      ratingKey: ratingKey,
      viewOffset: viewOffset,
      duration: duration,
      shouldMarkWatched: shouldMarkWatched,
    );

    appLogger.d(
      '已排队离线进度: $serverId:$ratingKey 位置为 ${(viewOffset / 1000).toStringAsFixed(0)}s / ${(duration / 1000).toStringAsFixed(0)}s (${((viewOffset / duration) * 100).toStringAsFixed(1)}%)',
    );

    notifyListeners();
  }

  /// 排队一个手动 "标记为已看" 操作。
  ///
  /// 移除同一项目的任何冲突操作。
  Future<void> queueMarkWatched({required String serverId, required String ratingKey}) =>
      _queueWatchStatusAction(serverId: serverId, ratingKey: ratingKey, actionType: 'watched');

  /// 排队一个手动 "标记为未看" 操作。
  ///
  /// 移除同一项目的任何冲突操作。
  Future<void> queueMarkUnwatched({required String serverId, required String ratingKey}) =>
      _queueWatchStatusAction(serverId: serverId, ratingKey: ratingKey, actionType: 'unwatched');

  /// 内部辅助方法，用于排队已看/未看操作。
  Future<void> _queueWatchStatusAction({
    required String serverId,
    required String ratingKey,
    required String actionType,
  }) async {
    await _database.insertWatchAction(serverId: serverId, ratingKey: ratingKey, actionType: actionType);

    appLogger.d('已排队离线标记 $actionType: $serverId:$ratingKey');
    notifyListeners();
  }

  /// 根据进度百分比检查项目是否应被视为已看。
  bool isWatchedByProgress(int viewOffset, int duration) {
    if (duration == 0) return false;
    return (viewOffset / duration) >= watchedThreshold;
  }

  /// 获取媒体项目的本地观看状态。
  ///
  /// 返回：
  /// - `true` 如果项目在本地被标记为已看或进度 >= 90%
  /// - `false` 如果项目在本地被标记为未看
  /// - `null` 如果不存在本地操作 (使用缓存的服务器数据)
  Future<bool?> getLocalWatchStatus(String globalKey) async {
    final action = await _database.getLatestWatchAction(globalKey);
    if (action == null) return null;

    switch (action.actionType) {
      case 'watched':
        return true;
      case 'unwatched':
        return false;
      case 'progress':
        // 检查进度是否超过阈值
        return action.shouldMarkWatched;
      default:
        return null;
    }
  }

  /// 在单个数据库查询中获取多个项目的本地观看状态。
  ///
  /// 返回 globalKey -> 观看状态 (true/false/null) 的映射。
  /// 比多次调用 getLocalWatchStatus 更高效。
  Future<Map<String, bool?>> getLocalWatchStatusesBatched(Set<String> globalKeys) async {
    if (globalKeys.isEmpty) return {};

    final actions = await _database.getLatestWatchActionsForKeys(globalKeys);
    final result = <String, bool?>{};

    for (final key in globalKeys) {
      final action = actions[key];
      if (action == null) {
        result[key] = null;
        continue;
      }

      switch (action.actionType) {
        case 'watched':
          result[key] = true;
        case 'unwatched':
          result[key] = false;
        case 'progress':
          result[key] = action.shouldMarkWatched;
        default:
          result[key] = null;
      }
    }

    return result;
  }

  /// 获取媒体项目的本地观看偏移量 (续播位置)。
  ///
  /// 返回本地跟踪的位置，如果不存在则返回 null。
  Future<int?> getLocalViewOffset(String globalKey) async {
    final action = await _database.getLatestWatchAction(globalKey);
    if (action == null) return null;

    // 仅为进度操作返回偏移量
    if (action.actionType == 'progress') {
      return action.viewOffset;
    }

    return null;
  }

  /// 获取待同步项目的数量。
  Future<int> getPendingSyncCount() async {
    return _database.getPendingSyncCount();
  }

  /// 同步所有待处理项目到各自的服务器。
  ///
  /// 在连接恢复时自动调用，或手动调用。
  /// 按服务器分批处理操作以减少连接查找。
  Future<void> syncPendingItems() async {
    if (_isSyncing) {
      appLogger.d('同步已在进行中，跳过');
      return;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      final pendingActions = await _database.getPendingWatchActions();

      if (pendingActions.isEmpty) {
        appLogger.d('没有待同步的观看操作');
        return;
      }

      appLogger.i('正在同步 ${pendingActions.length} 个待处理的观看操作');

      // 第一步：处理超过重试限制的项目并按服务器分组
      final actionsByServer = <String, List<OfflineWatchProgressItem>>{};

      for (final action in pendingActions) {
        // 删除已超过重试限制的项目
        if (action.syncAttempts >= maxSyncAttempts) {
          appLogger.w(
            '正在删除操作 ${action.id} - 已超过重试限制 '
            '(${action.syncAttempts} 次尝试)。最后错误: ${action.lastError}',
          );
          await _database.deleteWatchAction(action.id);
          continue;
        }

        // 检查服务器是否仍然存在
        if (_serverManager.getServer(action.serverId) == null) {
          appLogger.w('正在删除操作 ${action.id} - 服务器 ${action.serverId} 不再存在');
          await _database.deleteWatchAction(action.id);
          continue;
        }

        actionsByServer.putIfAbsent(action.serverId, () => []).add(action);
      }

      // 第二步：通过单个连接检查处理每个服务器的操作
      for (final entry in actionsByServer.entries) {
        final serverId = entry.key;
        final actions = entry.value;

        await _withOnlineClient(serverId, (client) async {
          for (final action in actions) {
            try {
              await _syncAction(client, action);
              // 成功 - 从队列中删除该操作
              await _database.deleteWatchAction(action.id);
              appLogger.d('成功同步操作 ${action.id}: ${action.actionType} 用于 ${action.ratingKey}');
            } catch (e) {
              appLogger.w('同步操作 ${action.id} 失败: $e');
              await _database.updateSyncAttempt(action.id, e.toString());
            }
          }
        });

        // 如果 _withOnlineClient 返回 null (服务器离线)，则将操作标记为重试
        if (_serverManager.getClient(serverId) == null || !_serverManager.isServerOnline(serverId)) {
          for (final action in actions) {
            // 仅在尚未处理时更新
            final stillPending = await _database.getLatestWatchAction('${action.serverId}:${action.ratingKey}');
            if (stillPending != null && stillPending.id == action.id) {
              await _database.updateSyncAttempt(action.id, '服务器不可用');
            }
          }
        }
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// 使用给定服务器的在线客户端执行回调。
  ///
  /// 如果没有可用的客户端或服务器离线，则返回 null。
  /// 回调接收 PlexClient 并应返回结果。
  Future<T?> _withOnlineClient<T>(String serverId, Future<T> Function(PlexClient client) callback) async {
    final client = _serverManager.getClient(serverId);
    if (client == null) {
      appLogger.d('没有服务器 $serverId 的客户端，跳过');
      return null;
    }

    if (!_serverManager.isServerOnline(serverId)) {
      appLogger.d('服务器 $serverId 离线，跳过');
      return null;
    }

    return callback(client);
  }

  /// 将单个操作同步到服务器。
  Future<void> _syncAction(PlexClient client, OfflineWatchProgressItem action) async {
    switch (action.actionType) {
      case 'watched':
        await client.markAsWatched(action.ratingKey);
        break;

      case 'unwatched':
        await client.markAsUnwatched(action.ratingKey);
        break;

      case 'progress':
        // 首先，使用当前位置更新时间线
        if (action.viewOffset != null && action.duration != null) {
          await client.updateProgress(
            action.ratingKey,
            time: action.viewOffset!,
            state: 'stopped', // 使用 'stopped'，因为我们是在事后同步
            duration: action.duration,
          );
        }

        // 如果进度超过阈值，也标记为已看
        if (action.shouldMarkWatched) {
          await client.markAsWatched(action.ratingKey);
        }
        break;
    }
  }

  /// 从服务器获取最新的观看状态并更新本地缓存。
  ///
  /// 在上线或应用启动时调用，以拉取在其他设备上进行的任何观看状态更改。
  ///
  /// 经过优化，按季获取剧集 (每季一次 API 调用)，
  /// 而不是每集进行一次 API 调用。
  Future<void> syncWatchStatesFromServer() async {
    try {
      // 从数据库获取所有已下载的项目
      final downloadedItems = await _database.getAllDownloadedMetadata();

      if (downloadedItems.isEmpty) {
        appLogger.d('没有已下载的项目需要同步观看状态');
        return;
      }

      appLogger.i('正在从服务器同步 ${downloadedItems.length} 个项目的观看状态');

      // 将剧集 (带有季父级) 与其他项目 (电影等) 分开
      // 结构: serverId -> seasonRatingKey -> Set<episodeRatingKey>
      final episodesByServerAndSeason = <String, Map<String, Set<String>>>{};
      // 结构: serverId -> List<ratingKey>
      final nonEpisodeItems = <String, List<String>>{};

      for (final item in downloadedItems) {
        if (item.type == 'episode' && item.parentRatingKey != null) {
          // 按服务器和季对剧集进行分组以进行批量获取
          episodesByServerAndSeason
              .putIfAbsent(item.serverId, () => {})
              .putIfAbsent(item.parentRatingKey!, () => {})
              .add(item.ratingKey);
        } else {
          // 电影，或没有父级的剧集 (回退到单独获取)
          nonEpisodeItems.putIfAbsent(item.serverId, () => []).add(item.ratingKey);
        }
      }

      int syncedCount = 0;
      int seasonCount = 0;

      // 按季批量获取剧集 - 每季进行一次 API 调用
      for (final serverEntry in episodesByServerAndSeason.entries) {
        final serverId = serverEntry.key;
        final seasonMap = serverEntry.value;

        await _withOnlineClient(serverId, (client) async {
          for (final seasonEntry in seasonMap.entries) {
            final seasonRatingKey = seasonEntry.key;
            final downloadedEpisodeKeys = seasonEntry.value;

            try {
              // 通过一次 API 调用获取该季中的所有剧集
              final seasonEpisodes = await client.getChildren(seasonRatingKey);
              seasonCount++;

              // 仅缓存我们已下载的剧集
              for (final episode in seasonEpisodes) {
                if (downloadedEpisodeKeys.contains(episode.ratingKey)) {
                  await PlexApiCache.instance.put(serverId, '/library/metadata/${episode.ratingKey}', {
                    'MediaContainer': {
                      'Metadata': [episode.toJson()],
                    },
                  });
                  syncedCount++;
                }
              }
            } catch (e) {
              appLogger.d('同步季 $seasonRatingKey 的观看状态失败: $e');
            }
          }
        });
      }

      // 单独获取非剧集项目 (电影等)
      for (final entry in nonEpisodeItems.entries) {
        final serverId = entry.key;
        final ratingKeys = entry.value;

        await _withOnlineClient(serverId, (client) async {
          for (final ratingKey in ratingKeys) {
            try {
              final metadata = await client.getMetadataWithImages(ratingKey);
              if (metadata != null) {
                await PlexApiCache.instance.put(serverId, '/library/metadata/$ratingKey', {
                  'MediaContainer': {
                    'Metadata': [metadata.toJson()],
                  },
                });
                syncedCount++;
              }
            } catch (e) {
              appLogger.d('同步 $ratingKey 的观看状态失败: $e');
            }
          }
        });
      }

      final movieCount = nonEpisodeItems.values.fold(0, (a, b) => a + b.length);
      appLogger.i('已同步观看状态: $seasonCount 季, $movieCount 个其他项目 (共 $syncedCount 个项目)');

      // 通知下载提供者从更新的缓存中刷新元数据
      if (syncedCount > 0) {
        onWatchStatesRefreshed?.call();
      }

      notifyListeners();
    } catch (e) {
      appLogger.w('从服务器同步观看状态出错: $e');
    }
  }

  /// 清除所有待处理的观看操作 (例如，退出登录时)。
  Future<void> clearAll() async {
    await _database.clearAllWatchActions();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_offlineModeProvider != null && _offlineModeListener != null) {
      _offlineModeProvider!.removeListener(_offlineModeListener!);
    }
    super.dispose();
  }
}
