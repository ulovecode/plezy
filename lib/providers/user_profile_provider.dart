import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/plex_home.dart';
import '../models/plex_home_user.dart';
import '../models/plex_user_profile.dart';
import '../services/plex_auth_service.dart';
import '../services/storage_service.dart';
import '../utils/app_logger.dart';
import '../utils/provider_extensions.dart';
import '../screens/profile/pin_entry_dialog.dart';
import 'plex_client_provider.dart';

/// 用于管理 Plex 用户个人资料、Home 用户切换和个人资料设置的 Provider。
class UserProfileProvider extends ChangeNotifier {
  PlexHome? _home;
  PlexHomeUser? _currentUser;
  PlexUserProfile? _profileSettings;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;

  /// 获取当前的 Plex Home 数据（包含所有 Home 用户）
  PlexHome? get home => _home;

  /// 获取当前登录的 Home 用户
  PlexHomeUser? get currentUser => _currentUser;

  /// 获取当前用户的个人资料设置（如语言偏好）
  PlexUserProfile? get profileSettings => _profileSettings;

  /// 是否正在加载数据
  bool get isLoading => _isLoading;

  /// 获取当前的错误消息
  String? get error => _error;

  /// 判断当前 Home 是否有多个用户
  bool get hasMultipleUsers {
    final result = _home?.hasMultipleUsers ?? false;
    appLogger.d('hasMultipleUsers: _home=${_home != null}, users count=${_home?.users.length ?? 0}, result=$result');
    return result;
  }

  PlexAuthService? _authService;
  StorageService? _storageService;

  // 切换个人资料时数据失效的回调
  // 接收带有新个人资料令牌的服务器列表，用于重新连接
  Future<void> Function(List<PlexServer>)? _onDataInvalidationRequested;

  /// 设置当切换个人资料需要数据失效时调用的回调
  /// 回调接收包含新个人资料访问令牌的服务器列表
  void setDataInvalidationCallback(Future<void> Function(List<PlexServer>)? callback) {
    _onDataInvalidationRequested = callback;
  }

  /// 使用新个人资料的服务器为所有屏幕触发数据失效
  Future<void> _invalidateAllData(List<PlexServer> servers) async {
    if (_onDataInvalidationRequested != null) {
      await _onDataInvalidationRequested!(servers);
      appLogger.d('Data invalidation triggered for profile switch with ${servers.length} servers');
    }
  }

  /// 初始化 Provider，加载缓存数据并刷新设置
  Future<void> initialize() async {
    // 防止重复初始化
    if (_isInitialized) {
      appLogger.d('UserProfileProvider: Already initialized, skipping');
      return;
    }

    appLogger.d('UserProfileProvider: Initializing...');
    try {
      _authService = await PlexAuthService.create();
      _storageService = await StorageService.getInstance();
      await _loadCachedData();

      // 如果没有缓存的 Home 数据或已过期，尝试从 API 加载
      if (_home == null) {
        appLogger.d('UserProfileProvider: No cached home data, attempting to load from API');
        try {
          await loadHomeUsers();
        } catch (e) {
          appLogger.w('UserProfileProvider: Failed to load home users during initialization', error: e);
          // 这里不设置错误，因为对应用启动不是关键的
        }
      }

      // 从 API 获取最新的个人资料设置
      appLogger.d('UserProfileProvider: Fetching profile settings from API');
      try {
        await refreshProfileSettings();
      } catch (e) {
        appLogger.w('UserProfileProvider: Failed to fetch profile settings during initialization', error: e);
        // 这里不设置错误，因为可能已经加载了缓存的个人资料
      }

      _isInitialized = true;
      appLogger.d('UserProfileProvider: Initialization complete');
    } catch (e) {
      appLogger.e('UserProfileProvider: Critical initialization failure', error: e);
      _setError('Failed to initialize profile services');
      // 失败时确保服务为 null
      _authService = null;
      _storageService = null;
      _isInitialized = false; // 允许失败后重试
    }
  }

