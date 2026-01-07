import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:plezy/utils/content_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_models.dart';
import '../models/plex_metadata.dart';
import '../services/download_manager_service.dart';
import '../services/download_storage_service.dart';
import '../services/plex_api_cache.dart';
import '../services/plex_client.dart';
import '../utils/app_logger.dart';
import '../utils/plex_cache_parser.dart';

/// 保存下载作品的 Plex 缩略图路径引用。
/// 实际文件路径由 serverId + 缩略图路径的哈希值计算得出。
class DownloadedArtwork {
  /// Plex 缩略图路径 (例如 /library/metadata/12345/thumb/1234567890)
  final String? thumbPath;

  const DownloadedArtwork({this.thumbPath});

  /// 获取此作品的本地文件路径
  String? getLocalPath(DownloadStorageService storage, String serverId) {
    if (thumbPath == null) return null;
    return storage.getArtworkPathSync(serverId, thumbPath!);
  }
}

/// 用于管理下载状态和操作的 Provider。
class DownloadProvider extends ChangeNotifier {
  final DownloadManagerService _downloadManager;
  StreamSubscription<DownloadProgress>? _progressSubscription;
  StreamSubscription<DeletionProgress>? _deletionProgressSubscription;

  // 按 globalKey (serverId:ratingKey) 跟踪下载进度
  final Map<String, DownloadProgress> _downloads = {};

  // 存储用于显示的元数据
  final Map<String, PlexMetadata> _metadata = {};

  // 存储用于离线显示的 Plex 缩略图路径 (实际文件路径由哈希值计算)
  final Map<String, DownloadedArtwork> _artworkPaths = {};

  // 跟踪当前正在排队的项目 (正在构建下载队列)
  final Set<String> _queueing = {};

  // 跟踪当前正在删除的项目及其进度
  final Map<String, DeletionProgress> _deletionProgress = {};

  // 跟踪剧集/季的总集数 (用于检测部分下载)
  // 键: globalKey (serverId:ratingKey), 值: 总集数
  final Map<String, int> _totalEpisodeCounts = {};

  DownloadProvider({required DownloadManagerService downloadManager}) : _downloadManager = downloadManager {
    // 监听来自下载管理器的进度更新
    _progressSubscription = _downloadManager.progressStream.listen(_onProgressUpdate);

    // 监听删除进度更新
    _deletionProgressSubscription = _downloadManager.deletionProgressStream.listen(_onDeletionProgressUpdate);

    // 从数据库加载持久化的下载项
    _loadPersistedDownloads();
  }

  /// 从数据库/缓存加载所有持久化的下载项和元数据
  Future<void> _loadPersistedDownloads() async {
    try {
      // 清除现有数据以防止删除后出现陈旧条目
      _downloads.clear();
      _artworkPaths.clear();
      _metadata.clear();
      _totalEpisodeCounts.clear();

      final storageService = DownloadStorageService.instance;
      final apiCache = PlexApiCache.instance;

      // 初始化作品目录路径以便同步访问
      await storageService.getArtworkDirectory();

      // 从数据库加载所有下载项
      final downloads = await _downloadManager.getAllDownloads();
      for (final item in downloads) {
        _downloads[item.globalKey] = DownloadProgress(
          globalKey: item.globalKey,
          status: DownloadStatus.values[item.status],
          progress: item.progress,
          downloadedBytes: item.downloadedBytes,
          totalBytes: item.totalBytes ?? 0,
        );

        // 存储 Plex 缩略图路径引用 (需要时从哈希值计算文件路径)
        _artworkPaths[item.globalKey] = DownloadedArtwork(thumbPath: item.thumbPath);

        // 从 API 缓存加载元数据 (基础端点 - 数据中包含章节/标记)
        final cached = await apiCache.get(item.serverId, '/library/metadata/${item.ratingKey}');
        final firstMetadata = PlexCacheParser.extractFirstMetadata(cached);
        if (firstMetadata != null) {
          final metadata = PlexMetadata.fromJson(firstMetadata).copyWith(serverId: item.serverId);
          _metadata[item.globalKey] = metadata;

          // 对于剧集，还加载父级 (剧集和季) 的元数据
          if (metadata.isEpisode) {
            await _loadParentMetadataFromCache(metadata, apiCache);
          }
        }
      }

      // 从 SharedPreferences 加载总集数
      await _loadTotalEpisodeCounts();

      appLogger.i(
        '已加载 ${_downloads.length} 个下载项, ${_metadata.length} 个元数据条目, '
        '以及 ${_totalEpisodeCounts.length} 个剧集计数',
      );
      notifyListeners();
    } catch (e) {
      appLogger.e('加载持久化下载项失败', error: e);
    }
  }

