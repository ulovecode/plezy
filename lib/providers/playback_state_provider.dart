import 'package:flutter/foundation.dart';
import '../models/plex_metadata.dart';
import '../models/play_queue_response.dart';
import '../services/plex_client.dart';

/// 播放模式类型
///
/// 目前所有播放都使用 Plex 播放队列。
enum PlaybackMode {
  playQueue, // 基于播放队列的播放 (顺序、随机、播放列表、合集)
}

/// 尝试定位当前队列索引的结果。
class _IndexLookupResult {
  final int? index;
  final bool attemptedLoad;
  final bool loadFailed;

  const _IndexLookupResult({this.index, this.attemptedLoad = false, this.loadFailed = false});
}

/// 使用 Plex 的播放队列 API 管理播放状态。
/// 此 Provider 仅限会话，不会在应用重启后持久化。
class PlaybackStateProvider with ChangeNotifier {
  // 播放队列状态
  int? _playQueueId;
  int _playQueueTotalCount = 0;
  bool _playQueueShuffled = false;
  int? _currentPlayQueueItemID;

  // 窗口化项目 (在当前位置周围加载)
  List<PlexMetadata> _loadedItems = [];
  final int _windowSize = 50; // 内存中保留的项目数

  // 用于向后兼容的旧状态
  String? _contextKey; // 此会话的剧集/季/播放列表 ratingKey
  PlaybackMode? _playbackMode;

  // 用于加载更多项目的客户端引用
  PlexClient? _client;

  /// 当前播放模式 (如果没有活动队列则为 null)
  PlaybackMode? get playbackMode => _playbackMode;

  /// 随机模式当前是否处于活动状态
  bool get isShuffleActive => _playQueueShuffled;

  /// 播放列表/合集模式当前是否处于活动状态
  bool get isPlaylistActive => _playbackMode == PlaybackMode.playQueue;

  /// 是否存在任何基于队列的活动播放
  bool get isQueueActive => _playQueueId != null && _playbackMode == PlaybackMode.playQueue;

  /// 当前会话的上下文键 (剧集/季/播放列表 ratingKey)
  String? get shuffleContextKey => _contextKey;

  /// 当前播放队列 ID
  int? get playQueueId => _playQueueId;

  /// 播放队列中的项目总数
  int get queueLength => _playQueueTotalCount;

  /// 获取在队列中的当前位置 (从 1 开始)
  int get currentPosition {
    if (_currentPlayQueueItemID == null || _loadedItems.isEmpty) return 0;
    final index = _loadedItems.indexWhere((item) => item.playQueueItemID == _currentPlayQueueItemID);
    return index != -1 ? index + 1 : 0;
  }

  /// 设置用于加载更多项目的客户端引用
  void setClient(PlexClient client) {
    _client = client;
  }

  /// 播放新项目时更新当前播放队列项目
  void setCurrentItem(PlexMetadata metadata) {
    if (_playbackMode == PlaybackMode.playQueue && metadata.playQueueItemID != null) {
      _currentPlayQueueItemID = metadata.playQueueItemID;
      notifyListeners();
    }
  }

  /// 从播放队列初始化播放
  /// 在通过 API 创建播放队列后调用此方法
  Future<void> setPlaybackFromPlayQueue(
    PlayQueueResponse playQueue,
    String? contextKey, {
    String? serverId,
    String? serverName,
  }) async {
    _playQueueId = playQueue.playQueueID;
    // 如果 totalCount 为 null，则使用 size 或 items 长度作为备选
    _playQueueTotalCount = playQueue.playQueueTotalCount ?? playQueue.size ?? (playQueue.items?.length ?? 0);
    _playQueueShuffled = playQueue.playQueueShuffled;
    _currentPlayQueueItemID = playQueue.playQueueSelectedItemID;

    // 项目已由 PlexClient 标记了服务器信息
    _loadedItems = playQueue.items ?? [];

    _contextKey = contextKey;
    _playbackMode = PlaybackMode.playQueue;
    notifyListeners();
  }

  /// 如果需要，从播放队列加载更多项目
  /// 如果加载了更多项目，则返回 true
  Future<bool> _ensureItemsLoaded(int targetPlayQueueItemID) async {
    if (_client == null || _playQueueId == null) return false;

    // 检查目标项目是否已加载
    final hasItem = _loadedItems.any((item) => item.playQueueItemID == targetPlayQueueItemID);

    if (hasItem) return true;

    // 在目标项目周围加载一个窗口
    try {
      final response = await _client!.getPlayQueue(
        _playQueueId!,
        center: targetPlayQueueItemID.toString(),
        window: _windowSize,
      );

      if (response != null && response.items != null) {
        // 项目已由 PlexClient 标记了服务器信息
        _loadedItems = response.items!;
        // 如果 totalCount 为 null，则使用 size 或 items 长度作为备选
        _playQueueTotalCount = response.playQueueTotalCount ?? response.size ?? response.items!.length;
        _playQueueShuffled = response.playQueueShuffled;
        notifyListeners();
        return true;
      }
    } catch (e) {
      // 加载项目失败
      return false;
    }

    return false;
  }

