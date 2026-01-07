import 'dart:async';

import 'plex_client.dart';
import '../models/plex_hub.dart';
import '../models/plex_library.dart';
import '../models/plex_metadata.dart';
import '../utils/app_logger.dart';
import 'multi_server_manager.dart';
import 'plex_auth_service.dart';

/// 用于聚合来自多个 Plex 服务器数据的服务
class DataAggregationService {
  final MultiServerManager _serverManager;

  // 媒体库缓存及其生存时间 (TTL)
  Map<String, List<PlexLibrary>>? _cachedLibrariesByServer;
  DateTime? _librariesCacheTime;
  static const Duration _librariesCacheTTL = Duration(hours: 1);

  DataAggregationService(this._serverManager);

  /// 清除媒体库缓存 (在服务器变更或退出登录时很有用)
  void clearCache() {
    _cachedLibrariesByServer = null;
    _librariesCacheTime = null;
  }

  /// 检查媒体库缓存是否仍然有效
  bool get _isLibrariesCacheValid {
    if (_cachedLibrariesByServer == null || _librariesCacheTime == null) {
      return false;
    }

    final cacheAge = DateTime.now().difference(_librariesCacheTime!);
    return cacheAge < _librariesCacheTTL;
  }

  /// 从所有在线服务器获取媒体库
  /// 媒体库会自动由 PlexClient 标记服务器信息
  Future<List<PlexLibrary>> getLibrariesFromAllServers() async {
    return _perServer<PlexLibrary>(
      operationName: '正在获取媒体库',
      operation: (serverId, client, server) async {
        return await client.getLibraries();
      },
    );
  }

  /// 从所有服务器获取 "On Deck" (继续观看) 并按时间排序
  /// 项目会自动由 PlexClient 标记服务器信息
  Future<List<PlexMetadata>> getOnDeckFromAllServers({int? limit}) async {
    final allOnDeck = await _perServer<PlexMetadata>(
      operationName: '正在获取继续观看项目',
      operation: (serverId, client, server) async {
        return await client.getOnDeck();
      },
    );

    // 按最近观看时间排序
    // 优先使用 lastViewedAt (最后观看时间)，如果没有则回退到 updatedAt/addedAt
    allOnDeck.sort((a, b) {
      final aTime = a.lastViewedAt ?? a.updatedAt ?? a.addedAt ?? 0;
      final bTime = b.lastViewedAt ?? b.updatedAt ?? b.addedAt ?? 0;
      return bTime.compareTo(aTime); // 降序 (最近的排在前面)
    });

    // 如果指定了限制，则应用限制
    final result = limit != null && limit < allOnDeck.length ? allOnDeck.sublist(0, limit) : allOnDeck;

    appLogger.i('已从所有服务器获取 ${result.length} 个继续观看项目');

    return result;
  }

  /// 从所有服务器获取媒体库并缓存，用于后续获取推荐栏 (Hub)
  /// 这允许媒体库获取与其他操作并行进行
  Future<Map<String, List<PlexLibrary>>> getLibrariesFromAllServersGrouped({bool forceRefresh = false}) async {
    // 如果缓存有效且不强制刷新，则返回缓存的媒体库数据
    if (!forceRefresh && _isLibrariesCacheValid) {
      appLogger.d('正在使用缓存的媒体库数据');
      return _cachedLibrariesByServer!;
    }

    final librariesByServer = await _perServerGrouped<PlexLibrary>(
      operationName: '正在获取媒体库',
      operation: (serverId, client, server) async {
        return await client.getLibraries();
      },
    );

    // 缓存结果
    _cachedLibrariesByServer = librariesByServer;
    _librariesCacheTime = DateTime.now();

    final totalLibraries = librariesByServer.values.fold<int>(0, (sum, libs) => sum + libs.length);
    appLogger.d('已从 ${librariesByServer.length} 个服务器获取 $totalLibraries 个媒体库');

    return librariesByServer;
  }

  /// 使用预先获取的媒体库，从所有服务器获取推荐栏 (Hub)
  Future<List<PlexHub>> getHubsFromAllServers({
    int? limit,
    Map<String, List<PlexLibrary>>? librariesByServer,
    Set<String>? hiddenLibraryKeys,
  }) async {
    final clients = _serverManager.onlineClients;

    if (clients.isEmpty) {
      appLogger.w('没有在线服务器可用于获取推荐栏');
      return [];
    }

    // 使用预先获取的媒体库，如果未提供则重新获取
    final libraries = librariesByServer ?? await getLibrariesFromAllServersGrouped();

    appLogger.d('正在从 ${clients.length} 个服务器获取推荐栏');

    final allHubs = <PlexHub>[];

    // 并行从所有服务器获取推荐栏，使用缓存的媒体库
    final hubFutures = clients.entries.map((entry) async {
      final serverId = entry.key;
      final client = entry.value;

      try {
        // 使用该服务器预先获取的媒体库
        final serverLibraries = libraries[serverId] ?? <PlexLibrary>[];
        if (serverLibraries.isEmpty) {
          appLogger.w('服务器 $serverId 没有可用的媒体库');
          return <PlexHub>[];
        }

        // 仅筛选可见的电影/剧集媒体库
        final visibleLibraries = serverLibraries.where((library) {
          if (library.type != 'movie' && library.type != 'show') {
            return false;
          }
          if (library.hidden != null && library.hidden != 0) {
            return false;
          }
          // 检查应用层隐藏的媒体库
          if (hiddenLibraryKeys != null && hiddenLibraryKeys.contains(library.globalKey)) {
            return false;
          }
          return true;
        }).toList();

        // 并行从所有媒体库获取推荐栏
        final libraryHubFutures = visibleLibraries.map((library) async {
          try {
            // 推荐栏已在源头标记了服务器信息
            final hubs = await client.getLibraryHubs(library.key);
            appLogger.d('已为服务器 $serverId 上的 ${library.title} 获取 ${hubs.length} 个推荐栏');
            return hubs;
          } catch (e) {
            appLogger.w('获取媒体库 ${library.title} 的推荐栏失败: $e');
            return <PlexHub>[];
          }
        });

        final libraryHubResults = await Future.wait(libraryHubFutures);

        // 展平所有媒体库的推荐栏
        final serverHubs = <PlexHub>[];
        for (final hubs in libraryHubResults) {
          serverHubs.addAll(hubs);
        }

        return serverHubs;
      } catch (e, stackTrace) {
        appLogger.e('从服务器 $serverId 获取推荐栏失败', error: e, stackTrace: stackTrace);
        _serverManager.updateServerStatus(serverId, false);
        return <PlexHub>[];
      }
    });

    final results = await Future.wait(hubFutures);

    // 展平所有结果
    for (final hubs in results) {
      allHubs.addAll(hubs);
    }

    // 如果指定了限制，则应用限制
    final result = limit != null && limit < allHubs.length ? allHubs.sublist(0, limit) : allHubs;

    appLogger.i('已从所有服务器获取 ${result.length} 个推荐栏');

    return result;
  }