  /// 加载本地缓存的 Home 用户和当前用户数据
  Future<void> _loadCachedData() async {
    if (_storageService == null) return;

    // 加载缓存的 Home 用户
    final cachedHomeData = _storageService!.getHomeUsersCache();
    if (cachedHomeData != null) {
      try {
        _home = PlexHome.fromJson(cachedHomeData);
      } catch (e) {
        appLogger.w('Failed to load cached home data', error: e);
      }
    }

    // 加载当前用户 UUID
    final currentUserUUID = _storageService!.getCurrentUserUUID();
    if (currentUserUUID != null && _home != null) {
      _currentUser = _home!.getUserByUUID(currentUserUUID);
    }

    // 个人资料设置不进行缓存 - 它们将在 refreshProfileSettings() 中从 API 获取最新的
    notifyListeners();
  }

  /// 从 API 获取用户的个人资料设置（如音频/字幕语言偏好）
  Future<void> refreshProfileSettings() async {
    if (_authService == null || _storageService == null) {
      appLogger.w('refreshProfileSettings: Services not initialized, skipping');
      return;
    }

    appLogger.d('Fetching user profile settings from Plex API');
    try {
      final currentToken = _storageService!.getPlexToken();
      if (currentToken == null) {
        appLogger.w('refreshProfileSettings: No Plex token available, cannot fetch profile');
        return;
      }

      final profile = await _authService!.getUserProfile(currentToken);
      _profileSettings = profile;

      appLogger.i('Successfully fetched user profile settings from API');

      notifyListeners();
    } catch (e) {
      appLogger.w('Failed to fetch user profile settings from API', error: e);
      // 不设置错误状态，个人资料将保持 null 或保留现有值
    }
  }

