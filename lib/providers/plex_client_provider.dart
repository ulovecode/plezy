import 'package:flutter/foundation.dart';
import '../services/plex_client.dart';
import '../utils/app_logger.dart';

/// 管理单个 PlexClient 实例并将其提供给 UI 的 Provider。
/// 通常用于当前正在与之交互的主服务器。
class PlexClientProvider extends ChangeNotifier {
  PlexClient? _client;

  /// 获取当前的 PlexClient 实例。
  PlexClient? get client => _client;

  /// 设置新的 PlexClient 实例。
  void setClient(PlexClient client) {
    _client = client;
    appLogger.d('PlexClientProvider: Client set');
    notifyListeners();
  }

  /// 更新当前客户端的认证令牌。
  void updateToken(String newToken) {
    if (_client != null) {
      _client!.updateToken(newToken);
      appLogger.d('PlexClientProvider: Token updated');
      notifyListeners();
    } else {
      appLogger.w('PlexClientProvider: Cannot update token - no client set');
    }
  }

  /// 清除当前的客户端实例（例如在注销时）。
  void clearClient() {
    _client = null;
    appLogger.d('PlexClientProvider: Client cleared');
    notifyListeners();
  }
}
