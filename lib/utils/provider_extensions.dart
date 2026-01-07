import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/plex_client.dart';
import '../i18n/strings.g.dart';
import '../models/plex_library.dart';
import '../models/plex_metadata.dart';
import '../models/plex_user_profile.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/plex_client_provider.dart';
import '../providers/user_profile_provider.dart';
import 'app_logger.dart';

extension ProviderExtensions on BuildContext {
  PlexClientProvider get plexClient => Provider.of<PlexClientProvider>(this, listen: false);

  UserProfileProvider get userProfile => Provider.of<UserProfileProvider>(this, listen: false);

  PlexClientProvider watchPlexClient() => Provider.of<PlexClientProvider>(this, listen: true);

  UserProfileProvider watchUserProfile() => Provider.of<UserProfileProvider>(this, listen: true);

  HiddenLibrariesProvider get hiddenLibraries => Provider.of<HiddenLibrariesProvider>(this, listen: false);

  HiddenLibrariesProvider watchHiddenLibraries() => Provider.of<HiddenLibrariesProvider>(this, listen: true);

  // 直接访问个人资料设置（可为空）
  PlexUserProfile? get profileSettings => userProfile.profileSettings;

  /// 获取特定服务器 ID 的 PlexClient
  /// 如果给定 serverId 没有可用的客户端，则抛出异常
  PlexClient getClientForServer(String serverId) {
    final multiServerProvider = Provider.of<MultiServerProvider>(this, listen: false);

    final serverClient = multiServerProvider.getClientForServer(serverId);

    if (serverClient == null) {
      appLogger.e('No client found for server $serverId');
      throw Exception(t.errors.noClientAvailable);
    }

    return serverClient;
  }

  /// 获取媒体库的 PlexClient
  /// 如果没有可用的客户端，则抛出异常
  PlexClient getClientForLibrary(PlexLibrary library) {
    // 如果媒体库没有 serverId，则回退到第一个可用的服务器
    if (library.serverId == null) {
      final multiServerProvider = Provider.of<MultiServerProvider>(this, listen: false);
      if (!multiServerProvider.hasConnectedServers) {
        throw Exception(t.errors.noClientAvailable);
      }
      return getClientForServer(multiServerProvider.onlineServerIds.first);
    }
    return getClientForServer(library.serverId!);
  }

  /// 获取元数据的 PlexClient，如果元数据中没有 serverId 则回退到第一个可用的服务器
  /// 如果没有可用的服务器，则抛出异常
  PlexClient getClientForMetadata(PlexMetadata metadata) {
    if (metadata.serverId != null) {
      return getClientForServer(metadata.serverId!);
    }
    return getFirstAvailableClient();
  }

  /// 获取元数据的 PlexClient，如果是离线模式或没有 serverId 则返回 null
  /// 用于支持离线模式的屏幕
  PlexClient? getClientForMetadataOrNull(PlexMetadata metadata, {bool isOffline = false}) {
    if (isOffline || metadata.serverId == null) {
      return null;
    }
    return getClientForServer(metadata.serverId!);
  }

  /// 从连接的服务器中获取第一个可用的客户端
  /// 如果没有可用的服务器，则抛出异常
  PlexClient getFirstAvailableClient() {
    final multiServerProvider = Provider.of<MultiServerProvider>(this, listen: false);
    if (!multiServerProvider.hasConnectedServers) {
      throw Exception(t.errors.noClientAvailable);
    }
    return getClientForServer(multiServerProvider.onlineServerIds.first);
  }

  /// 获取 serverId 的客户端，并带有回退到第一个可用服务器的逻辑
  /// 适用于可能没有 serverId 的项目
  PlexClient getClientWithFallback(String? serverId) {
    if (serverId != null) {
      return getClientForServer(serverId);
    }
    return getFirstAvailableClient();
  }
}
