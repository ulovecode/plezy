import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 用于在整个应用中跟踪全屏状态的全局管理器
class FullscreenStateManager extends ChangeNotifier with WindowListener {
  static final FullscreenStateManager _instance = FullscreenStateManager._internal();

  factory FullscreenStateManager() => _instance;

  FullscreenStateManager._internal();

  bool _isFullscreen = false;
  bool _isListening = false;

  bool get isFullscreen => _isFullscreen;

  /// 手动设置全屏状态 (由 macOS 上的 NSWindowDelegate 回调调用)
  void setFullscreen(bool value) {
    if (_isFullscreen != value) {
      _isFullscreen = value;
      notifyListeners();
    }
  }

  /// 开始监控全屏状态
  void startMonitoring() {
    if (!_shouldMonitor() || _isListening) return;

    // Windows/Linux 使用 window_manager 监听器
    // macOS 则使用 NSWindowDelegate 回调 (见 FullscreenWindowDelegate)
    if (!Platform.isMacOS) {
      windowManager.addListener(this);
      _isListening = true;
    }
  }

  /// 停止监控全屏状态
  void stopMonitoring() {
    if (_isListening) {
      windowManager.removeListener(this);
      _isListening = false;
    }
  }

  bool _shouldMonitor() {
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  // Windows/Linux 的 WindowListener 回调
  @override
  void onWindowEnterFullScreen() {
    setFullscreen(true);
  }

  @override
  void onWindowLeaveFullScreen() {
    setFullscreen(false);
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