  /// 从 SharedPreferences 加载总集数
  Future<void> _loadTotalEpisodeCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('episode_count_'));

      for (final key in keys) {
        final globalKey = key.replaceFirst('episode_count_', '');
        final count = prefs.getInt(key);
        if (count != null) {
          _totalEpisodeCounts[globalKey] = count;
          appLogger.d('📂 从 SharedPrefs 加载剧集计数: $globalKey = $count');
        }
      }

      appLogger.i('📚 从 SharedPreferences 加载了 ${_totalEpisodeCounts.length} 个剧集计数');
    } catch (e) {
      appLogger.w('加载剧集计数失败', error: e);
    }
  }

  /// 将总集数持久化到 SharedPreferences
  Future<void> _persistTotalEpisodeCount(String globalKey, int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('episode_count_$globalKey', count);
      appLogger.d('已持久化 $globalKey 的剧集计数: $count');
    } catch (e) {
      appLogger.w('持久化 $globalKey 的剧集计数失败', error: e);
    }
  }

  /// 从缓存中加载剧集的父级 (剧集和季) 元数据
  Future<void> _loadParentMetadataFromCache(PlexMetadata episode, PlexApiCache apiCache) async {
    final serverId = episode.serverId;
    if (serverId == null) return;

    // 加载剧集元数据 (基础端点)
    final showRatingKey = episode.grandparentRatingKey;
    if (showRatingKey != null) {
      final showGlobalKey = '$serverId:$showRatingKey';
      if (!_metadata.containsKey(showGlobalKey)) {
        final cached = await apiCache.get(serverId, '/library/metadata/$showRatingKey');
        final showJson = PlexCacheParser.extractFirstMetadata(cached);
        if (showJson != null) {
          final showMetadata = PlexMetadata.fromJson(showJson).copyWith(serverId: serverId);
          _metadata[showGlobalKey] = showMetadata;
          // 存储作品引用以供离线显示
          if (showMetadata.thumb != null) {
            _artworkPaths[showGlobalKey] = DownloadedArtwork(thumbPath: showMetadata.thumb);
          }
        }
      }
    }

    // 加载季元数据 (基础端点)
    final seasonRatingKey = episode.parentRatingKey;
    if (seasonRatingKey != null) {
      final seasonGlobalKey = '$serverId:$seasonRatingKey';
      if (!_metadata.containsKey(seasonGlobalKey)) {
        final cached = await apiCache.get(serverId, '/library/metadata/$seasonRatingKey');
        final seasonJson = PlexCacheParser.extractFirstMetadata(cached);
        if (seasonJson != null) {
          final seasonMetadata = PlexMetadata.fromJson(seasonJson).copyWith(serverId: serverId);
          _metadata[seasonGlobalKey] = seasonMetadata;
          // 存储作品引用以供离线显示
          if (seasonMetadata.thumb != null) {
            _artworkPaths[seasonGlobalKey] = DownloadedArtwork(thumbPath: seasonMetadata.thumb);
          }
        }
      }
    }
  }

  void _onProgressUpdate(DownloadProgress progress) {
    appLogger.d('收到进度更新: ${progress.globalKey} - ${progress.status} - ${progress.progress}%');

    _downloads[progress.globalKey] = progress;

    // 当作品路径可用时同步它们
    if (progress.hasArtworkPaths) {
      _artworkPaths[progress.globalKey] = DownloadedArtwork(thumbPath: progress.thumbPath);
    }

    appLogger.d('正在通知 ${progress.globalKey} 的监听器');
    notifyListeners();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _deletionProgressSubscription?.cancel();
    super.dispose();
  }

  /// 所有当前的下载进度条目
  Map<String, DownloadProgress> get downloads => Map.unmodifiable(_downloads);

  /// 下载项的所有元数据
  Map<String, PlexMetadata> get metadata => Map.unmodifiable(_metadata);

  /// 获取所有正在排队/下载中的项目 (用于“队列”选项卡)
  List<DownloadProgress> get queuedDownloads {
    return _downloads.values
        .where(
          (p) =>
              p.status == DownloadStatus.queued ||
              p.status == DownloadStatus.downloading ||
              p.status == DownloadStatus.paused,
        )
        .toList();
  }

  /// 获取所有已完成的下载项
  List<DownloadProgress> get completedDownloads {
    return _downloads.values.where((p) => p.status == DownloadStatus.completed).toList();
  }

  /// 获取已完成下载的电视剧剧集 (单集)
  List<PlexMetadata> get downloadedEpisodes {
    return _metadata.entries
        .where((entry) {
          final progress = _downloads[entry.key];
          return progress?.status == DownloadStatus.completed && entry.value.type == 'episode';
        })
        .map((entry) => entry.value)
        .toList();
  }

  /// 获取具有已下载剧集的唯一电视剧
  /// 返回存储的剧集元数据，如果不存在则从剧集元数据合成
  List<PlexMetadata> get downloadedShows {
    final Map<String, PlexMetadata> shows = {};

    for (final entry in _metadata.entries) {
      final globalKey = entry.key;
      final meta = entry.value;
      final progress = _downloads[globalKey];

      if (progress?.status == DownloadStatus.completed && meta.type == 'episode') {
        final showRatingKey = meta.grandparentRatingKey;
        if (showRatingKey != null && !shows.containsKey(showRatingKey)) {
          // 优先获取存储的剧集元数据
          final showGlobalKey = '${meta.serverId}:$showRatingKey';
          final storedShow = _metadata[showGlobalKey];

          if (storedShow != null && storedShow.type == 'show') {
            // 使用存储的剧集元数据 (包含年份、摘要、clearLogo)
            shows[showRatingKey] = storedShow;
          } else {
            // 备选方案：从剧集元数据合成 (缺失年份、摘要)
            shows[showRatingKey] = PlexMetadata(
              ratingKey: showRatingKey,
              key: '/library/metadata/$showRatingKey',
              type: 'show',
              title: meta.grandparentTitle ?? 'Unknown Show',
              thumb: meta.grandparentThumb,
              art: meta.grandparentArt,
              serverId: meta.serverId,
            );
          }
        }
      }
    }

    return shows.values.toList();
  }

  /// 获取已完成下载的电影
  List<PlexMetadata> get downloadedMovies {
    return _metadata.entries
        .where((entry) {
          final progress = _downloads[entry.key];
          return progress?.status == DownloadStatus.completed && entry.value.type == 'movie';
        })
        .map((entry) => entry.value)
        .toList();
  }

  /// 获取特定下载项的元数据
  PlexMetadata? getMetadata(String globalKey) => _metadata[globalKey];

  /// 获取特定下载项的作品路径 (用于离线显示)
  DownloadedArtwork? getArtworkPaths(String globalKey) => _artworkPaths[globalKey];

  /// 获取任何作品类型 (缩略图、背景图、clearLogo 等) 的本地文件路径
  /// 如果作品目录未初始化或作品路径为 null，则返回 null
  String? getArtworkLocalPath(String serverId, String? artworkPath) {
    if (artworkPath == null) return null;
    return DownloadStorageService.instance.getArtworkPathSync(serverId, artworkPath);
  }

  /// 获取特定剧集的已下载剧集 (通过 grandparentRatingKey)
  List<PlexMetadata> getDownloadedEpisodesForShow(String showRatingKey) {
    return _metadata.entries
        .where((entry) {
          final progress = _downloads[entry.key];
          final meta = entry.value;
          return progress?.status == DownloadStatus.completed &&
              meta.type == 'episode' &&
              meta.grandparentRatingKey == showRatingKey;
        })
        .map((entry) => entry.value)
        .toList();
  }

  /// 获取特定剧集的所有剧集下载项 (任何状态)
  List<DownloadProgress> _getEpisodeDownloadsForShow(String showRatingKey) {
    return _downloads.entries
        .where((entry) {
          final meta = _metadata[entry.key];
          return meta?.type == 'episode' && meta?.grandparentRatingKey == showRatingKey;
        })
        .map((entry) => entry.value)
        .toList();
  }

  /// 获取特定季的所有剧集下载项 (任何状态)
  List<DownloadProgress> _getEpisodeDownloadsForSeason(String seasonRatingKey) {
    return _downloads.entries
        .where((entry) {
          final meta = _metadata[entry.key];
          return meta?.type == 'episode' && meta?.parentRatingKey == seasonRatingKey;
        })
        .map((entry) => entry.value)
        .toList();
  }

  /// 计算剧集的总进度 (基于其所有剧集)
  /// 返回包含聚合值的合成 DownloadProgress
  DownloadProgress? getAggregateProgressForShow(String serverId, String showRatingKey) {
    return _calculateAggregateProgress(
      serverId: serverId,
      ratingKey: showRatingKey,
      episodes: _getEpisodeDownloadsForShow(showRatingKey),
      entityType: 'show',
    );
  }

  /// 计算季的总进度 (基于其所有剧集)
  /// 返回包含聚合值的合成 DownloadProgress
  DownloadProgress? getAggregateProgressForSeason(String serverId, String seasonRatingKey) {
    return _calculateAggregateProgress(
      serverId: serverId,
      ratingKey: seasonRatingKey,
      episodes: _getEpisodeDownloadsForSeason(seasonRatingKey),
      entityType: 'season',
    );
  }

  /// 用于计算剧集/季聚合下载进度的共享助手
  DownloadProgress? _calculateAggregateProgress({
    required String serverId,
    required String ratingKey,
    required List<DownloadProgress> episodes,
    required String entityType,
  }) {
    final globalKey = '$serverId:$ratingKey';

    // 诊断：检查剧集计数的所有来源
    final meta = _metadata[globalKey];
    final metadataLeafCount = meta?.leafCount;
    final storedCount = _totalEpisodeCounts[globalKey];
    final downloadedCount = episodes.length;

    appLogger.d(
      '📊 $entityType $ratingKey 的剧集计数来源:\n'
      '  - 元数据 leafCount: $metadataLeafCount\n'
      '  - 存储计数: $storedCount\n'
      '  - 已下载剧集: $downloadedCount\n'
      '  - 元数据是否存在: ${meta != null}\n'
      '  - 类型: ${meta?.type}\n'
      '  - 标题: ${meta?.title}',
    );

    // 获取总剧集数 - 优先使用 metadata.leafCount
    int totalEpisodes;
    String countSource;

    if (metadataLeafCount != null && metadataLeafCount > 0) {
      totalEpisodes = metadataLeafCount;
      countSource = 'metadata.leafCount';
    } else if (storedCount != null && storedCount > 0) {
      totalEpisodes = storedCount;
      countSource = '存储计数 (SharedPreferences)';
    } else {
      totalEpisodes = downloadedCount;
      countSource = '已下载剧集 (备选方案)';
    }

    appLogger.d('✅ 正在为 $entityType $ratingKey 使用来自 [$countSource] 的 totalEpisodes=$totalEpisodes');

    // 如果我们有存储的计数但没有下载项，检查它是否为有效的部分下载状态
    if (totalEpisodes == 0 || (episodes.isEmpty && totalEpisodes > 0)) {
      appLogger.d('⚠️  $entityType $ratingKey 没有有效的下载项，返回 null');
      return null;
    }

    // 计算聚合统计信息
    int completedCount = 0;
    int downloadingCount = 0;
    int queuedCount = 0;
    int failedCount = 0;

    for (final ep in episodes) {
      switch (ep.status) {
        case DownloadStatus.completed:
          completedCount++;
        case DownloadStatus.downloading:
          downloadingCount++;
        case DownloadStatus.queued:
          queuedCount++;
        case DownloadStatus.failed:
          failedCount++;
        default:
          break;
      }
    }

    // 确定总体状态
    final DownloadStatus overallStatus;
    if (completedCount == totalEpisodes) {
      overallStatus = DownloadStatus.completed;
    } else if (completedCount > 0 && downloadingCount == 0 && queuedCount == 0 && completedCount < totalEpisodes) {
      overallStatus = DownloadStatus.partial;
    } else if (downloadingCount > 0) {
      overallStatus = DownloadStatus.downloading;
    } else if (queuedCount > 0) {
      overallStatus = DownloadStatus.queued;
    } else if (failedCount > 0) {
      overallStatus = DownloadStatus.failed;
    } else {
      return null;
    }

    // 基于总剧集数计算总体进度百分比
    final int overallProgress = totalEpisodes > 0 ? ((completedCount * 100) / totalEpisodes).round() : 0;

    appLogger.d(
      '$entityType $ratingKey 的聚合进度: $overallProgress% '
      '($completedCount 已完成, $downloadingCount 下载中, '
      '总计 $totalEpisodes 中的 $queuedCount 个已排队) - 状态: $overallStatus',
    );

    return DownloadProgress(
      globalKey: globalKey,
      status: overallStatus,
      progress: overallProgress,
      downloadedBytes: 0,
      totalBytes: 0,
      currentFile: '$completedCount/$totalEpisodes 剧集',
    );
  }

  /// 是否存在任何下载项 (活动中或已完成)
  bool get hasDownloads => _downloads.isNotEmpty;

  /// 是否存在任何活动中的下载项
  bool get hasActiveDownloads =>
      _downloads.values.any((p) => p.status == DownloadStatus.downloading || p.status == DownloadStatus.queued);

  /// 获取特定项目的下载进度
  /// 对于剧集/季，返回其所有子剧集的聚合进度
  /// 对于剧集/电影，返回直接进度
  DownloadProgress? getProgress(String globalKey) {
    // 首先检查是否有直接进度 (针对剧集/电影)
    final directProgress = _downloads[globalKey];
    if (directProgress != null) {
      return directProgress;
    }

    // 如果没有直接进度，检查这是否是剧集或季
    // 并从剧集中计算聚合进度
    final parts = globalKey.split(':');
    if (parts.length != 2) return null;

    final serverId = parts[0];
    final ratingKey = parts[1];

    // 尝试获取元数据以确定类型
    final meta = _metadata[globalKey];
    if (meta == null) {
      // 尚未存储元数据，可能是正在排队的剧集/季
      // 检查是否存在以此为父级的任何剧集
      final episodesAsShow = _getEpisodeDownloadsForShow(ratingKey);
      if (episodesAsShow.isNotEmpty) {
        return getAggregateProgressForShow(serverId, ratingKey);
      }

      final episodesAsSeason = _getEpisodeDownloadsForSeason(ratingKey);
      if (episodesAsSeason.isNotEmpty) {
        return getAggregateProgressForSeason(serverId, ratingKey);
      }

      return null;
    }

    // 我们有元数据，检查类型
    final type = meta.type.toLowerCase();
    if (type == 'show') {
      return getAggregateProgressForShow(serverId, ratingKey);
    } else if (type == 'season') {
      return getAggregateProgressForSeason(serverId, ratingKey);
    }

    return null;
  }

  /// 检查项目是否已下载
  /// 对于剧集/季，检查所有剧集是否已下载
  bool isDownloaded(String globalKey) {
    final progress = getProgress(globalKey);
    return progress?.status == DownloadStatus.completed;
  }

  /// 检查项目是否正在下载中
  /// 对于剧集/季，检查是否有任何剧集正在下载
  bool isDownloading(String globalKey) {
    final progress = getProgress(globalKey);
    return progress?.status == DownloadStatus.downloading;
  }

  /// Check if an item is in the queue
  /// For shows/seasons, checks if any episodes are queued
  bool isQueued(String globalKey) {
    final progress = getProgress(globalKey);
    return progress?.status == DownloadStatus.queued;
  }

  /// Check if an item is currently being queued (building download queue)
  bool isQueueing(String globalKey) => _queueing.contains(globalKey);

  /// Get the local video file path for a downloaded item
  /// Returns null if not downloaded or file doesn't exist
  Future<String?> getVideoFilePath(String globalKey) async {
    appLogger.d('getVideoFilePath called with globalKey: $globalKey');

    final downloadedItem = await _downloadManager.getDownloadedMedia(globalKey);
    if (downloadedItem == null) {
      appLogger.w('No downloaded item found for globalKey: $globalKey');
      return null;
    }
    if (downloadedItem.status != DownloadStatus.completed.index) {
      appLogger.w('Download not complete. Status: ${downloadedItem.status}');
      return null;
    }
    if (downloadedItem.videoFilePath == null) {
      appLogger.w('Video file path is null for globalKey: $globalKey');
      return null;
    }

    final storedPath = downloadedItem.videoFilePath!;
    final storageService = DownloadStorageService.instance;

    // SAF URIs (content://) are already valid - don't transform them
    if (storageService.isSafUri(storedPath)) {
      appLogger.d('Found SAF video path: $storedPath');
      return storedPath;
    }

    // Convert stored path (may be relative) to absolute path
    final absolutePath = await storageService.ensureAbsolutePath(storedPath);

    // Verify file exists
    final file = File(absolutePath);
    if (!await file.exists()) {
      appLogger.w('Offline video file not found: $absolutePath');
      return null;
    }
    return absolutePath;
  }

  /// Queue a download for a media item.
  /// For movies and episodes, queues directly.
  /// For shows and seasons, fetches all child episodes and queues them.
  /// Returns the number of items queued.
  Future<int> queueDownload(PlexMetadata metadata, PlexClient client) async {
    final globalKey = '${metadata.serverId}:${metadata.ratingKey}';

    // Check if downloads are blocked on cellular
    if (await DownloadManagerService.shouldBlockDownloadOnCellular()) {
      throw CellularDownloadBlockedException();
    }

    try {
      // Mark as queueing to show loading state in UI
      _queueing.add(globalKey);
      notifyListeners();

      final type = metadata.type.toLowerCase();

      if (type == 'movie' || type == 'episode') {
        // Direct download of a single item
        await _queueSingleDownload(metadata, client);
        return 1;
      } else if (type == 'show') {
        // Store show metadata so getProgress() can identify it as a show
        _metadata[globalKey] = metadata;

        // Download all episodes from all seasons
        return await _queueShowDownload(metadata, client);
      } else if (type == 'season') {
        // Store season metadata so getProgress() can identify it as a season
        _metadata[globalKey] = metadata;

        // Download all episodes in season
        return await _queueSeasonDownload(metadata, client);
      } else {
        throw Exception('Cannot download ${metadata.type}');
      }
    } finally {
      // Always remove from queueing set, even on error
      _queueing.remove(globalKey);
      notifyListeners();
    }
  }

  /// Queue a single movie or episode for download
  Future<void> _queueSingleDownload(PlexMetadata metadata, PlexClient client) async {
    final globalKey = '${metadata.serverId}:${metadata.ratingKey}';

    // Don't re-queue if already downloading or completed
    if (_downloads.containsKey(globalKey)) {
      final existing = _downloads[globalKey]!;
      if (existing.status == DownloadStatus.downloading || existing.status == DownloadStatus.completed) {
        return;
      }
    }

    // Fetch full metadata to get year, summary, clearLogo
    // The metadata from getChildren() is summarized and missing these fields
    PlexMetadata metadataToStore = metadata;
    try {
      final fullMetadata = await client.getMetadataWithImages(metadata.ratingKey);
      if (fullMetadata != null) {
        metadataToStore = fullMetadata.copyWith(serverId: metadata.serverId, serverName: metadata.serverName);
      }
    } catch (e) {
      appLogger.w('Failed to fetch full metadata for ${metadata.ratingKey}, using partial', error: e);
    }

    // For episodes, also fetch and store show and season metadata for offline display
    if (metadataToStore.type == 'episode') {
      await _fetchAndStoreParentMetadata(metadataToStore, client);
    }

    // Store full metadata for display
    _metadata[globalKey] = metadataToStore;

    // Update local state immediately for UI feedback
    _downloads[globalKey] = DownloadProgress(globalKey: globalKey, status: DownloadStatus.queued);
    notifyListeners();

    // Actually trigger download via DownloadManagerService
    await _downloadManager.queueDownload(metadata: metadataToStore, client: client);
  }

  /// Fetch and store show and season metadata for an episode
  /// Also downloads artwork for show and season
  Future<void> _fetchAndStoreParentMetadata(PlexMetadata episode, PlexClient client) async {
    final serverId = episode.serverId;
    if (serverId == null) return;
    final storageService = DownloadStorageService.instance;

    // Fetch and store show metadata if not already stored
    final showRatingKey = episode.grandparentRatingKey;
    if (showRatingKey != null) {
      final showGlobalKey = '$serverId:$showRatingKey';

      // Try to use existing metadata (set when queueing an entire show)
      PlexMetadata? showMetadata = _metadata[showGlobalKey];

      // If not already cached, fetch full metadata with images
      if (showMetadata == null) {
        try {
          showMetadata = await client.getMetadataWithImages(showRatingKey);
        } catch (e) {
          appLogger.w('Failed to fetch show metadata for $showRatingKey', error: e);
        }
      }

      if (showMetadata != null) {
        final showWithServer = showMetadata.copyWith(serverId: serverId);
        _metadata[showGlobalKey] = showWithServer;

        // Persist to database/API cache for offline usage
        await _downloadManager.saveMetadata(showWithServer);

        // Ensure show artwork is downloaded even if metadata already existed
        final thumbPath = showWithServer.thumb;
        final hasPoster = thumbPath != null && await storageService.artworkExists(serverId, thumbPath);
        if (!hasPoster) {
          await _downloadManager.downloadArtworkForMetadata(showWithServer, client);
          appLogger.d('Downloaded show artwork for $showGlobalKey');
        }

        // Store artwork reference in provider's map for offline display
        _artworkPaths[showGlobalKey] = DownloadedArtwork(thumbPath: thumbPath);
      }
    }

    // Fetch and store season metadata if not already stored
    final seasonRatingKey = episode.parentRatingKey;
    if (seasonRatingKey != null) {
      final seasonGlobalKey = '$serverId:$seasonRatingKey';
      PlexMetadata? seasonMetadata = _metadata[seasonGlobalKey];

      if (seasonMetadata == null) {
        try {
          seasonMetadata = await client.getMetadataWithImages(seasonRatingKey);
        } catch (e) {
          appLogger.w('Failed to fetch season metadata for $seasonRatingKey', error: e);
        }
      }

      if (seasonMetadata != null) {
        final seasonWithServer = seasonMetadata.copyWith(serverId: serverId);
        _metadata[seasonGlobalKey] = seasonWithServer;

        // Persist to database/API cache for offline usage
        await _downloadManager.saveMetadata(seasonWithServer);

        // Ensure season artwork is downloaded even if metadata already existed
        final thumbPath = seasonWithServer.thumb;
        final hasPoster = thumbPath != null && await storageService.artworkExists(serverId, thumbPath);
        if (!hasPoster) {
          await _downloadManager.downloadArtworkForMetadata(seasonWithServer, client);
          appLogger.d('Downloaded season artwork for $seasonGlobalKey');
        }

        // Store artwork reference in provider's map for offline display
        _artworkPaths[seasonGlobalKey] = DownloadedArtwork(thumbPath: thumbPath);
      }
    }
  }

  /// Queue all episodes from a TV show for download
  Future<int> _queueShowDownload(PlexMetadata show, PlexClient client) async {
    final globalKey = '${show.serverId}:${show.ratingKey}';
    int count = 0;
    final seasons = await client.getChildren(show.ratingKey);

    // Store total episode count from show metadata (leafCount)
    if (show.leafCount != null && show.leafCount! > 0) {
      _totalEpisodeCounts[globalKey] = show.leafCount!;
      await _persistTotalEpisodeCount(globalKey, show.leafCount!);
      appLogger.i(
        '💾 Stored episode count for show $globalKey: ${show.leafCount}\n'
        '  - Show title: ${show.title}\n'
        '  - Show type: ${show.type}\n'
        '  - Total stored counts: ${_totalEpisodeCounts.length}',
      );
    } else {
      appLogger.w(
        '⚠️  Show $globalKey has no leafCount! Cannot store episode count.\n'
        '  - Show title: ${show.title}\n'
        '  - Show type: ${show.type}\n'
        '  - leafCount value: ${show.leafCount}',
      );
    }

    for (final season in seasons) {
      if (season.type == 'season') {
        // Ensure season has serverId from parent show
        final seasonWithServer = season.serverId != null ? season : season.copyWith(serverId: show.serverId);
        count += await _queueSeasonDownload(seasonWithServer, client);
      }
    }

    return count;
  }

  /// Queue all episodes from a season for download
  Future<int> _queueSeasonDownload(PlexMetadata season, PlexClient client) async {
    final globalKey = '${season.serverId}:${season.ratingKey}';
    int count = 0;
    final episodes = await client.getChildren(season.ratingKey);

    // Store total episode count from season metadata (leafCount)
    if (season.leafCount != null && season.leafCount! > 0) {
      _totalEpisodeCounts[globalKey] = season.leafCount!;
      await _persistTotalEpisodeCount(globalKey, season.leafCount!);
      appLogger.i(
        '💾 Stored episode count for season $globalKey: ${season.leafCount}\n'
        '  - Season title: ${season.title}\n'
        '  - Season type: ${season.type}\n'
        '  - Total stored counts: ${_totalEpisodeCounts.length}',
      );
    } else {
      appLogger.w(
        '⚠️  Season $globalKey has no leafCount! Cannot store episode count.\n'
        '  - Season title: ${season.title}\n'
        '  - Season type: ${season.type}\n'
        '  - leafCount value: ${season.leafCount}',
      );
    }

    for (final episode in episodes) {
      if (episode.type == 'episode') {
        // Ensure episode has serverId from parent season
        final episodeWithServer = episode.serverId != null ? episode : episode.copyWith(serverId: season.serverId);
        await _queueSingleDownload(episodeWithServer, client);
        count++;
      }
    }

    return count;
  }

  /// Queue only the missing (not downloaded) episodes for a show/season
  /// Used for resuming partial downloads
  /// Returns the number of episodes queued
  Future<int> queueMissingEpisodes(PlexMetadata metadata, PlexClient client) async {
    final type = metadata.type.toLowerCase();

    if (type == 'show') {
      return await _queueMissingShowEpisodes(metadata, client);
    } else if (type == 'season') {
      return await _queueMissingSeasonEpisodes(metadata, client);
    } else {
      throw Exception('queueMissingEpisodes only supports shows/seasons');
    }
  }

  /// Queue missing episodes for a show
  Future<int> _queueMissingShowEpisodes(PlexMetadata show, PlexClient client) async {
    int queuedCount = 0;

    // Fetch all seasons
    final seasons = await client.getChildren(show.ratingKey);

    for (final season in seasons) {
      if (season.type == 'season') {
        final seasonWithServer = season.serverId != null ? season : season.copyWith(serverId: show.serverId);
        queuedCount += await _queueMissingSeasonEpisodes(seasonWithServer, client);
      }
    }

    appLogger.i('Queued $queuedCount missing episodes for show ${show.title}');
    return queuedCount;
  }

  /// Queue missing episodes for a season
  Future<int> _queueMissingSeasonEpisodes(PlexMetadata season, PlexClient client) async {
    int queuedCount = 0;

    // Fetch all episodes
    final episodes = await client.getChildren(season.ratingKey);

    for (final episode in episodes) {
      if (episode.type == 'episode') {
        final episodeWithServer = episode.serverId != null ? episode : episode.copyWith(serverId: season.serverId);

        final episodeGlobalKey = '${episodeWithServer.serverId}:${episodeWithServer.ratingKey}';

        // Only queue if NOT already downloaded or in progress
        final progress = _downloads[episodeGlobalKey];
        if (progress == null ||
            (progress.status != DownloadStatus.completed &&
                progress.status != DownloadStatus.downloading &&
                progress.status != DownloadStatus.queued)) {
          await _queueSingleDownload(episodeWithServer, client);
          queuedCount++;
          appLogger.d('Queued missing episode: ${episode.title} ($episodeGlobalKey)');
        }
      }
    }

    return queuedCount;
  }

  /// Pause a download (works for both downloading and queued items)
  Future<void> pauseDownload(String globalKey) async {
    final progress = _downloads[globalKey];
    if (progress != null &&
        (progress.status == DownloadStatus.downloading || progress.status == DownloadStatus.queued)) {
      await _downloadManager.pauseDownload(globalKey);
    }
  }

  /// Resume a paused download
  Future<void> resumeDownload(String globalKey, PlexClient client) async {
    final progress = _downloads[globalKey];
    if (progress != null && progress.status == DownloadStatus.paused) {
      await _downloadManager.resumeDownload(globalKey, client);
    }
  }

  /// Retry a failed download
  Future<void> retryDownload(String globalKey, PlexClient client) async {
    final progress = _downloads[globalKey];
    if (progress != null && progress.status == DownloadStatus.failed) {
      await _downloadManager.retryDownload(globalKey, client);
    }
  }

  /// Cancel a download
  Future<void> cancelDownload(String globalKey) async {
    final progress = _downloads[globalKey];
    if (progress != null) {
      await _downloadManager.cancelDownload(globalKey);
      _downloads.remove(globalKey);
      _metadata.remove(globalKey);
      notifyListeners();
    }
  }

  /// Delete a downloaded item
  Future<void> deleteDownload(String globalKey) async {
    try {
      // Check if this is a show/season and clean up episode count
      final meta = _metadata[globalKey];
      if (meta?.type == 'show' || meta?.type == 'season') {
        final removedCount = _totalEpisodeCounts.remove(globalKey);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('episode_count_$globalKey');
        appLogger.i(
          '🗑️  Removed episode count for $globalKey\n'
          '  - Removed count value: $removedCount\n'
          '  - Metadata type: ${meta?.type}\n'
          '  - Metadata title: ${meta?.title}\n'
          '  - Remaining stored counts: ${_totalEpisodeCounts.length}',
        );
      }

      // Start deletion (progress will be tracked via stream)
      await _downloadManager.deleteDownload(globalKey);

      // Remove from local state
      _downloads.remove(globalKey);
      _metadata.remove(globalKey);
      _artworkPaths.remove(globalKey);

      notifyListeners();
    } catch (e) {
      // Remove from deletion tracking on error
      _deletionProgress.remove(globalKey);
      notifyListeners();
      rethrow;
    }
  }

  /// Handle deletion progress updates
  void _onDeletionProgressUpdate(DeletionProgress progress) {
    if (progress.isComplete) {
      // Deletion complete - remove from tracking
      _deletionProgress.remove(progress.globalKey);
    } else {
      // Update progress
      _deletionProgress[progress.globalKey] = progress;
    }
    notifyListeners();
  }

  /// Check if an item is being deleted
  bool isDeleting(String globalKey) => _deletionProgress.containsKey(globalKey);

  /// Get deletion progress for an item
  DeletionProgress? getDeletionProgress(String globalKey) => _deletionProgress[globalKey];

  /// Get all items currently being deleted
  UnmodifiableMapView<String, DeletionProgress> get deletionProgress => UnmodifiableMapView(_deletionProgress);

  /// Refresh the downloads list from database
  Future<void> refresh() async {
    await _loadPersistedDownloads();
  }

  /// Refresh only metadata from API cache (after watch state sync).
  ///
  /// This is more lightweight than full refresh() - only updates metadata
  /// without reloading download progress from database.
  Future<void> refreshMetadataFromCache() async {
    final apiCache = PlexApiCache.instance;
    int updatedCount = 0;

    for (final globalKey in _metadata.keys.toList()) {
      final parts = globalKey.split(':');
      if (parts.length != 2) continue;

      final serverId = parts[0];
      final ratingKey = parts[1];

      try {
        final cached = await apiCache.get(serverId, '/library/metadata/$ratingKey');

        final firstMetadata = PlexCacheParser.extractFirstMetadata(cached);
        if (firstMetadata != null) {
          final metadata = PlexMetadata.fromJson(firstMetadata);
          _metadata[globalKey] = metadata.copyWith(serverId: serverId);
          updatedCount++;
        }
      } catch (e) {
        appLogger.d('Failed to refresh metadata for $globalKey: $e');
      }
    }

    if (updatedCount > 0) {
      appLogger.i('Refreshed metadata from cache for $updatedCount items');
      notifyListeners();
    }
  }
}

/// Exception thrown when download is blocked due to cellular-only setting
class CellularDownloadBlockedException implements Exception {
  final String message = 'Downloads are disabled on cellular data';

  @override
  String toString() => message;
}
