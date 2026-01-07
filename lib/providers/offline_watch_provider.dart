import 'package:flutter/foundation.dart';

import '../models/plex_metadata.dart';
import '../services/offline_watch_sync_service.dart';
import '../services/plex_api_cache.dart';
import 'download_provider.dart';

/// 用于离线观看状态 UI 状态的 Provider。
///
/// 提供：
/// - 有效的观看状态 (本地更改 + 缓存的服务器数据)
/// - 剧集的离线 "OnDeck" (待播项目) 计算
/// - 离线时手动标记已看/未看
class OfflineWatchProvider extends ChangeNotifier {
  final OfflineWatchSyncService _syncService;
  final DownloadProvider _downloadProvider;
  // ignore: unused_field - 为将来的缓存元数据查找保留
  final PlexApiCache _apiCache;

  OfflineWatchProvider({
    required OfflineWatchSyncService syncService,
    required DownloadProvider downloadProvider,
    required PlexApiCache apiCache,
  }) : _syncService = syncService,
       _downloadProvider = downloadProvider,
       _apiCache = apiCache {
    // 监听同步服务更改以更新 UI
    _syncService.addListener(_onSyncServiceChanged);
  }

  void _onSyncServiceChanged() {
    notifyListeners();
  }

  /// 同步是否正在进行中
  bool get isSyncing => _syncService.isSyncing;

  /// 获取待同步项目的数量
  Future<int> getPendingSyncCount() => _syncService.getPendingSyncCount();

  /// 获取媒体项目的有效观看状态。
  ///
  /// 优先级：
  /// 1. 本地离线操作 (如果存在)
  /// 2. 来自 API 缓存的缓存服务器数据
  /// 3. 来自下载 Provider 的元数据
  ///
  /// 如果已观看，则返回 true，否则返回 false。
  Future<bool> isWatched(String globalKey) async {
    // 首先检查本地离线操作
    final localStatus = await _syncService.getLocalWatchStatus(globalKey);
    if (localStatus != null) {
      return localStatus;
    }

    // 回退到缓存的元数据
    final metadata = _downloadProvider.getMetadata(globalKey);
    if (metadata != null) {
      return metadata.isWatched;
    }

    return false;
  }

  /// 使用缓存的元数据同步检查观看状态。
  ///
  /// 这对于无法等待的 UI 很有用，但可能无法反映
  /// 最新的本地操作。
  bool isWatchedSync(PlexMetadata metadata) {
    // 注意：这不会同步检查本地操作
    // 因为这需要异步数据库访问。
    // 为了实时准确性，请改用 isWatched()。
    return metadata.isWatched;
  }

  /// 获取媒体项目的有效播放偏移量 (续播位置)。
  ///
  /// 优先级：
  /// 1. 本地离线进度 (如果存在)
  /// 2. 来自下载 Provider 的元数据
  ///
  /// 如果没有位置信息，则返回 null。
  Future<int?> getViewOffset(String globalKey) async {
    // 首先检查本地离线进度
    final localOffset = await _syncService.getLocalViewOffset(globalKey);
    if (localOffset != null) {
      return localOffset;
    }

    // 回退到缓存的元数据
    final metadata = _downloadProvider.getMetadata(globalKey);
    return metadata?.viewOffset;
  }

  /// 获取剧集的排序剧集 (按季，然后按集数)。
  List<PlexMetadata> _getSortedEpisodes(String showRatingKey) {
    final episodes = _downloadProvider.getDownloadedEpisodesForShow(showRatingKey);
    if (episodes.isEmpty) return episodes;

    episodes.sort((a, b) {
      final seasonCompare = (a.parentIndex ?? 0).compareTo(b.parentIndex ?? 0);
      if (seasonCompare != 0) return seasonCompare;
      return (a.index ?? 0).compareTo(b.index ?? 0);
    });

    return episodes;
  }

  /// 批量解析一组剧集的观看状态。
  ///
  /// 返回每集 globalKey -> isWatched 的映射。
  Future<Map<String, bool>> _resolveEpisodeWatchStatuses(List<PlexMetadata> episodes) async {
    if (episodes.isEmpty) return {};

    final globalKeys = episodes.map((e) => e.globalKey).toSet();
    final localStatuses = await _syncService.getLocalWatchStatusesBatched(globalKeys);

    return {
      for (final episode in episodes)
        episode.globalKey:
            localStatuses[episode.globalKey] ?? _downloadProvider.getMetadata(episode.globalKey)?.isWatched ?? false,
    };
  }

  /// 查找剧集的下一个未观看的已下载剧集。
  ///
  /// 这是“离线 OnDeck”计算 - 查找第一个
  /// 尚未观看 (或正在观看) 的剧集。
  ///
  /// 剧集按季号排序，然后按集号排序。
  ///
  /// 返回下一个未观看的剧集，如果全部已看，则返回第一集。
  Future<PlexMetadata?> getNextUnwatchedEpisode(String showRatingKey) async {
    final episodes = _getSortedEpisodes(showRatingKey);
    if (episodes.isEmpty) return null;

    final watchStatuses = await _resolveEpisodeWatchStatuses(episodes);

    // 查找第一个未观看的剧集
    for (final episode in episodes) {
      if (!watchStatuses[episode.globalKey]!) {
        return episode;
      }
    }

    // 所有剧集均已观看 - 返回第一集以供重播
    return episodes.first;
  }

  /// 同步查找下一个未观看的已下载剧集。
  ///
  /// 这使用缓存的元数据而不检查本地离线操作。
  /// 为了实时准确性，请改用 getNextUnwatchedEpisode()。
  PlexMetadata? getNextUnwatchedEpisodeSync(String showRatingKey) {
    final episodes = _getSortedEpisodes(showRatingKey);
    if (episodes.isEmpty) return null;

    // 查找第一个未观看的剧集 (使用元数据的 isWatched)
    for (final episode in episodes) {
      if (!episode.isWatched) {
        return episode;
      }
    }

    // 所有剧集均已观看 - 返回第一集以供重播
    return episodes.first;
  }

  /// 在离线时将项目标记为已看。
  ///
  /// 这会将操作加入队列，以便在在线时同步。
  Future<void> markAsWatched({required String serverId, required String ratingKey}) async {
    await _syncService.queueMarkWatched(serverId: serverId, ratingKey: ratingKey);
    notifyListeners();
  }

  /// 在离线时将项目标记为未看。
  ///
  /// 这会将操作加入队列，以便在在线时同步。
  Future<void> markAsUnwatched({required String serverId, required String ratingKey}) async {
    await _syncService.queueMarkUnwatched(serverId: serverId, ratingKey: ratingKey);
    notifyListeners();
  }

  /// 获取剧集的已下载剧集及其观看状态。
  ///
  /// 返回 (episode, isWatched) 对的列表。
  /// 为了效率，使用批量数据库查询。
  Future<List<(PlexMetadata episode, bool isWatched)>> getEpisodesWithWatchStatus(String showRatingKey) async {
    final episodes = _downloadProvider.getDownloadedEpisodesForShow(showRatingKey);
    if (episodes.isEmpty) return [];

    final watchStatuses = await _resolveEpisodeWatchStatuses(episodes);

    return [for (final episode in episodes) (episode, watchStatuses[episode.globalKey]!)];
  }

  /// 触发待处理项目的手动同步。
  Future<void> syncNow() async {
    await _syncService.syncPendingItems();
  }

  @override
  void dispose() {
    _syncService.removeListener(_onSyncServiceChanged);
    super.dispose();
  }
}
