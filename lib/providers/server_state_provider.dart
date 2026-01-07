import 'package:flutter/foundation.dart';

/// 用于跟踪特定服务器 UI 状态的 Provider
/// 管理当前在详情视图中处于上下文的服务器
class ServerStateProvider extends ChangeNotifier {
  String? _currentServerId;
  final Map<String, bool> _serverConnectionStates = {};
  final Map<String, String?> _serverErrors = {};

  /// 获取当前选定的服务器 ID（用于详情视图）
  String? get currentServerId => _currentServerId;

  /// 设置当前的服务器上下文（例如，当从特定服务器查看库时）
  void setCurrentServer(String? serverId) {
    if (_currentServerId != serverId) {
      _currentServerId = serverId;
      notifyListeners();
    }
  }

  /// 清除当前服务器的选择
  void clearCurrentServer() {
    if (_currentServerId != null) {
      _currentServerId = null;
      notifyListeners();
    }
  }

  /// 获取服务器的连接状态
  bool isServerConnected(String serverId) {
    return _serverConnectionStates[serverId] ?? false;
  }

  /// 更新服务器的连接状态
  void updateServerConnectionState(String serverId, bool isConnected) {
    if (_serverConnectionStates[serverId] != isConnected) {
      _serverConnectionStates[serverId] = isConnected;
      notifyListeners();
    }
  }

  /// 获取服务器的错误消息（如果没有错误则为 null）
  String? getServerError(String serverId) {
    return _serverErrors[serverId];
  }

  /// 设置服务器的错误
  void setServerError(String serverId, String? error) {
    _serverErrors[serverId] = error;
    notifyListeners();
  }

  /// 清除服务器的错误
  void clearServerError(String serverId) {
    if (_serverErrors.containsKey(serverId)) {
      _serverErrors.remove(serverId);
      notifyListeners();
    }
  }

  /// 清除所有服务器错误
  void clearAllServerErrors() {
    if (_serverErrors.isNotEmpty) {
      _serverErrors.clear();
      notifyListeners();
    }
  }

  /// 重置所有状态
  void reset() {
    _currentServerId = null;
    _serverConnectionStates.clear();
    _serverErrors.clear();
    notifyListeners();
  }
}
