import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'plex_client.dart';
import '../models/plex_config.dart';
import '../utils/app_logger.dart';
import 'plex_auth_service.dart';
import 'storage_service.dart';

/// 同时管理多个 Plex 服务器连接
class MultiServerManager {
  /// serverId (clientIdentifier) 到 PlexClient 实例的映射
  final Map<String, PlexClient> _clients = {};

  /// serverId 到服务器信息的映射
  final Map<String, PlexServer> _servers = {};

  /// serverId 到在线状态的映射
  final Map<String, bool> _serverStatus = {};

  /// 服务器状态变更的流控制器
  final _statusController = StreamController<Map<String, bool>>.broadcast();

  /// 服务器状态变更的流
  Stream<Map<String, bool>> get statusStream => _statusController.stream;

  /// 用于网络监控的连接状态订阅
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// serverId 到活跃优化 Future 的映射
  final Map<String, Future<void>> _activeOptimizations = {};

  /// 获取所有已注册的服务器 ID
  List<String> get serverIds => _servers.keys.toList();

  /// 获取所有在线的服务器 ID
  List<String> get onlineServerIds => _serverStatus.entries.where((e) => e.value).map((e) => e.key).toList();

  /// 获取所有离线的服务器 ID
  List<String> get offlineServerIds => _serverStatus.entries.where((e) => !e.value).map((e) => e.key).toList();

  /// 获取特定服务器的客户端
  PlexClient? getClient(String serverId) => _clients[serverId];

  /// 获取特定服务器的服务器信息
  PlexServer? getServer(String serverId) => _servers[serverId];

  /// 获取所有在线的客户端
  Map<String, PlexClient> get onlineClients {
    final result = <String, PlexClient>{};
    for (final serverId in onlineServerIds) {
      final client = _clients[serverId];
      if (client != null) {
        result[serverId] = client;
      }
    }
    return result;
  }

  /// 获取所有服务器
  Map<String, PlexServer> get servers => Map.unmodifiable(_servers);

  /// 检查服务器是否在线
  bool isServerOnline(String serverId) => _serverStatus[serverId] ?? false;

  /// 为给定服务器创建并初始化 PlexClient
  ///
  /// 处理寻找可用连接、加载缓存端点、创建配置以及构建具有故障转移支持的客户端。
  Future<PlexClient> _createClientForServer({required PlexServer server, required String clientIdentifier}) async {
    final serverId = server.clientIdentifier;

    // 寻找最佳可用连接
    PlexConnection? workingConnection;
    await for (final connection in server.findBestWorkingConnection()) {
      workingConnection = connection;
      break;
    }

    if (workingConnection == null) {
      throw Exception('未找到可用连接');
    }

    final baseUrl = workingConnection.uri;

    // 获取存储并加载此服务器的缓存端点
    final storage = await StorageService.getInstance();
    final cachedEndpoint = storage.getServerEndpoint(serverId);

    // 创建具有故障转移支持的 PlexClient
    final prioritizedEndpoints = server.prioritizedEndpointUrls(preferredFirst: cachedEndpoint ?? baseUrl);
    final config = await PlexConfig.create(
      baseUrl: baseUrl,
      token: server.accessToken,
      clientIdentifier: clientIdentifier,
    );

    final client = PlexClient(
      config,
      serverId: serverId,
      serverName: server.name,
      prioritizedEndpoints: prioritizedEndpoints,
      onEndpointChanged: (newUrl) async {
        await storage.saveServerEndpoint(serverId, newUrl);
        appLogger.i('故障转移后更新 ${server.name} 的端点: $newUrl');
      },
    );

    // 保存初始端点
    await storage.saveServerEndpoint(serverId, baseUrl);

    return client;
  }

  /// 并行连接到所有可用服务器
  /// 返回成功连接的服务器数量
  Future<int> connectToAllServers(
    List<PlexServer> servers, {
    String? clientIdentifier,
    Duration timeout = const Duration(seconds: 10),
    Function(String serverId, PlexClient client)? onServerConnected,
    Function(String serverId, Object error)? onServerFailed,
  }) async {
    if (servers.isEmpty) {
      appLogger.w('没有可连接的服务器');
      return 0;
    }

    appLogger.i('正在连接到 ${servers.length} 个服务器...');

    // 使用提供的客户端 ID 或为此应用实例生成一个唯一的 ID
    final effectiveClientId = clientIdentifier ?? DateTime.now().millisecondsSinceEpoch.toString();

    // 为所有服务器创建连接任务
    final connectionFutures = servers.map((server) async {
      final serverId = server.clientIdentifier;

      try {
        appLogger.d('尝试连接服务器: ${server.name}');

        final client = await _createClientForServer(server: server, clientIdentifier: effectiveClientId);

        // 存储客户端和服务器信息
        _clients[serverId] = client;
        _servers[serverId] = server;
        _serverStatus[serverId] = true;

        onServerConnected?.call(serverId, client);
        appLogger.i('成功连接到 ${server.name}');

        return serverId;
      } catch (e, stackTrace) {
        appLogger.e('连接 ${server.name} 失败', error: e, stackTrace: stackTrace);

        // 标记为离线
        _servers[serverId] = server;
        _serverStatus[serverId] = false;

        onServerFailed?.call(serverId, e);
        return null;
      }
    });

    // 等待所有连接完成（带超时控制）
    final results = await Future.wait(
      connectionFutures.map(
        (f) => f.timeout(
          timeout,
          onTimeout: () {
            appLogger.w('服务器连接超时');
            return null;
          },
        ),
      ),
    );

    // 统计成功连接的数量
    final successCount = results.where((id) => id != null).length;

    // 通知监听者状态变更
    _statusController.add(Map.from(_serverStatus));

    appLogger.i('成功连接到 $successCount/${servers.length} 个服务器');

    // 如果有任何成功连接的服务器，则启动网络监控
    if (successCount > 0) {
      startNetworkMonitoring();
    }

    return successCount;
  }

