import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:plezy/utils/content_utils.dart';
import '../database/app_database.dart';
import 'settings_service.dart';
import '../models/download_models.dart';
import '../models/plex_metadata.dart';
import '../models/plex_media_info.dart';
import '../services/plex_client.dart';
import '../services/download_storage_service.dart';
import '../services/plex_api_cache.dart';
import '../utils/app_logger.dart';
import '../utils/codec_utils.dart';
import '../utils/plex_cache_parser.dart';

/// AppDatabase 的下载操作扩展方法
extension DownloadDatabaseOperations on AppDatabase {
  /// 向数据库插入一条新的下载记录
  Future<void> insertDownload({
    required String serverId,
    required String ratingKey,
    required String globalKey,
    required String type,
    String? parentRatingKey,
    String? grandparentRatingKey,
    required int status,
  }) async {
    await into(downloadedMedia).insert(
      DownloadedMediaCompanion.insert(
        serverId: serverId,
        ratingKey: ratingKey,
        globalKey: globalKey,
        type: type,
        parentRatingKey: Value(parentRatingKey),
        grandparentRatingKey: Value(grandparentRatingKey),
        status: status,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// 将项目添加到下载队列
  Future<void> addToQueue({
    required String mediaGlobalKey,
    int priority = 0,
    bool downloadSubtitles = true,
    bool downloadArtwork = true,
  }) async {
    await into(downloadQueue).insert(
      DownloadQueueCompanion.insert(
        mediaGlobalKey: mediaGlobalKey,
        priority: Value(priority),
        addedAt: DateTime.now().millisecondsSinceEpoch,
        downloadSubtitles: Value(downloadSubtitles),
        downloadArtwork: Value(downloadArtwork),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// 从队列中获取下一个项目 (优先级最高，最早添加的优先)
  /// 仅返回未暂停的项目
  Future<DownloadQueueItem?> getNextQueueItem() async {
    // 与 downloadedMedia 关联查询，以检查状态并过滤掉已暂停的项目
    final query = select(
      downloadQueue,
    ).join([innerJoin(downloadedMedia, downloadedMedia.globalKey.equalsExp(downloadQueue.mediaGlobalKey))]);

    query
      ..where(downloadedMedia.status.equals(DownloadStatus.paused.index).not())
      ..orderBy([
        OrderingTerm(expression: downloadQueue.priority, mode: OrderingMode.desc),
        OrderingTerm(expression: downloadQueue.addedAt),
      ])
      ..limit(1);

    final result = await query.getSingleOrNull();
    return result?.readTable(downloadQueue);
  }

  /// 更新下载状态
  Future<void> updateDownloadStatus(String globalKey, int status) async {
    await (update(
      downloadedMedia,
    )..where((t) => t.globalKey.equals(globalKey))).write(DownloadedMediaCompanion(status: Value(status)));
  }

  /// 更新下载进度
  Future<void> updateDownloadProgress(String globalKey, int progress, int downloadedBytes, int totalBytes) async {
    await (update(downloadedMedia)..where((t) => t.globalKey.equals(globalKey))).write(
      DownloadedMediaCompanion(
        progress: Value(progress),
        downloadedBytes: Value(downloadedBytes),
        totalBytes: Value(totalBytes),
      ),
    );
  }

  /// 更新视频文件路径
  Future<void> updateVideoFilePath(String globalKey, String filePath) async {
    await (update(downloadedMedia)..where((t) => t.globalKey.equals(globalKey))).write(
      DownloadedMediaCompanion(
        videoFilePath: Value(filePath),
        downloadedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 更新封面图路径
  Future<void> updateArtworkPaths({required String globalKey, String? thumbPath}) async {
    await (update(
      downloadedMedia,
    )..where((t) => t.globalKey.equals(globalKey))).write(DownloadedMediaCompanion(thumbPath: Value(thumbPath)));
  }

  /// 更新下载错误并增加重试计数
  Future<void> updateDownloadError(String globalKey, String errorMessage) async {
    // 获取当前重试计数并递增
    final existing = await getDownloadedMedia(globalKey);
    final currentCount = existing?.retryCount ?? 0;

    await (update(downloadedMedia)..where((t) => t.globalKey.equals(globalKey))).write(
      DownloadedMediaCompanion(errorMessage: Value(errorMessage), retryCount: Value(currentCount + 1)),
    );
  }

  /// 清除下载错误并重置重试计数 (用于重试)
  Future<void> clearDownloadError(String globalKey) async {
    await (update(downloadedMedia)..where((t) => t.globalKey.equals(globalKey))).write(
      const DownloadedMediaCompanion(errorMessage: Value(null), retryCount: Value(0)),
    );
  }

  /// 从队列中移除项目
  Future<void> removeFromQueue(String mediaGlobalKey) async {
    await (delete(downloadQueue)..where((t) => t.mediaGlobalKey.equals(mediaGlobalKey))).go();
  }

  /// 获取已下载的媒体项目
  Future<DownloadedMediaItem?> getDownloadedMedia(String globalKey) async {
    return (select(downloadedMedia)..where((t) => t.globalKey.equals(globalKey))).getSingleOrNull();
  }

  /// 删除一条下载记录
  Future<void> deleteDownload(String globalKey) async {
    await (delete(downloadedMedia)..where((t) => t.globalKey.equals(globalKey))).go();
    await (delete(downloadQueue)..where((t) => t.mediaGlobalKey.equals(globalKey))).go();
  }

  /// 获取某个季的所有已下载剧集
  Future<List<DownloadedMediaItem>> getEpisodesBySeason(String seasonKey) {
    return (select(downloadedMedia)..where((t) => t.parentRatingKey.equals(seasonKey))).get();
  }

  /// 获取某个剧集的所有已下载剧集
  Future<List<DownloadedMediaItem>> getEpisodesByShow(String showKey) {
    return (select(downloadedMedia)..where((t) => t.grandparentRatingKey.equals(showKey))).get();
  }
}

class DownloadManagerService {
  final AppDatabase _database;
  final DownloadStorageService _storageService;
  final PlexApiCache _apiCache = PlexApiCache.instance;
  final Dio _dio;

  // 下载进度更新的流控制器
  final _progressController = StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  // 删除进度更新的流控制器
  final _deletionProgressController = StreamController<DeletionProgress>.broadcast();
  Stream<DeletionProgress> get deletionProgressStream => _deletionProgressController.stream;

  // 带有取消令牌的活跃下载任务
  final Map<String, CancelToken> _activeDownloads = {};

  // 防止重复处理队列的标志
  bool _isProcessingQueue = false;

  // 用于自动恢复的连接状态监听器
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // 用于自动恢复的缓存客户端
  PlexClient? _lastClient;

  /// 检查是否由于“仅 WiFi 下载”设置而应阻塞下载
  Future<bool> _shouldBlockDownload() async {
    return shouldBlockDownloadOnCellular();
  }

  /// 检查是否由于“仅 WiFi 下载”设置而应阻塞下载的静态方法
  /// 可被 DownloadProvider 用于显示用户友好的错误信息
  static Future<bool> shouldBlockDownloadOnCellular() async {
    final settings = await SettingsService.getInstance();
    if (!settings.getDownloadOnWifiOnly()) return false;

    final connectivity = await Connectivity().checkConnectivity();
    // 如果处于移动网络且未连接 WiFi，则阻塞 (如果两者都可用则允许)
    return connectivity.contains(ConnectivityResult.mobile) &&
        !connectivity.contains(ConnectivityResult.wifi) &&
        !connectivity.contains(ConnectivityResult.ethernet);
  }

  DownloadManagerService({required AppDatabase database, required DownloadStorageService storageService, Dio? dio})
    : _database = database,
      _storageService = storageService,
      _dio = dio ?? Dio();

  /// 如果文件存在则删除并记录日志
  /// 如果文件被删除则返回 true，否则返回 false
  Future<bool> _deleteFileIfExists(File file, String description) async {
    if (await file.exists()) {
      await file.delete();
      appLogger.i('已删除 $description: ${file.path}');
      return true;
    }
    return false;
  }

  /// 将媒体项目加入下载队列
  Future<void> queueDownload({
    required PlexMetadata metadata,
    required PlexClient client,
    int priority = 0,
    bool downloadSubtitles = true,
    bool downloadArtwork = true,
  }) async {
    final globalKey = '${metadata.serverId}:${metadata.ratingKey}';

    // 检查是否已在下载或已完成
    final existing = await _database.getDownloadedMedia(globalKey);
    if (existing != null &&
        (existing.status == DownloadStatus.downloading.index || existing.status == DownloadStatus.completed.index)) {
      appLogger.i('$globalKey 的下载已存在，状态为 ${existing.status}');
      return;
    }

    // 插入数据库
    await _database.insertDownload(
      serverId: metadata.serverId!,
      ratingKey: metadata.ratingKey,
      globalKey: globalKey,
      type: metadata.type,
      parentRatingKey: metadata.parentRatingKey,
      grandparentRatingKey: metadata.grandparentRatingKey,
      status: DownloadStatus.queued.index,
    );

    // 固定已缓存的 API 响应以供离线使用
    // (getMetadataWithImages 之前已被 download_provider 调用，已缓存章节/标记)
    await _apiCache.pinForOffline(metadata.serverId!, metadata.ratingKey);

    // 添加到队列
    await _database.addToQueue(
      mediaGlobalKey: globalKey,
      priority: priority,
      downloadSubtitles: downloadSubtitles,
      downloadArtwork: downloadArtwork,
    );

    _emitProgress(globalKey, DownloadStatus.queued, 0);

    // 如果尚未开始，则启动队列处理
    _processQueue(client);
  }

  /// 开始处理下载队列 - 一次处理一个项目
  Future<void> _processQueue(PlexClient client) async {
    if (_isProcessingQueue) {
      appLogger.d('队列处理已在进行中');
      return;
    }

    _isProcessingQueue = true;
    _lastClient = client; // 缓存以便自动恢复
    _setupConnectivityListener(); // 设置连接监听器以便自动恢复

    try {
      while (true) {
        // 检查是否因移动网络而需要暂停
        if (await _shouldBlockDownload()) {
          appLogger.i('暂停下载 - 处于移动网络且已启用“仅 WiFi 下载”');
          break;
        }

        // 从队列获取下一个项目
        final nextItem = await _database.getNextQueueItem();
        if (nextItem == null) {
          appLogger.d('队列中没有更多项目');
          break;
        }

        await _startDownload(nextItem.mediaGlobalKey, client, nextItem);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  /// 设置连接状态监听器，以便在 WiFi 可用时自动恢复下载
  void _setupConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) async {
      // 如果 WiFi 变得可用，尝试恢复队列
      if (results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.ethernet)) {
        final hasQueuedItems = await _database.getNextQueueItem() != null;
        if (hasQueuedItems && !_isProcessingQueue && _lastClient != null) {
          appLogger.i('WiFi 已连接 - 恢复下载');
          _processQueue(_lastClient!);
        }
      }
    });
  }

  /// 开始下载特定项目
  Future<void> _startDownload(String globalKey, PlexClient client, DownloadQueueItem queueItem) async {
    try {
      appLogger.i('正在开始下载 $globalKey');

      // 更新状态为正在下载
      await _transitionStatus(globalKey, DownloadStatus.downloading);
      appLogger.d('状态已更新为正在下载');

      // 解析 globalKey 以获取 serverId 和 ratingKey
      final parts = globalKey.split(':');
      final serverId = parts[0];
      final ratingKey = parts[1];

      // 从缓存获取元数据
      final cachedResponse = await _apiCache.get(serverId, '/library/metadata/$ratingKey');
      if (cachedResponse == null) {
        throw Exception('在缓存中未找到 $globalKey 的元数据');
      }

      // 从缓存响应中解析元数据
      final firstMetadata = PlexCacheParser.extractFirstMetadata(cachedResponse);
      if (firstMetadata == null) {
        throw Exception('$globalKey 的缓存元数据无效');
      }
      final metadata = PlexMetadata.fromJson(firstMetadata).copyWith(serverId: serverId);

      // 获取视频播放数据 (包括 URL、流信息等)
      final playbackData = await client.getVideoPlaybackData(metadata.ratingKey);
      if (playbackData.videoUrl == null) {
        throw Exception('无法获取视频 URL');
      }

      // 缓存播放额外内容 (章节 + 标记) 供离线使用
      // 这一步会同时执行获取和缓存
      await client.getPlaybackExtras(metadata.ratingKey);

      // 从 URL 确定文件扩展名，默认为 mp4
      final extension = _getExtensionFromUrl(playbackData.videoUrl!) ?? 'mp4';

      final metadataWithServer = metadata;

      // 对于剧集，从缓存的剧集元数据中查找剧集的年份
      int? showYear;
      if (metadataWithServer.type == 'episode' && metadataWithServer.grandparentRatingKey != null) {
        final showCached = await _apiCache.get(
          serverId,
          '/library/metadata/${metadataWithServer.grandparentRatingKey}',
        );
        final showJson = PlexCacheParser.extractFirstMetadata(showCached);
        if (showJson != null) {
          final showMetadata = PlexMetadata.fromJson(showJson);
          showYear = showMetadata.year;
        }
      }

      // 创建取消令牌
      final cancelToken = CancelToken();
      _activeDownloads[globalKey] = cancelToken;

      appLogger.d('正在开始 $globalKey 的视频下载');

      // 确定下载路径并处理 SAF 模式
      final String downloadFilePath;
      final String storedPath;

      if (_storageService.isUsingSaf) {
        // SAF 模式：先下载到临时缓存，然后复制到 SAF
        final tempFileName = '${globalKey.replaceAll(':', '_')}.$extension';
        downloadFilePath = await _storageService.getTempDownloadPath(tempFileName);

        // 下载到临时路径
        await _downloadFile(
          url: playbackData.videoUrl!,
          filePath: downloadFilePath,
          globalKey: globalKey,
          cancelToken: cancelToken,
        );

        appLogger.d('视频已下载到临时路径，正在为 $globalKey 复制到 SAF');

        // 复制到 SAF
        final List<String> pathComponents;
        final String safFileName;
        if (metadataWithServer.type == 'movie') {
          pathComponents = _storageService.getMovieSafPathComponents(metadataWithServer);
          safFileName = _storageService.getMovieSafFileName(metadataWithServer, extension);
        } else if (metadataWithServer.type == 'episode') {
          pathComponents = _storageService.getEpisodeSafPathComponents(metadataWithServer, showYear: showYear);
          safFileName = _storageService.getEpisodeSafFileName(metadataWithServer, extension);
        } else {
          pathComponents = [serverId, metadataWithServer.ratingKey];
          safFileName = 'video.$extension';
        }

        final safUri = await _storageService.copyToSaf(
          downloadFilePath,
          pathComponents,
          safFileName,
          _storageService.getMimeType(extension),
        );

        if (safUri == null) {
          throw Exception('将视频复制到 SAF 存储失败');
        }

        storedPath = safUri;
        appLogger.d('视频已复制到 SAF: $safUri');
      } else {
        // 普通模式：直接下载到最终路径
        if (metadataWithServer.type == 'movie') {
          downloadFilePath = await _storageService.getMovieVideoPath(metadataWithServer, extension);
        } else if (metadataWithServer.type == 'episode') {
          downloadFilePath = await _storageService.getEpisodeVideoPath(
            metadataWithServer,
            extension,
            showYear: showYear,
          );
        } else {
          downloadFilePath = await _storageService.getVideoFilePath(serverId, metadataWithServer.ratingKey, extension);
        }

        await _downloadFile(
          url: playbackData.videoUrl!,
          filePath: downloadFilePath,
          globalKey: globalKey,
          cancelToken: cancelToken,
        );

        // 存储相对路径 (以应对 iOS 容器 UUID 变更)
        storedPath = await _storageService.toRelativePath(downloadFilePath);
      }

      appLogger.d('$globalKey 的视频下载完成');

      // 更新数据库中的存储路径 (SAF URI 或相对路径)
      await _database.updateVideoFilePath(globalKey, storedPath);

      // 如果启用，下载封面图 (仅剧集特定封面，非剧集/季封面)
      // 使用传入的 queueItem 设置 (而非 getNextQueueItem，后者会返回下一个项目)
      if (queueItem.downloadArtwork) {
        await _downloadArtwork(globalKey, metadataWithServer, client, showYear: showYear);

        // 下载章节缩略图
        await _downloadChapterThumbnails(metadataWithServer.serverId!, metadataWithServer.ratingKey, client);
      }

      // 如果启用，下载字幕
      if (queueItem.downloadSubtitles && playbackData.mediaInfo != null) {
        await _downloadSubtitles(globalKey, metadataWithServer, playbackData.mediaInfo!, client, showYear: showYear);
      }

      // 标记为已完成
      await _transitionStatus(globalKey, DownloadStatus.completed);
      await _database.removeFromQueue(globalKey);

      _activeDownloads.remove(globalKey);

      appLogger.i('$globalKey 的下载已完成');
    } catch (e) {
      // 检查是否由用户发起的取消/暂停 (非真实失败)
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // 状态已由 pauseDownload() 或 cancelDownload() 设置
        // 仅清理并退出，不标记为失败
        appLogger.d('$globalKey 的下载已取消/暂停: ${e.message}');
        _activeDownloads.remove(globalKey);
        return;
      }

      appLogger.e('$globalKey 的下载失败', error: e);
      await _transitionStatus(globalKey, DownloadStatus.failed, errorMessage: e.toString());
      await _database.updateDownloadError(globalKey, e.toString());
      // 从队列移除以防止陷入无限重试循环
      await _database.removeFromQueue(globalKey);
      _activeDownloads.remove(globalKey);
    }
  }

  Future<void> _downloadFile({
    required String url,
    required String filePath,
    required String globalKey,
    required CancelToken cancelToken,
  }) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);

    int lastBytes = 0;
    DateTime lastUpdate = DateTime.now();

    await _dio.download(
      url,
      filePath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        // 计算速度 (每 500ms 更新一次)
        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds >= 500) {
          final elapsedSeconds = now.difference(lastUpdate).inSeconds.clamp(1, double.infinity);
          final bytesPerSecond = (received - lastBytes) / elapsedSeconds;
          lastUpdate = now;
          lastBytes = received;

          final progress = total > 0 ? ((received / total) * 100).round() : 0;

          appLogger.d('下载进度: $progress% ($received/$total bytes) - $globalKey');

          _progressController.add(
            DownloadProgress(
              globalKey: globalKey,
              status: DownloadStatus.downloading,
              progress: progress,
              downloadedBytes: received,
              totalBytes: total,
              speed: bytesPerSecond,
              currentFile: 'video',
            ),
          );

          // 异步更新数据库 (非阻塞)
          _database.updateDownloadProgress(globalKey, progress, received, total).catchError((e) {
            appLogger.w('Failed to update download progress in DB', error: e);
          });
        }
      },
    );
  }

  /// 使用基于哈希的存储为媒体项目下载封面图
  /// 下载所有封面图类型：缩略图/海报、透明 Logo 和背景图
  Future<void> _downloadArtwork(String globalKey, PlexMetadata metadata, PlexClient client, {int? showYear}) async {
    if (metadata.serverId == null) return;

    try {
      _emitProgress(globalKey, DownloadStatus.downloading, 0, currentFile: 'artwork');

      final serverId = metadata.serverId!;

      // 下载缩略图/海报
      if (metadata.thumb != null) {
        await _downloadSingleArtwork(serverId, metadata.thumb!, client);
      }

      // 下载透明 Logo
      if (metadata.clearLogo != null) {
        await _downloadSingleArtwork(serverId, metadata.clearLogo!, client);
      }

      // 下载背景图
      if (metadata.art != null) {
        await _downloadSingleArtwork(serverId, metadata.art!, client);
      }

      // 在数据库中存储缩略图引用 (用于显示的主封面)
      await _database.updateArtworkPaths(globalKey: globalKey, thumbPath: metadata.thumb);

      _emitProgressWithArtwork(globalKey, thumbPath: metadata.thumb);
      appLogger.d('已为 $globalKey 下载封面图');
    } catch (e) {
      appLogger.w('为 $globalKey 下载封面图失败', error: e);
      // 如果封面图下载失败，不要让整个下载任务失败
    }
  }

  /// 如果单个封面图文件尚不存在，则下载它
  Future<void> _downloadSingleArtwork(String serverId, String artworkPath, PlexClient client) async {
    try {
      // 检查是否已下载 (去重)
      if (await _storageService.artworkExists(serverId, artworkPath)) {
        appLogger.d('封面图已存在: $artworkPath');
        return;
      }

      final url = client.getThumbnailUrl(artworkPath);
      if (url.isEmpty) {
        appLogger.w('缩略图 URL 为空: $artworkPath');
        return;
      }

      final filePath = await _storageService.getArtworkPathFromThumb(serverId, artworkPath);
      final file = File(filePath);

      // 确保父目录存在
      await file.parent.create(recursive: true);

      // 下载封面图
      await _dio.download(url, filePath);
      appLogger.i('已下载封面图: $artworkPath -> $filePath');
    } catch (e, stack) {
      appLogger.w('下载封面图失败: $artworkPath', error: e, stackTrace: stack);
      // 不要抛出异常 - 封面图下载失败不应中断整个下载任务
    }
  }

  /// 为元数据项下载所有封面图 (用于父级元数据的公共方法)
  /// 下载缩略图/海报、透明 Logo 和背景图
  Future<void> downloadArtworkForMetadata(PlexMetadata metadata, PlexClient client) async {
    if (metadata.serverId == null) return;
    final serverId = metadata.serverId!;

    // 下载缩略图/海报
    if (metadata.thumb != null) {
      await _downloadSingleArtwork(serverId, metadata.thumb!, client);
    }

    // 下载透明 Logo
    if (metadata.clearLogo != null) {
      await _downloadSingleArtwork(serverId, metadata.clearLogo!, client);
    }

    // 下载背景图
    if (metadata.art != null) {
      await _downloadSingleArtwork(serverId, metadata.art!, client);
    }
  }

  /// 为媒体项目下载章节缩略图
  Future<void> _downloadChapterThumbnails(String serverId, String ratingKey, PlexClient client) async {
    try {
      // 从缓存的 API 响应中获取章节信息
      final extras = await client.getPlaybackExtras(ratingKey);

      for (final chapter in extras.chapters) {
        if (chapter.thumb != null) {
          await _downloadSingleArtwork(serverId, chapter.thumb!, client);
        }
      }

      if (extras.chapters.isNotEmpty) {
        appLogger.d('已下载 ${extras.chapters.length} 个章节缩略图');
      }
    } catch (e) {
      appLogger.w('下载章节缩略图失败', error: e);
      // 如果章节缩略图下载失败，不要让整个下载任务失败
    }
  }

  /// [showYear]: 对于剧集，传递剧集的首播年份 (而非该集的年份)
  Future<void> _downloadSubtitles(
    String globalKey,
    PlexMetadata metadata,
    PlexMediaInfo mediaInfo,
    PlexClient client, {
    int? showYear,
  }) async {
    try {
      _emitProgress(globalKey, DownloadStatus.downloading, 0, currentFile: 'subtitles');

      for (final subtitle in mediaInfo.subtitleTracks) {
        // 仅下载外部字幕
        if (!subtitle.isExternal || subtitle.key == null) {
          continue;
        }

        final baseUrl = client.config.baseUrl;
        final token = client.config.token ?? '';
        final subtitleUrl = subtitle.getSubtitleUrl(baseUrl, token);
        if (subtitleUrl == null) continue;

        // 确定文件扩展名
        final extension = CodecUtils.getSubtitleExtension(subtitle.codec);

        // 根据媒体类型获取用户友好的字幕路径
        final String subtitlePath;
        if (metadata.isEpisode) {
          subtitlePath = await _storageService.getEpisodeSubtitlePath(
            metadata,
            subtitle.id,
            extension,
            showYear: showYear,
          );
        } else if (metadata.isMovie) {
          subtitlePath = await _storageService.getMovieSubtitlePath(metadata, subtitle.id, extension);
        } else {
          // 回退到旧结构
          subtitlePath = await _storageService.getSubtitlePath(
            metadata.serverId!,
            metadata.ratingKey,
            subtitle.id,
            extension,
          );
        }

        // 下载字幕文件
        final file = File(subtitlePath);
        await file.parent.create(recursive: true);
        await _dio.download(subtitleUrl, subtitlePath);

        appLogger.d('已为 $globalKey 下载字幕 ${subtitle.id}');
      }
    } catch (e) {
      appLogger.w('为 $globalKey 下载字幕失败', error: e);
      // 如果字幕下载失败，不要让整个下载任务失败
    }
  }

  String? _getExtensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final path = uri.path;
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1) return null;
    return path.substring(lastDot + 1).split('?').first;
  }

  void _emitProgress(
    String globalKey,
    DownloadStatus status,
    int progress, {
    String? errorMessage,
    String? currentFile,
  }) {
    _progressController.add(
      DownloadProgress(
        globalKey: globalKey,
        status: status,
        progress: progress,
        errorMessage: errorMessage,
        currentFile: currentFile,
      ),
    );
  }

  /// 更新数据库中的下载状态并发送进度通知。
  ///
  /// 此辅助方法结合了两个常见操作：
  /// 1. 更新数据库中的状态
  /// 2. 向监听器发送进度
  ///
  /// 大多数状态的默认进度为 0，已完成状态为 100。
  Future<void> _transitionStatus(String globalKey, DownloadStatus status, {int? progress, String? errorMessage}) async {
    await _database.updateDownloadStatus(globalKey, status.index);
    _emitProgress(
      globalKey,
      status,
      progress ?? (status == DownloadStatus.completed ? 100 : 0),
      errorMessage: errorMessage,
    );
  }

  /// 发送包含封面图路径的进度更新，以便 DownloadProvider 同步
  void _emitProgressWithArtwork(String globalKey, {String? thumbPath}) {
    // 发送包含封面图路径的进度更新
    // 状态保持为下载中，因为封面图只是其中一个步骤
    _progressController.add(
      DownloadProgress(
        globalKey: globalKey,
        status: DownloadStatus.downloading,
        progress: 0,
        currentFile: 'artwork',
        thumbPath: thumbPath,
      ),
    );
  }

  /// 暂停下载 (适用于正在下载和队列中的项目)
  Future<void> pauseDownload(String globalKey) async {
    // 如果存在活跃下载，则取消
    final cancelToken = _activeDownloads[globalKey];
    if (cancelToken != null) {
      cancelToken.cancel('用户暂停');
      _activeDownloads.remove(globalKey);
    }
    // 将状态更新为已暂停并从队列移除，以免重启
    await _transitionStatus(globalKey, DownloadStatus.paused);
    await _database.removeFromQueue(globalKey);
  }

  /// 恢复已暂停的下载
  Future<void> resumeDownload(String globalKey, PlexClient client) async {
    await _transitionStatus(globalKey, DownloadStatus.queued);
    // 重新添加到队列 (pauseDownload 会从队列移除)
    await _database.addToQueue(mediaGlobalKey: globalKey);
    _processQueue(client);
  }

  /// 重试失败的下载
  Future<void> retryDownload(String globalKey, PlexClient client) async {
    // 清除错误并重置重试计数
    await _database.clearDownloadError(globalKey);
    // 重置状态为队列中
    await _transitionStatus(globalKey, DownloadStatus.queued);
    // 重新添加到队列
    await _database.addToQueue(mediaGlobalKey: globalKey);
    _processQueue(client);
  }

  /// 取消下载
  Future<void> cancelDownload(String globalKey) async {
    final cancelToken = _activeDownloads[globalKey];
    if (cancelToken != null) {
      cancelToken.cancel('用户取消');
      _activeDownloads.remove(globalKey);
    }
    await _transitionStatus(globalKey, DownloadStatus.cancelled);
    await _database.removeFromQueue(globalKey);
  }

  /// 删除已下载的项目及其文件
  Future<void> deleteDownload(String globalKey) async {
    // 如果正在活跃下载，则取消
    final cancelToken = _activeDownloads[globalKey];
    if (cancelToken != null) {
      cancelToken.cancel('下载已删除');
      _activeDownloads.remove(globalKey);
    }

    // 从存储中删除文件
    final parts = globalKey.split(':');
    if (parts.length != 2) {
      await _database.deleteDownload(globalKey);
      return;
    }

    final serverId = parts[0];
    final ratingKey = parts[1];
    final metadata = await _getMetadataFromCache(serverId, ratingKey);

    if (metadata == null) {
      // 回退方案：不带进度删除
      await _deleteMediaFilesWithMetadata(serverId, ratingKey);
      await _apiCache.deleteForItem(serverId, ratingKey);
      await _database.deleteDownload(globalKey);
      return;
    }

    // 确定要删除的项目总数
    final totalItems = await _getTotalItemsToDelete(metadata, serverId);

    // 发送初始进度
    _emitDeletionProgress(
      DeletionProgress(globalKey: globalKey, itemTitle: metadata.title, currentItem: 0, totalItems: totalItems),
    );

    // 从存储中删除文件 (带进度更新)
    await _deleteMediaFilesWithMetadata(serverId, ratingKey);

    // 从 API 缓存中删除
    await _apiCache.deleteForItem(serverId, ratingKey);

    // 从数据库中删除
    await _database.deleteDownload(globalKey);

    // 发送完成通知
    _emitDeletionProgress(
      DeletionProgress(
        globalKey: globalKey,
        itemTitle: metadata.title,
        currentItem: totalItems,
        totalItems: totalItems,
      ),
    );
  }

  /// 发送删除进度更新
  void _emitDeletionProgress(DeletionProgress progress) {
    _deletionProgressController.add(progress);
  }

  /// 计算要删除的项目总数 (用于进度追踪)
  Future<int> _getTotalItemsToDelete(PlexMetadata metadata, String serverId) async {
    switch (metadata.type.toLowerCase()) {
      case 'episode':
        return 1; // 单个剧集
      case 'movie':
        return 1; // 单个电影
      case 'season':
        // 计算季中的剧集数
        final episodes = await _database.getEpisodesBySeason(metadata.ratingKey);
        return episodes.length;
      case 'show':
        // 计算剧集中的所有剧集数
        final episodes = await _database.getEpisodesByShow(metadata.ratingKey);
        return episodes.length;
      default:
        return 1;
    }
  }

  /// 使用元数据查找正确路径并删除媒体文件
  Future<void> _deleteMediaFilesWithMetadata(String serverId, String ratingKey) async {
    try {
      // 从 API 缓存获取元数据
      final metadata = await _getMetadataFromCache(serverId, ratingKey);

      if (metadata == null) {
        // 回退方案：尝试数据库记录
        final downloadRecord = await _database.getDownloadedMedia('$serverId:$ratingKey');
        if (downloadRecord?.videoFilePath != null) {
          await _deleteByFilePath(downloadRecord!);
          return;
        }
        appLogger.w('无法删除 - 找不到 $serverId:$ratingKey 的元数据');
        return;
      }

      // 根据类型删除
      switch (metadata.type.toLowerCase()) {
        case 'episode':
          await _deleteEpisodeFiles(metadata, serverId);
          break;
        case 'season':
          await _deleteSeasonFiles(metadata, serverId);
          break;
        case 'show':
          await _deleteShowFiles(metadata, serverId);
          break;
        case 'movie':
          await _deleteMovieFiles(metadata, serverId);
          break;
        default:
          appLogger.w('未知的删除类型: ${metadata.type}');
      }
    } catch (e, stack) {
      appLogger.e('删除文件出错', error: e, stackTrace: stack);
    }
  }

  /// 从 API 缓存获取元数据
  Future<PlexMetadata?> _getMetadataFromCache(String serverId, String ratingKey) async {
    final cachedData = await _apiCache.get(serverId, '/library/metadata/$ratingKey');
    final metadataJson = PlexCacheParser.extractFirstMetadata(cachedData);
    if (metadataJson != null) {
      return PlexMetadata.fromJson(metadataJson).copyWith(serverId: serverId);
    }
    return null;
  }

  /// 从缓存的元数据中获取章节缩略图路径
  Future<List<String>> _getChapterThumbPaths(String serverId, String ratingKey) async {
    try {
      final cachedData = await _apiCache.get(serverId, '/library/metadata/$ratingKey');
      final chapters = PlexCacheParser.extractChapters(cachedData);
      if (chapters == null) return [];

      return chapters
          .map((ch) => ch['thumb'] as String?)
          .where((thumb) => thumb != null && thumb.isNotEmpty)
          .cast<String>()
          .toList();
    } catch (e) {
      appLogger.w('获取 $ratingKey 的章节缩略图路径出错', error: e);
      return [];
    }
  }

  /// 检查章节缩略图是否被其他已下载项目使用
  Future<bool> _isChapterThumbnailInUse(String serverId, String thumbPath, String excludeRatingKey) async {
    try {
      // 获取所有已下载项目
      final allItems = await _database.select(_database.downloadedMedia).get();

      // 检查是否有其他项目使用此章节缩略图
      for (final item in allItems) {
        // 跳过正在删除的项目
        if (item.ratingKey == excludeRatingKey) {
          continue;
        }

        // 获取此项目的章节缩略图路径
        final itemChapterPaths = await _getChapterThumbPaths(serverId, item.ratingKey);

        // 检查此项目是否包含相同的缩略图路径
        if (itemChapterPaths.contains(thumbPath)) {
          return true; // 缩略图正在使用中
        }
      }

      return false; // 缩略图未被使用
    } catch (e) {
      appLogger.w('检查章节缩略图使用情况出错: $thumbPath', error: e);
      // 出错时，为安全起见假设正在使用 (不删除)
      return true;
    }
  }

  /// 删除媒体项目的章节缩略图 (带引用计数)
  Future<void> _deleteChapterThumbnails(String serverId, String ratingKey) async {
    try {
      final thumbPaths = await _getChapterThumbPaths(serverId, ratingKey);

      if (thumbPaths.isEmpty) {
        appLogger.d('没有要删除的 $ratingKey 的章节缩略图');
        return;
      }

      int deletedCount = 0;
      int preservedCount = 0;

      for (final thumbPath in thumbPaths) {
        try {
          // 检查此缩略图是否被其他项目使用
          final inUse = await _isChapterThumbnailInUse(serverId, thumbPath, ratingKey);

          if (inUse) {
            appLogger.d('保留章节缩略图 (正在使用): $thumbPath');
            preservedCount++;
            continue;
          }

          // 获取封面图文件路径并删除
          final artworkPath = await _storageService.getArtworkPathFromThumb(serverId, thumbPath);
          if (await _deleteFileIfExists(File(artworkPath), '章节缩略图')) {
            deletedCount++;
          }
        } catch (e) {
          appLogger.w('删除章节缩略图失败: $thumbPath', error: e);
          // 即使一个失败，也继续处理其他章节
        }
      }

      if (deletedCount > 0 || preservedCount > 0) {
        appLogger.i('删除了 ${thumbPaths.length} 个章节缩略图中的 $deletedCount 个 (保留了 $preservedCount 个)');
      }
    } catch (e, stack) {
      appLogger.w('删除 $ratingKey 的章节缩略图出错', error: e, stackTrace: stack);
      // 不要抛出异常 - 章节删除不应阻塞主删除流程
    }
  }

  /// 删除剧集文件
  Future<void> _deleteEpisodeFiles(PlexMetadata episode, String serverId) async {
    try {
      final parentMetadata = episode.grandparentRatingKey != null
          ? await _getMetadataFromCache(serverId, episode.grandparentRatingKey!)
          : null;
      final showYear = parentMetadata?.year;

      // 删除视频文件
      final videoPathTemplate = await _storageService.getEpisodeVideoPath(episode, 'tmp', showYear: showYear);
      final videoPathWithoutExt = videoPathTemplate.substring(0, videoPathTemplate.lastIndexOf('.'));
      final actualVideoFile = await _findFileWithAnyExtension(videoPathWithoutExt);
      if (actualVideoFile != null) {
        await _deleteFileIfExists(actualVideoFile, '剧集视频');
      }

      // 删除缩略图
      final thumbPath = await _storageService.getEpisodeThumbnailPath(episode, showYear: showYear);
      await _deleteFileIfExists(File(thumbPath), '剧集缩略图');

      // 删除字幕目录
      final subsDir = await _storageService.getEpisodeSubtitlesDirectory(episode, showYear: showYear);
      if (await subsDir.exists()) {
        await subsDir.delete(recursive: true);
        appLogger.i('已删除剧集字幕: ${subsDir.path}');
      }

      // 删除章节缩略图 (带引用计数)
      await _deleteChapterThumbnails(serverId, episode.ratingKey);

      // 如果父目录为空，则清理
      await _cleanupEmptyDirectories(episode, showYear);
    } catch (e, stack) {
      appLogger.e('删除剧集文件出错', error: e, stackTrace: stack);
    }
  }

  /// 删除季文件
  Future<void> _deleteSeasonFiles(PlexMetadata season, String serverId) async {
    try {
      final parentMetadata = season.parentRatingKey != null
          ? await _getMetadataFromCache(serverId, season.parentRatingKey!)
          : null;
      final showYear = parentMetadata?.year;

      // 获取此季中的所有剧集
      final episodesInSeason = await _database.getEpisodesBySeason(season.ratingKey);

      appLogger.d('正在删除季 ${season.ratingKey} 中的 ${episodesInSeason.length} 个剧集');
      await _deleteEpisodesInCollection(
        episodes: episodesInSeason,
        serverId: serverId,
        parentKey: season.ratingKey,
        parentTitle: season.title,
      );

      final seasonDir = await _storageService.getSeasonDirectory(season, showYear: showYear);
      if (await seasonDir.exists()) {
        await seasonDir.delete(recursive: true);
        appLogger.i('已删除季目录: ${seasonDir.path}');
      }

      await _cleanupShowDirectory(season, showYear);
    } catch (e, stack) {
      appLogger.e('删除季文件出错', error: e, stackTrace: stack);
    }
  }

  /// 删除集合中的剧集 (季或剧集)
  /// 返回删除的剧集数
  Future<void> _deleteEpisodesInCollection({
    required List<DownloadedMediaItem> episodes,
    required String serverId,
    required String parentKey,
    required String parentTitle,
  }) async {
    for (int i = 0; i < episodes.length; i++) {
      final episode = episodes[i];
      final episodeGlobalKey = '$serverId:${episode.ratingKey}';

      // 发送进度更新
      _emitDeletionProgress(
        DeletionProgress(
          globalKey: '$serverId:$parentKey',
          itemTitle: parentTitle,
          currentItem: i + 1,
          totalItems: episodes.length,
          currentOperation: '正在删除第 ${i + 1}/${episodes.length} 个剧集',
        ),
      );

      // 删除章节缩略图
      await _deleteChapterThumbnails(serverId, episode.ratingKey);

      // 删除剧集文件 (视频、字幕)
      await _deleteByFilePath(episode);

      // 从 API 缓存中删除剧集
      await _apiCache.deleteForItem(serverId, episode.ratingKey);

      // 删除剧集数据库条目
      await _database.deleteDownload(episodeGlobalKey);
    }
  }

  /// 删除剧集文件
  Future<void> _deleteShowFiles(PlexMetadata show, String serverId) async {
    try {
      // 获取此剧集中的所有剧集
      final episodesInShow = await _database.getEpisodesByShow(show.ratingKey);

      appLogger.d('正在删除剧集 ${show.ratingKey} 中的 ${episodesInShow.length} 个剧集');
      await _deleteEpisodesInCollection(
        episodes: episodesInShow,
        serverId: serverId,
        parentKey: show.ratingKey,
        parentTitle: show.title,
      );

      final showDir = await _storageService.getShowDirectory(show);
      if (await showDir.exists()) {
        await showDir.delete(recursive: true);
        appLogger.i('已删除剧集目录: ${showDir.path}');
      }
    } catch (e, stack) {
      appLogger.e('删除剧集文件出错', error: e, stackTrace: stack);
    }
  }

  /// 删除电影文件
  Future<void> _deleteMovieFiles(PlexMetadata movie, String serverId) async {
    try {
      final movieDir = await _storageService.getMovieDirectory(movie);
      if (await movieDir.exists()) {
        await movieDir.delete(recursive: true);
        appLogger.i('已删除电影目录: ${movieDir.path}');
      }

      // 删除章节缩略图 (带引用计数)
      await _deleteChapterThumbnails(serverId, movie.ratingKey);
    } catch (e, stack) {
      appLogger.e('删除电影文件出错', error: e, stackTrace: stack);
    }
  }

  /// 删除剧集后清理空目录
  Future<void> _cleanupEmptyDirectories(PlexMetadata episode, int? showYear) async {
    final seasonDir = await _storageService.getSeasonDirectory(episode, showYear: showYear);

    if (await seasonDir.exists()) {
      final contents = await seasonDir.list().toList();
      final hasVideos = contents.any(
        (e) =>
            e.path.endsWith('.mp4') ||
            e.path.endsWith('.ogv') ||
            e.path.endsWith('.mkv') ||
            e.path.endsWith('.m4v') ||
            e.path.endsWith('.avi') ||
            e.path.contains('_subs'),
      );

      if (!hasVideos) {
        if (!await _isSeasonArtworkInUse(episode, showYear)) {
          await seasonDir.delete(recursive: true);
          appLogger.i('已删除空季目录: ${seasonDir.path}');
          await _cleanupShowDirectory(episode, showYear);
        }
      }
    }
  }

  /// 如果为空则清理剧集目录
  Future<void> _cleanupShowDirectory(PlexMetadata metadata, int? showYear) async {
    final showDir = await _storageService.getShowDirectory(metadata, showYear: showYear);

    if (await showDir.exists()) {
      final contents = await showDir.list().toList();
      final hasSeasons = contents.any((e) => e is Directory && e.path.contains('Season '));

      if (!hasSeasons) {
        if (!await _isShowArtworkInUse(metadata, showYear)) {
          await showDir.delete(recursive: true);
          appLogger.i('已删除空剧集目录: ${showDir.path}');
        }
      }
    }
  }

  /// 检查季封面图是否在使用中
  Future<bool> _isSeasonArtworkInUse(PlexMetadata episode, int? showYear) async {
    final seasonKey = episode.parentRatingKey;
    if (seasonKey == null) return false;

    final otherEpisodes = await _database.getEpisodesBySeason(seasonKey);

    // 检查除此剧集外是否还有其他剧集
    return otherEpisodes.any((e) => e.globalKey != '${episode.serverId}:${episode.ratingKey}');
  }

  /// 检查剧集封面图是否在使用中
  Future<bool> _isShowArtworkInUse(PlexMetadata metadata, int? showYear) async {
    final showKey = metadata.grandparentRatingKey ?? metadata.parentRatingKey ?? metadata.ratingKey;

    final allItems = await _database.select(_database.downloadedMedia).get();

    // 检查除此项目外是否还有其他属于此剧集的项目
    return allItems.any(
      (item) =>
          (item.grandparentRatingKey == showKey || item.parentRatingKey == showKey) &&
          item.globalKey != '${metadata.serverId}:${metadata.ratingKey}',
    );
  }

  /// 查找具有任意扩展名的文件
  Future<File?> _findFileWithAnyExtension(String pathWithoutExt) async {
    final dir = Directory(path.dirname(pathWithoutExt));
    final baseName = path.basename(pathWithoutExt);

    if (!await dir.exists()) return null;

    try {
      final files = await dir
          .list()
          .where((e) => e is File && path.basenameWithoutExtension(e.path) == baseName)
          .toList();

      return files.isNotEmpty ? files.first as File : null;
    } catch (e) {
      appLogger.w('查找文件出错: $pathWithoutExt', error: e);
      return null;
    }
  }

  /// 使用数据库中的文件路径进行回退删除
  Future<void> _deleteByFilePath(DownloadedMediaItem record) async {
    try {
      if (record.videoFilePath != null) {
        final videoPath = await _storageService.toAbsolutePath(record.videoFilePath!);
        final videoDeleted = await _deleteFileIfExists(File(videoPath), '视频文件');

        // 如果视频已删除，则删除字幕目录
        if (videoDeleted) {
          final subsPath = videoPath.replaceAll(RegExp(r'\.[^.]+$'), '_subs');
          final subsDir = Directory(subsPath);
          if (await subsDir.exists()) {
            await subsDir.delete(recursive: true);
            appLogger.i('已删除字幕: $subsPath');
          }
        }
      }

      if (record.thumbPath != null) {
        final thumbPath = await _storageService.toAbsolutePath(record.thumbPath!);
        await _deleteFileIfExists(File(thumbPath), '缩略图');
      }
    } catch (e, stack) {
      appLogger.e('回退删除出错', error: e, stackTrace: stack);
    }
  }

  /// 获取具有特定状态的所有下载项目
  Stream<List<DownloadedMediaItem>> watchDownloadsByStatus(DownloadStatus status) {
    return (_database.select(_database.downloadedMedia)..where((t) => t.status.equals(status.index))).watch();
  }

  /// 获取所有已下载的媒体项目 (用于加载持久化数据)
  Future<List<DownloadedMediaItem>> getAllDownloads() async {
    return _database.select(_database.downloadedMedia).get();
  }

  /// 根据 globalKey 获取特定的已下载媒体项目
  Future<DownloadedMediaItem?> getDownloadedMedia(String globalKey) async {
    return _database.getDownloadedMedia(globalKey);
  }

  /// 保存媒体项目 (剧集、季、电影或剧集) 的元数据
  /// 用于持久化父级元数据 (剧集/季)，以便离线显示
  Future<void> saveMetadata(PlexMetadata metadata) async {
    if (metadata.serverId == null) {
      appLogger.w('没有 serverId 无法保存元数据');
      return;
    }

    // 缓存到 API 缓存以便离线使用
    await _cacheMetadataForOffline(metadata.serverId!, metadata.ratingKey, metadata);
  }

  /// 以 API 响应格式缓存元数据以便离线访问
  /// 这模拟了 PlexClient 从服务器接收到的内容
  Future<void> _cacheMetadataForOffline(String serverId, String ratingKey, PlexMetadata metadata) async {
    final endpoint = '/library/metadata/$ratingKey';

    // 构建匹配 Plex API 格式的响应结构
    final cachedResponse = {
      'MediaContainer': {
        'Metadata': [metadata.toJson()],
      },
    };

    await _apiCache.put(serverId, endpoint, cachedResponse);
    await _apiCache.pinForOffline(serverId, ratingKey);
  }

  /// 以 API 响应格式缓存子项 (季或剧集)
  Future<void> cacheChildrenForOffline(String serverId, String parentRatingKey, List<PlexMetadata> children) async {
    final endpoint = '/library/metadata/$parentRatingKey/children';

    // 构建匹配 Plex API 格式的响应结构
    final cachedResponse = {
      'MediaContainer': {'Metadata': children.map((c) => c.toJson()).toList()},
    };

    await _apiCache.put(serverId, endpoint, cachedResponse);
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    for (final token in _activeDownloads.values) {
      token.cancel('服务已销毁');
    }
    _progressController.close();
    _deletionProgressController.close();
  }
}
