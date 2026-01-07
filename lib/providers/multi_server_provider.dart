import 'package:flutter/foundation.dart';

import '../services/plex_client.dart';
import '../services/data_aggregation_service.dart';
import '../services/multi_server_manager.dart';
import '../services/plex_auth_service.dart';
import '../utils/app_logger.dart';

/// 用于多服务器 Plex 连接的 Provider
/// 管理多个 PlexClient 实例并提供数据聚合
class MultiServerProvider extends ChangeNotifier {
  final MultiServerManager _serverManager;
  final DataAggregationService _aggregationService;

  MultiServerProvider(this._serverManager, this._aggregationService) {
    // 监听服务器状态更改
    _serverManager.statusStream.listen((_) {
      notifyListeners();
    });
  }

  /// 获取多服务器管理器
  MultiServerManager get serverManager => _serverManager;

  /// 获取数据聚合服务
  DataAggregationService get aggregationService => _aggregationService;

  /// 获取特定服务器的客户端
  PlexClient? getClientForServer(String serverId) {
    return _serverManager.getClient(serverId);
  }

  /// 获取所有在线服务器 ID
  List<String> get onlineServerIds => _serverManager.onlineServerIds;

  /// 获取所有服务器 ID
  List<String> get serverIds => _serverManager.serverIds;

  /// 检查服务器是否在线
  bool isServerOnline(String serverId) {
    return _serverManager.isServerOnline(serverId);
  }

  /// 获取在线服务器数量
  int get onlineServerCount => _serverManager.onlineServerIds.length;

  /// 获取总服务器数量
  int get totalServerCount => _serverManager.serverIds.length;

  /// 检查是否连接了任何服务器
  bool get hasConnectedServers => onlineServerCount > 0;

  /// 更新特定服务器的令牌
  void updateTokenForServer(String serverId, String newToken) {
    final client = _serverManager.getClient(serverId);
    if (client != null) {
      client.updateToken(newToken);
      appLogger.d('MultiServerProvider: 服务器 $serverId 的令牌已更新');
      notifyListeners();
    } else {
      appLogger.w('MultiServerProvider: 无法更新令牌 - 未找到服务器 $serverId');
    }
  }

  /// 清除所有服务器连接
  void clearAllConnections() {
    _serverManager.disconnectAll();
    _aggregationService.clearCache(); // 服务器更改时清除缓存数据
    appLogger.d('MultiServerProvider: 所有连接已清除');
    notifyListeners();
  }

  /// 配置文件切换后重新连接所有服务器
  /// 清除现有连接并连接到所有提供的服务器
  Future<int> reconnectWithServers(List<PlexServer> servers, {String? clientIdentifier}) async {
    // 首先清除现有连接
    _serverManager.disconnectAll();
    _aggregationService.clearCache(); // 服务器更改时清除缓存数据
    appLogger.d('MultiServerProvider: 已清除连接，正在重新连接到 ${servers.length} 台服务器');

    // 使用新服务器令牌进行连接
    final connectedCount = await _serverManager.connectToAllServers(servers, clientIdentifier: clientIdentifier);

    appLogger.i('MultiServerProvider: 配置文件切换后，已重新连接到 $connectedCount/${servers.length} 台服务器');
    notifyListeners();
    return connectedCount;
  }

  /// 检查所有已连接服务器的健康状况
  Future<void> checkServerHealth() async {
    await _serverManager.checkServerHealth();
    // notifyListeners() 将通过状态流自动调用
  }

  @override
  void dispose() {
    _serverManager.dispose();
    super.dispose();
  }
}