  /// 跨所有在线服务器搜索
  /// 结果会自动由 PlexClient 标记服务器信息
  Future<List<PlexMetadata>> searchAcrossServers(String query, {int? limit}) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final allResults = await _perServer<PlexMetadata>(
      operationName: '正在搜索 "$query"',
      operation: (serverId, client, server) async {
        return await client.search(query);
      },
    );

    // 如果指定了限制，则应用限制
    final result = limit != null && limit < allResults.length ? allResults.sublist(0, limit) : allResults;

    appLogger.i('在所有服务器上找到 ${result.length} 个搜索结果');

    return result;
  }

  /// 获取特定服务器的媒体库
  Future<List<PlexLibrary>> getLibrariesForServer(String serverId) async {
    final client = _serverManager.getClient(serverId);

    if (client == null) {
      appLogger.w('未找到服务器 $serverId 的客户端');
      return [];
    }

    try {
      // 媒体库会自动由 PlexClient 标记服务器信息
      return await client.getLibraries();
    } catch (e, stackTrace) {
      appLogger.e('获取服务器 $serverId 的媒体库失败', error: e, stackTrace: stackTrace);
      _serverManager.updateServerStatus(serverId, false);
      return [];
    }
  }

  /// 按服务器对媒体库进行分组
  Map<String, List<PlexLibrary>> groupLibrariesByServer(List<PlexLibrary> libraries) {
    final grouped = <String, List<PlexLibrary>>{};

    for (final library in libraries) {
      final serverId = library.serverId;
      if (serverId != null) {
        grouped.putIfAbsent(serverId, () => []).add(library);
      }
    }

    return grouped;
  }

  // 私有辅助方法

  /// 用于多服务器并行扇出 (fan-out) 操作的基础辅助方法
  ///
  /// 返回原始结果为 (serverId, result) 元组列表。
  /// 被 [_perServer] 和 [_perServerGrouped] 用于不同的聚合策略。
  Future<List<(String serverId, List<T> result)>> _perServerRaw<T>({
    required String operationName,
    required Future<List<T>> Function(String serverId, PlexClient client, PlexServer? server) operation,
  }) async {
    final clients = _serverManager.onlineClients;

    if (clients.isEmpty) {
      appLogger.w('没有在线服务器可用于 $operationName');
      return [];
    }

    appLogger.d('正在从 ${clients.length} 个服务器执行 $operationName');

    final futures = clients.entries.map((entry) async {
      final serverId = entry.key;
      final client = entry.value;
      final server = _serverManager.getServer(serverId);
      final sw = Stopwatch()..start();

      try {
        final result = await operation(serverId, client, server);
        appLogger.d(
          '服务器 $serverId 的 $operationName 完成，耗时 ${sw.elapsedMilliseconds}ms，获取到 ${result.length} 个项目',
        );
        return (serverId, result);
      } catch (e, stackTrace) {
        appLogger.e('服务器 $serverId 的 $operationName 失败', error: e, stackTrace: stackTrace);
        _serverManager.updateServerStatus(serverId, false);
        appLogger.d('服务器 $serverId 的 $operationName 在耗时 ${sw.elapsedMilliseconds}ms 后失败');
        return (serverId, <T>[]);
      }
    });

    return await Future.wait(futures);
  }

  /// 用于多服务器并行扇出操作的高阶辅助方法
  ///
  /// 遍历所有在线客户端，为每个服务器执行操作，
  /// 处理错误，更新服务器状态，并将结果展平为单个列表。
  Future<List<T>> _perServer<T>({
    required String operationName,
    required Future<List<T>> Function(String serverId, PlexClient client, PlexServer? server) operation,
  }) async {
    final results = await _perServerRaw(operationName: operationName, operation: operation);
    return [for (final (_, items) in results) ...items];
  }

  /// 用于多服务器并行扇出操作的高阶辅助方法，按服务器对结果进行分组
  ///
  /// 与 [_perServer] 类似，但返回一个按 serverId 分组结果的 Map。
  Future<Map<String, List<T>>> _perServerGrouped<T>({
    required String operationName,
    required Future<List<T>> Function(String serverId, PlexClient client, PlexServer? server) operation,
  }) async {
    final results = await _perServerRaw(operationName: operationName, operation: operation);
    return {for (final (id, items) in results) id: items};
  }
}
