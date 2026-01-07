import 'dart:async';

/// 媒体库刷新事件的类型
enum LibraryRefreshType { collections, playlists }

/// 用于触发媒体库标签页刷新的通知器。
///
/// 单例模式，具有可重新初始化的状态。控制器是延迟创建的，
/// 如果已释放且稍后被访问，则会自动重新创建。
class LibraryRefreshNotifier {
  static final LibraryRefreshNotifier _instance = LibraryRefreshNotifier._internal();

  factory LibraryRefreshNotifier() => _instance;

  LibraryRefreshNotifier._internal();

  /// 统一的流控制器（延迟创建，可重新初始化）
  StreamController<LibraryRefreshType>? _controller;

  /// 确保控制器存在（如果为空或已关闭则创建）
  StreamController<LibraryRefreshType> get _ensureController {
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<LibraryRefreshType>.broadcast();
    }
    return _controller!;
  }

  /// 所有刷新事件的统一流
  Stream<LibraryRefreshType> get stream => _ensureController.stream;

  /// 集合标签页的流（向后兼容）
  Stream<void> get collectionsStream => stream.where((t) => t == LibraryRefreshType.collections).map((_) {});

  /// 播放列表标签页的流（向后兼容）
  Stream<void> get playlistsStream => stream.where((t) => t == LibraryRefreshType.playlists).map((_) {});

  /// 通知集合已更改
  void notifyCollectionsChanged() {
    _ensureController.add(LibraryRefreshType.collections);
  }

  /// 通知播放列表已更改
  void notifyPlaylistsChanged() {
    _ensureController.add(LibraryRefreshType.playlists);
  }

  /// 释放控制器（稍后可以通过访问流重新初始化）
  void dispose() {
    _controller?.close();
    _controller = null;
  }
}
