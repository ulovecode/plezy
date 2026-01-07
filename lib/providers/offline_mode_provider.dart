import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/multi_server_manager.dart';

/// 根据网络连接和服务器可达性跟踪离线模式状态。
class OfflineModeProvider extends ChangeNotifier {
  final MultiServerManager _serverManager;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<Map<String, bool>>? _serverStatusSubscription;

  bool _hasNetworkConnection = true;
  late bool _hasServerConnection;
  bool _isInitialized = false;

  OfflineModeProvider(this._serverManager) : _hasServerConnection = _serverManager.onlineServerIds.isNotEmpty;

  /// 应用当前是否处于离线模式
  /// 离线 = 无网络 或 无可达服务器
  bool get isOffline => !_hasNetworkConnection || !_hasServerConnection;

  /// 是否有网络连接 (WiFi、移动数据等)
  bool get hasNetworkConnection => _hasNetworkConnection;

  /// 是否至少有一个 Plex 服务器可达
  bool get hasServerConnection => _hasServerConnection;

  /// 更新网络和服务器连接标志
  Future<void> _updateConnectionFlags() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    _hasNetworkConnection = !connectivityResult.contains(ConnectivityResult.none);
    _hasServerConnection = _serverManager.onlineServerIds.isNotEmpty;
  }

  /// 初始化 Provider 并开始监控
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // 检查初始连接状态
    await _updateConnectionFlags();

    // 监控网络连接变化
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = isOffline;
      _hasNetworkConnection = !results.contains(ConnectivityResult.none);

      if (wasOffline != isOffline) {
        notifyListeners();
      }
    });

    // 监控来自 MultiServerManager 的服务器状态
    _serverStatusSubscription = _serverManager.statusStream.listen((statusMap) {
      final wasOffline = isOffline;
      _hasServerConnection = statusMap.values.any((isOnline) => isOnline);

      if (wasOffline != isOffline) {
        notifyListeners();
      }
    });

    notifyListeners();
  }

  /// 强制刷新连接状态
  Future<void> refresh() async {
    await _updateConnectionFlags();
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _serverStatusSubscription?.cancel();
    super.dispose();
  }
}