  Future<_IndexLookupResult> _getCurrentIndex({bool loadIfMissing = false}) async {
    if (_playbackMode != PlaybackMode.playQueue || _loadedItems.isEmpty || _currentPlayQueueItemID == null) {
      return const _IndexLookupResult();
    }

    var currentIndex = _loadedItems.indexWhere((item) => item.playQueueItemID == _currentPlayQueueItemID);

    if (currentIndex != -1) {
      return _IndexLookupResult(index: currentIndex);
    }

    if (!loadIfMissing || _client == null || _playQueueId == null) {
      return const _IndexLookupResult();
    }

    final loaded = await _ensureItemsLoaded(_currentPlayQueueItemID!);
    if (!loaded) {
      return const _IndexLookupResult(attemptedLoad: true, loadFailed: true);
    }

    currentIndex = _loadedItems.indexWhere((item) => item.playQueueItemID == _currentPlayQueueItemID);

    if (currentIndex == -1) {
      return const _IndexLookupResult(attemptedLoad: true, loadFailed: true);
    }

    return _IndexLookupResult(index: currentIndex, attemptedLoad: true);
  }

  /// 获取播放队列中的下一个项目。
  /// 如果队列耗尽或当前项目不在队列中，则返回 null。
  /// [loopQueue] - 如果为 true，则在队列耗尽时从头开始
  Future<PlexMetadata?> getNextEpisode(String currentItemKey, {bool loopQueue = false}) async {
    if (_playbackMode != PlaybackMode.playQueue) {
      // 对于顺序模式，让视频播放器处理下一集
      return null;
    }

    final indexResult = await _getCurrentIndex(loadIfMissing: true);
    if (indexResult.index == null) {
      if (indexResult.loadFailed) {
        clearShuffle();
      }
      return null;
    }
    final currentIndex = indexResult.index!;

    // 检查已加载窗口中是否存在下一个项目
    if (currentIndex + 1 < _loadedItems.length) {
      final nextItem = _loadedItems[currentIndex + 1];
      // 此处不更新 _currentPlayQueueItemID - 让 setCurrentItem 在播放开始时处理
      return nextItem;
    }

    // 检查我们是否处于整个队列的末尾
    if (currentIndex + 1 >= _playQueueTotalCount) {
      if (loopQueue && _playQueueTotalCount > 0) {
        // 循环回到开头 - 加载第一个项目
        if (_client != null && _playQueueId != null) {
          final response = await _client!.getPlayQueue(_playQueueId!);
          if (response != null && response.items != null && response.items!.isNotEmpty) {
            // 项目已由 PlexClient 标记了服务器信息
            _loadedItems = response.items!;
            final firstItem = _loadedItems.first;
            // 此处不更新 _currentPlayQueueItemID - 让 setCurrentItem 在播放开始时处理
            return firstItem;
          }
        }
      }
      // 在队列末尾 - 返回 null 但保持队列活动，以便用户仍可以返回
      return null;
    }

    // 需要加载下一个窗口
    if (_client != null && _playQueueId != null) {
      // 加载以当前项目之后的项目为中心的下一个窗口
      final nextItemID = _loadedItems.last.playQueueItemID;
      if (nextItemID != null) {
        final loaded = await _ensureItemsLoaded(nextItemID + 1);
        if (loaded) {
          // 使用新加载的项目再次尝试
          return getNextEpisode(currentItemKey, loopQueue: loopQueue);
        }
      }
    }

    return null;
  }

  /// 获取播放队列中的上一个项目。
  /// 如果处于队列开头或当前项目不在队列中，则返回 null。
  Future<PlexMetadata?> getPreviousEpisode(String currentItemKey) async {
    if (_playbackMode != PlaybackMode.playQueue) {
      // 对于顺序模式，让视频播放器处理前一集
      return null;
    }

    final currentIndex = (await _getCurrentIndex()).index;
    if (currentIndex == null) return null;

    // 检查已加载窗口中是否存在上一个项目
    if (currentIndex > 0) {
      final prevItem = _loadedItems[currentIndex - 1];
      // 此处不更新 _currentPlayQueueItemID - 让 setCurrentItem 在播放开始时处理
      return prevItem;
    }

    // 检查我们是否处于整个队列的开头
    if (currentIndex == 0) {
      return null;
    }

    // 需要加载上一个窗口
    if (_client != null && _playQueueId != null) {
      final prevItemID = _loadedItems.first.playQueueItemID;
      if (prevItemID != null && prevItemID > 0) {
        final loaded = await _ensureItemsLoaded(prevItemID - 1);
        if (loaded) {
          return getPreviousEpisode(currentItemKey);
        }
      }
    }

    return null;
  }

  /// 清除播放队列并退出队列模式
  void clearShuffle() {
    _playQueueId = null;
    _playQueueTotalCount = 0;
    _playQueueShuffled = false;
    _currentPlayQueueItemID = null;
    _loadedItems = [];
    _contextKey = null;
    _playbackMode = null;
    notifyListeners();
  }
}