  /// 添加单个服务器连接
  Future<bool> addServer(PlexServer server, {String? clientIdentifier}) async {
    final serverId = server.clientIdentifier;
    final effectiveClientId = clientIdentifier ?? DateTime.now().millisecondsSinceEpoch.toString();

    try {
      appLogger.d('正在添加服务器: ${server.name}');

      final client = await _createClientForServer(server: server, clientIdentifier: effectiveClientId);

      // 存储
      _clients[serverId] = client;
      _servers[serverId] = server;
      _serverStatus[serverId] = true;

      // 通知
      _statusController.add(Map.from(_serverStatus));

      appLogger.i('成功添加服务器: ${server.name}');
      return true;
    } catch (e, stackTrace) {
      appLogger.e('添加服务器 ${server.name} 失败', error: e, stackTrace: stackTrace);

      _servers[serverId] = server;
      _serverStatus[serverId] = false;
      _statusController.add(Map.from(_serverStatus));

      return false;
    }
  }

  /// 移除服务器连接
  void removeServer(String serverId) {
    _clients.remove(serverId);
    _servers.remove(serverId);
    _serverStatus.remove(serverId);
    _statusController.add(Map.from(_serverStatus));
    appLogger.i('已移除服务器: $serverId');
  }

  /// 更新服务器状态（用于健康监测）
  void updateServerStatus(String serverId, bool isOnline) {
    if (_serverStatus[serverId] != isOnline) {
      _serverStatus[serverId] = isOnline;
      _statusController.add(Map.from(_serverStatus));
      appLogger.d('服务器 $serverId 状态变更为: $isOnline');
    }
  }

  /// 测试所有服务器的连接健康状况
  Future<void> checkServerHealth() async {
    appLogger.d('正在检查 ${_clients.length} 个服务器的健康状况');

    final healthChecks = _clients.entries.map((entry) async {
      final serverId = entry.key;
      final client = entry.value;

      try {
        // 通过获取服务器标识进行简单的 ping 测试
        await client.getServerIdentity();
        updateServerStatus(serverId, true);
      } catch (e) {
        appLogger.w('服务器 $serverId 健康检查失败: $e');
        updateServerStatus(serverId, false);
      }
    });

    await Future.wait(healthChecks);
  }

  /// 为所有服务器启动网络连接监控
  void startNetworkMonitoring() {
    if (_connectivitySubscription != null) {
      appLogger.d('网络监控已处于活跃状态');
      return;
    }

    appLogger.i('正在为所有服务器启动网络监控');
    final connectivity = Connectivity();
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(
      (results) {
        final status = results.isNotEmpty ? results.first : ConnectivityResult.none;

        if (status == ConnectivityResult.none) {
          appLogger.w('网络连接丢失，暂停优化直到网络恢复');
          return;
        }

        appLogger.d(
          '检测到网络变更，重新优化所有服务器',
          error: {
            'status': status.name,
            'interfaces': results.map((r) => r.name).toList(),
            'serverCount': _servers.length,
          },
        );

        // 重新优化所有服务器
        _reoptimizeAllServers(reason: 'connectivity:${status.name}');
      },
      onError: (error, stackTrace) {
        appLogger.w('连接状态监听器错误', error: error, stackTrace: stackTrace);
      },
    );
  }

  /// 停止网络连接监控
  void stopNetworkMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    appLogger.i('已停止网络监控');
  }

  /// 重新优化所有已连接的服务器
  void _reoptimizeAllServers({required String reason}) {
    for (final entry in _servers.entries) {
      final serverId = entry.key;
      final server = entry.value;

      // 如果服务器离线，则跳过
      if (!isServerOnline(serverId)) {
        continue;
      }

      // 如果此服务器已在运行优化，则跳过
      if (_activeOptimizations.containsKey(serverId)) {
        appLogger.d('${server.name} 的优化已在运行中，跳过', error: {'reason': reason});
        continue;
      }

      // 运行优化
      _activeOptimizations[serverId] = _reoptimizeServer(serverId: serverId, server: server, reason: reason)
          .whenComplete(() {
            _activeOptimizations.remove(serverId);
          });
    }
  }

  /// 为特定服务器重新优化连接
  Future<void> _reoptimizeServer({required String serverId, required PlexServer server, required String reason}) async {
    final storage = await StorageService.getInstance();
    final client = _clients[serverId];

    try {
      appLogger.d('开始为 ${server.name} 进行连接优化', error: {'reason': reason});

      await for (final connection in server.findBestWorkingConnection()) {
        final newUrl = connection.uri;

        // 检查这是否确实比当前连接更好
        if (client != null && client.config.baseUrl == newUrl) {
          appLogger.d('${server.name} 已在使用最优端点: $newUrl');
          continue;
        }

        // 保存新端点
        await storage.saveServerEndpoint(serverId, newUrl);

        // 如果客户端支持端点故障转移，它将自动切换
        // 否则，我们可能需要重新创建客户端（但故障转移逻辑应该能处理它）
        appLogger.i('已更新 ${server.name} 的最优端点: $newUrl', error: {'type': connection.displayType});
      }
    } catch (e, stackTrace) {
      appLogger.w('${server.name} 的连接优化失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 断开所有服务器连接
  void disconnectAll() {
    appLogger.i('正在断开所有服务器连接');
    stopNetworkMonitoring();
    _clients.clear();
    _servers.clear();
    _serverStatus.clear();
    _activeOptimizations.clear();
    _statusController.add({});
  }

  /// 释放资源
  void dispose() {
    disconnectAll();
    _statusController.close();
  }
}
