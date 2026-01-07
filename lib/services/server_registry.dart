import 'dart:convert';

import '../utils/app_logger.dart';
import 'plex_auth_service.dart';
import 'storage_service.dart';

/// 统一的服务器配置注册表
/// 管理可用服务器及其配置
class ServerRegistry {
  final StorageService _storage;

  ServerRegistry(this._storage);

  /// 获取所有已注册的服务器
  Future<List<PlexServer>> getServers() async {
    try {
      final serversJson = _storage.getServersListJson();
      if (serversJson == null || serversJson.isEmpty) {
        return [];
      }

      final List<dynamic> serversList = jsonDecode(serversJson);
      return serversList.map((json) => PlexServer.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e, stackTrace) {
      appLogger.e('从存储加载服务器失败', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// 将所有服务器保存到存储中
  Future<void> saveServers(List<PlexServer> servers) async {
    try {
      final serversJson = jsonEncode(servers.map((s) => s.toJson()).toList());
      await _storage.saveServersListJson(serversJson);
      appLogger.d('已将 ${servers.length} 个服务器保存到存储');
    } catch (e, stackTrace) {
      appLogger.e('将服务器保存到存储失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 根据 ID 获取特定服务器
  Future<PlexServer?> getServer(String serverId) async {
    final servers = await getServers();
    try {
      return servers.firstWhere((s) => s.clientIdentifier == serverId);
    } catch (e) {
      return null;
    }
  }

  /// 更新服务器状态 (当服务器连接状态改变时调用)
  Future<void> updateServerStatus(String serverId, {bool? online, DateTime? lastSeen}) async {
    final servers = await getServers();
    final serverIndex = servers.indexWhere((s) => s.clientIdentifier == serverId);

    if (serverIndex == -1) {
      appLogger.w('未找到要更新状态的服务器: $serverId');
      return;
    }

    // 注意：来自 auth service 的 PlexServer 没有可变的状态字段
    // 状态追踪由 MultiServerManager 处理
    // 保留此方法以便未来如果我们在 PlexServer 模型中添加状态时进行扩展
  }

  /// 添加或更新单个服务器
  Future<void> upsertServer(PlexServer server) async {
    final servers = await getServers();
    final index = servers.indexWhere((s) => s.clientIdentifier == server.clientIdentifier);

    if (index >= 0) {
      servers[index] = server;
      appLogger.d('已更新服务器: ${server.name}');
    } else {
      servers.add(server);
      appLogger.d('已添加新服务器: ${server.name}');
    }

    await saveServers(servers);
  }

  /// 移除服务器
  Future<void> removeServer(String serverId) async {
    final servers = await getServers();
    servers.removeWhere((s) => s.clientIdentifier == serverId);
    await saveServers(servers);

    appLogger.i('已移除服务器: $serverId');
  }

  /// 清除所有服务器
  Future<void> clearAllServers() async {
    await _storage.clearServersList();
    appLogger.i('已从注册表中清除所有服务器');
  }

  /// 从 Plex API 刷新服务器并更新存储
  /// 这会更新可能已更改的连接信息 (IP、端口)
  Future<void> refreshServersFromApi() async {
    final token = _storage.getPlexToken();
    if (token == null || token.isEmpty) {
      appLogger.d('没有可用的 Plex 令牌，跳过服务器刷新');
      return;
    }

    try {
      appLogger.d('正在从 Plex API 刷新服务器...');
      final authService = await PlexAuthService.create();
      final freshServers = await authService.fetchServers(token);

      if (freshServers.isEmpty) {
        appLogger.w('API 未返回服务器，保留现有数据');
        return;
      }

      // 获取现有服务器以保留任何仅限本地的数据
      final existingServers = await getServers();
      final existingIds = existingServers.map((s) => s.clientIdentifier).toSet();

      // 使用最新连接信息更新现有服务器，并添加新服务器
      final updatedServers = <PlexServer>[];
      for (final fresh in freshServers) {
        if (existingIds.contains(fresh.clientIdentifier)) {
          // 服务器已存在 - 使用最新数据 (更新后的 IP、连接)
          updatedServers.add(fresh);
        } else {
          // 新服务器 - 添加它
          updatedServers.add(fresh);
          appLogger.i('发现新服务器: ${fresh.name}');
        }
      }

      await saveServers(updatedServers);
      appLogger.i('已从 API 刷新了 ${updatedServers.length} 个服务器');
    } catch (e, stackTrace) {
      appLogger.w('从 API 刷新服务器失败，正在使用缓存数据', error: e, stackTrace: stackTrace);
      // 不要重新抛出 - 我们可以继续使用缓存的服务器
    }
  }

  /// 从单服务器存储迁移到多服务器存储
  /// 在应用启动期间调用以迁移现有用户
  Future<void> migrateFromSingleServer() async {
    try {
      // 检查是否已经以新格式拥有服务器
      final existingServers = await getServers();
      if (existingServers.isNotEmpty) {
        appLogger.d('服务器已完成迁移，跳过迁移步骤');
        return;
      }

      // 尝试加载旧的单服务器数据
      final oldServerData = _storage.getServerData();
      if (oldServerData == null) {
        appLogger.d('没有旧的服务器数据需要迁移');
        return;
      }

      // 解析并迁移
      final server = PlexServer.fromJson(oldServerData);

      appLogger.i('正在将单服务器迁移到多服务器: ${server.name}');

      // 以新格式保存为第一个服务器
      await saveServers([server]);

      appLogger.i('迁移完成');
    } catch (e, stackTrace) {
      appLogger.e('从单服务器迁移失败', error: e, stackTrace: stackTrace);
      // 不要重新抛出 - 迁移失败不应导致应用崩溃
    }
  }
}