  /// 加载 Plex Home 用户列表
  /// [forceRefresh] 如果为 true，则强制从 API 刷新而不是使用缓存
  Future<void> loadHomeUsers({bool forceRefresh = false}) async {
    appLogger.d('loadHomeUsers called - forceRefresh: $forceRefresh');

    // 如果服务未就绪，自动初始化
    if (_authService == null || _storageService == null) {
      appLogger.d('loadHomeUsers: Services not initialized, initializing services...');
      _authService = await PlexAuthService.create();
      _storageService = await StorageService.getInstance();
      await _loadCachedData();

      // 初始化后再次检查
      if (_authService == null || _storageService == null) {
        appLogger.e('loadHomeUsers: Failed to initialize services');
        _setError('Failed to initialize services');
        return;
      }
    }

    // 如果不强制刷新且已有缓存数据，则直接使用
    if (!forceRefresh && _home != null) {
      appLogger.d('loadHomeUsers: Using cached data, users count: ${_home!.users.length}');
      return;
    }

    _setLoading(true);
    _clearError();

    try {
      final currentToken = _storageService!.getPlexToken();
      if (currentToken == null) {
        throw Exception('No Plex.tv authentication token available');
      }
      appLogger.d('loadHomeUsers: Using Plex.tv token');

      appLogger.d('loadHomeUsers: Fetching home users from API');
      final home = await _authService!.getHomeUsers(currentToken);
      _home = home;

      appLogger.i('loadHomeUsers: Success! Home users count: ${home.users.length}');
      appLogger.d('loadHomeUsers: Users: ${home.users.map((u) => u.displayName).join(', ')}');

      // 缓存 Home 数据
      await _storageService!.saveHomeUsersCache(home.toJson());

      // 如果尚未设置当前用户，则尝试从存储中加载或默认为管理员
      if (_currentUser == null) {
        final currentUserUUID = _storageService!.getCurrentUserUUID();
        if (currentUserUUID != null) {
          _currentUser = home.getUserByUUID(currentUserUUID);
          appLogger.d('loadHomeUsers: Set current user from UUID: ${_currentUser?.displayName}');
        } else {
          // 如果没有设置当前用户，默认为管理员用户
          _currentUser = home.adminUser;
          if (_currentUser != null) {
            await _storageService!.saveCurrentUserUUID(_currentUser!.uuid);
            appLogger.d('loadHomeUsers: Set current user to admin: ${_currentUser?.displayName}');
          }
        }
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to load home users: $e');
      appLogger.e('Failed to load home users', error: e);
    } finally {
      _setLoading(false);
    }
  }

  /// 切换到不同的 Home 用户
  /// 如果用户设置了 PIN 码，将弹窗要求输入
  Future<bool> switchToUser(PlexHomeUser user, BuildContext? context) async {
    if (_authService == null || _storageService == null) {
      _setError('Services not initialized');
      return false;
    }

    if (user.uuid == _currentUser?.uuid) {
      // 已经是该用户
      return true;
    }

    // 在异步操作前提取 client provider
    PlexClientProvider? clientProvider;
    if (context != null) {
      try {
        clientProvider = context.plexClient;
      } catch (e) {
        appLogger.w('Failed to get PlexClientProvider', error: e);
      }
    }

    _setLoading(true);
    _clearError();

    return await _attemptUserSwitch(user, context, clientProvider, null);
  }

  /// 尝试执行用户切换的内部逻辑，支持 PIN 码重试
  Future<bool> _attemptUserSwitch(
    PlexHomeUser user,
    BuildContext? context,
    PlexClientProvider? clientProvider,
    String? errorMessage,
  ) async {
    try {
      final currentToken = _storageService!.getPlexToken();
      if (currentToken == null) {
        throw Exception('No Plex.tv authentication token available');
      }

      // 检查用户是否需要 PIN 码
      String? pin;
      if (user.requiresPassword && context != null && context.mounted) {
        pin = await showPinEntryDialog(context, user.displayName, errorMessage: errorMessage);

        // 用户取消了 PIN 对话框
        if (pin == null) {
          _setLoading(false);
          return false;
        }
      }

      final switchResponse = await _authService!.switchToUser(user.uuid, currentToken, pin: pin);

      // switchResponse.authToken 是新用户的 Plex.tv 令牌
      // 使用此令牌获取服务器列表以获取正确的服务器访问令牌
      appLogger.d('Got new user Plex.tv token, fetching servers...');

      final servers = await _authService!.fetchServers(switchResponse.authToken);
      if (servers.isEmpty) {
        throw Exception('No servers available for this user');
      }

      appLogger.d('Fetched ${servers.length} servers for new profile');

      // 保存新的 Plex.tv 令牌供将来使用
      await _storageService!.savePlexToken(switchResponse.authToken);

      // 在存储中更新当前用户 UUID
      await _storageService!.saveCurrentUserUUID(user.uuid);

      // 更新当前用户
      _currentUser = user;

      // 更新用户个人资料设置（从 API 获取最新的）
      _profileSettings = switchResponse.profile;
      appLogger.d(
        'Updated profile settings for user: ${user.displayName}',
        error: {
          'defaultAudioLanguage': _profileSettings?.defaultAudioLanguage ?? 'not set',
          'defaultSubtitleLanguage': _profileSettings?.defaultSubtitleLanguage ?? 'not set',
        },
      );

      notifyListeners();

      // 使所有缓存数据失效并使用新令牌重新连接到所有服务器
      // 回调将使用服务器列表处理服务器重新连接
      await _invalidateAllData(servers);

      appLogger.d('Profile switch complete, all servers reconnected with new tokens');

      appLogger.i('Successfully switched to user: ${user.displayName}');
      return true;
    } catch (e) {
      // 检查是否是 PIN 码验证错误
      if (e is DioException && e.response?.statusCode == 403) {
        final errors = e.response?.data['errors'] as List?;
        if (errors != null && errors.isNotEmpty) {
          final errorCode = errors[0]['code'] as int?;
          final errorMessage = errors[0]['message'] as String?;

          // 错误代码 1041 表示 PIN 码无效
          if (errorCode == 1041) {
            appLogger.w('Invalid PIN for user: ${user.displayName}');
            _clearError(); // 清除之前的错误状态

            // 如果 context 仍然有效，携带错误消息重试
            if (context != null && context.mounted) {
              return await _attemptUserSwitch(
                user,
                context,
                clientProvider,
                errorMessage ?? 'Incorrect PIN. Please try again.',
              );
            }

            // 如果 context 不可用，返回 false 而不显示错误
            appLogger.d('Cannot retry PIN entry - context not available');
            return false;
          }
        }
      }

      // 对于非 PIN 验证错误显示错误消息
      _setError('Failed to switch user: $e');
      appLogger.e('Failed to switch to user: ${user.displayName}', error: e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 刷新当前用户数据
  Future<void> refreshCurrentUser() async {
    if (_currentUser != null) {
      await loadHomeUsers(forceRefresh: true);

      // 从刷新后的数据中更新当前用户
      if (_home != null) {
        _currentUser = _home!.getUserByUUID(_currentUser!.uuid);
        notifyListeners();
      }
    }
  }

  /// 注销用户，清除所有本地数据
  Future<void> logout() async {
    if (_storageService == null) return;

    _setLoading(true);

    try {
      await _storageService!.clearUserData();

      // 清除用户特定的 Provider 状态，但保留服务供将来登录使用
      _home = null;
      _currentUser = null;
      _profileSettings = null;
      _onDataInvalidationRequested = null;

      _clearError();
      notifyListeners();

      appLogger.i('User logged out successfully');
    } catch (e) {
      appLogger.e('Error during logout', error: e);
    } finally {
      _setLoading(false);
    }
  }

  /// 为新的服务器上下文刷新 Provider
  /// 切换服务器时调用此方法以确保 Provider 状态同步
  Future<void> refreshForNewServer([BuildContext? context]) async {
    appLogger.d('UserProfileProvider: Refreshing for new server context');

    _setLoading(true);

    try {
      // 清除之前服务器的缓存数据（内存和存储）
      _home = null;
      _currentUser = null;
      _profileSettings = null;
      _clearError();

      // 使用当前的存储状态重新初始化服务
      _authService = await PlexAuthService.create();
      _storageService = await StorageService.getInstance();

      // 清除特定于之前服务器上下文的存储状态
      await Future.wait([
        // 清除 Home 用户缓存（特定于服务器）
        _storageService!.clearHomeUsersCache(),
        // 清除当前用户 UUID（特定于个人资料，不应跨服务器持久化）
        _storageService!.clearCurrentUserUUID(),
      ]);

      appLogger.d('UserProfileProvider: Cleared previous server storage state');

      // 加载新服务器的缓存数据（清除缓存后应为空）
      await _loadCachedData();

      // 由于清除了缓存，从 API 加载
      appLogger.d('UserProfileProvider: Loading fresh home users for new server');

      // 在异步操作前存储 context 引用，以避免 build context 警告
      final contextForSwitch = context;

      try {
        await loadHomeUsers();

        // 加载 Home 用户后，如果设置了当前用户（管理员用户），
        // 执行完整的个人资料切换以确保令牌正确更新
        if (_currentUser != null && contextForSwitch != null) {
          appLogger.d(
            'UserProfileProvider: Performing complete profile switch to ${_currentUser!.displayName} for new server',
          );

          // 执行完整的个人资料切换，包括 API 调用和令牌更新
          final userToSwitchTo = _currentUser!;
          // ignore: use_build_context_synchronously
          final success = await switchToUser(userToSwitchTo, contextForSwitch);

          if (success) {
            appLogger.d('UserProfileProvider: Successfully switched to admin user for new server');
          } else {
            appLogger.w('UserProfileProvider: Failed to complete profile switch for new server');
          }
        } else if (_currentUser != null && contextForSwitch == null) {
          appLogger.w('UserProfileProvider: Cannot perform complete profile switch - no context provided');
          // 即使没有完整切换，仍尝试刷新个人资料设置
          try {
            await refreshProfileSettings();
          } catch (e) {
            appLogger.w('UserProfileProvider: Failed to refresh profile settings for new server', error: e);
          }
        }
      } catch (e) {
        appLogger.w('UserProfileProvider: Failed to load home users for new server', error: e);
        // 不设置错误，因为这不是关键的
      }

      appLogger.d('UserProfileProvider: Refresh for new server complete');
    } catch (e) {
      appLogger.e('UserProfileProvider: Failed to refresh for new server', error: e);
      _setError('Failed to refresh for new server');
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }
}
