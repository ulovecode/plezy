import 'plex_client.dart';
import '../models/plex_media_info.dart';
import '../models/plex_metadata.dart';
import '../models/download_models.dart';
import '../mpv/mpv.dart';
import '../utils/app_logger.dart';
import '../i18n/strings.g.dart';
import '../database/app_database.dart';
import 'download_storage_service.dart';
import 'dart:io';
import 'package:drift/drift.dart';

/// 负责从 Plex 服务器获取视频播放数据的服务
class PlaybackInitializationService {
  final PlexClient client;
  final AppDatabase? database;

  PlaybackInitializationService({required this.client, this.database});

  /// 将视频路径格式化为 URL（为文件路径添加 file:// 前缀）
  String _formatVideoUrl(String path) {
    return path.contains('://') ? path : 'file://$path';
  }

  /// 检查内容是否在离线状态下可用并返回本地路径
  ///
  /// 如果视频已下载并完成，则返回本地文件路径。
  /// 如果离线不可用或未提供数据库，则返回 null。
  Future<String?> getOfflineVideoPath(String serverId, String ratingKey) async {
    if (database == null) {
      return null;
    }

    try {
      // 在数据库中查询具有匹配 serverId 和 ratingKey 的已下载媒体
      final query = database!.select(database!.downloadedMedia)
        ..where((tbl) => tbl.serverId.equals(serverId) & tbl.ratingKey.equals(ratingKey));

      final downloadedItem = await query.getSingleOrNull();

      // 如果未找到或未完成，则返回 null
      if (downloadedItem == null || downloadedItem.status != DownloadStatus.completed.index) {
        return null;
      }

      // 如果没有视频文件路径，则返回 null
      if (downloadedItem.videoFilePath == null) {
        return null;
      }

      final storageService = DownloadStorageService.instance;
      final storedPath = downloadedItem.videoFilePath!;

      // 获取可读路径（处理 SAF URI 和文件路径）
      final readablePath = await storageService.getReadablePath(storedPath);

      // 对于文件路径（非 SAF），验证文件是否存在
      if (!storageService.isSafUri(storedPath)) {
        final file = File(readablePath);
        if (!await file.exists()) {
          appLogger.w('未找到离线视频文件: $readablePath (存储为: $storedPath)');
          return null;
        }
      }

      appLogger.d('找到离线视频: $readablePath');
      return readablePath;
    } catch (e) {
      appLogger.w('检查离线视频路径时出错', error: e);
      return null;
    }
  }

  /// 获取给定元数据的播放数据
  ///
  /// 返回包含视频 URL 和可用版本的 PlaybackInitializationResult
  /// 如果 [preferOffline] 为 true 且离线内容可用，则使用本地文件
  Future<PlaybackInitializationResult> getPlaybackData({
    required PlexMetadata metadata,
    required int selectedMediaIndex,
    bool preferOffline = false,
  }) async {
    try {
      // 如果启用了 preferOffline，首先检查离线内容
      String? offlineVideoPath;
      if (preferOffline && database != null) {
        offlineVideoPath = await getOfflineVideoPath(client.serverId, metadata.ratingKey);
      }

      // 如果离线视频可用，则使用它
      if (offlineVideoPath != null) {
        appLogger.d('正在为 ${metadata.ratingKey} 使用离线播放');

        // 对于离线播放，我们仍需要获取媒体信息以获取字幕，
        // 但视频使用本地文件路径
        try {
          final playbackData = await client.getVideoPlaybackData(metadata.ratingKey, mediaIndex: selectedMediaIndex);

          // 构建外部字幕轨道列表
          final externalSubtitles = _buildExternalSubtitles(playbackData.mediaInfo);

          // 返回带有本地文件路径的结果
          return PlaybackInitializationResult(
            availableVersions: playbackData.availableVersions,
            videoUrl: _formatVideoUrl(offlineVideoPath),
            mediaInfo: playbackData.mediaInfo,
            externalSubtitles: externalSubtitles,
            isOffline: true,
          );
        } catch (e) {
          // 如果无法获取媒体信息（例如没有网络），则使用仅离线模式
          appLogger.w('无法为离线视频获取媒体信息，使用仅离线模式', error: e);
          return PlaybackInitializationResult(
            availableVersions: [],
            videoUrl: _formatVideoUrl(offlineVideoPath),
            mediaInfo: null,
            externalSubtitles: const [],
            isOffline: true,
          );
        }
      }

      // 回退到网络流媒体
      final playbackData = await client.getVideoPlaybackData(metadata.ratingKey, mediaIndex: selectedMediaIndex);

      if (!playbackData.hasValidVideoUrl) {
        throw PlaybackException(t.messages.fileInfoNotAvailable);
      }

      // 构建外部字幕轨道列表
      final externalSubtitles = _buildExternalSubtitles(playbackData.mediaInfo);

      // 返回带有可用版本和视频 URL 的结果
      return PlaybackInitializationResult(
        availableVersions: playbackData.availableVersions,
        videoUrl: playbackData.videoUrl,
        mediaInfo: playbackData.mediaInfo,
        externalSubtitles: externalSubtitles,
        isOffline: false,
      );
    } catch (e) {
      if (e is PlaybackException) {
        rethrow;
      }
      throw PlaybackException(t.messages.errorLoading(error: e.toString()));
    }
  }

  /// 从媒体信息构建外部字幕轨道列表
  List<SubtitleTrack> _buildExternalSubtitles(PlexMediaInfo? mediaInfo) {
    final externalSubtitles = <SubtitleTrack>[];

    if (mediaInfo == null) {
      return externalSubtitles;
    }

    final externalTracks = mediaInfo.subtitleTracks.where((PlexSubtitleTrack track) => track.isExternal).toList();

    if (externalTracks.isNotEmpty) {
      appLogger.d('找到 ${externalTracks.length} 个外部字幕轨道');
    }

    for (final plexTrack in externalTracks) {
      try {
        // 如果没有认证令牌，则跳过
        final token = client.config.token;
        if (token == null) {
          appLogger.w('没有可用于外部字幕的认证令牌');
          continue;
        }

        final url = plexTrack.getSubtitleUrl(client.config.baseUrl, token);

        // 如果无法构建 URL，则跳过
        if (url == null) continue;

        externalSubtitles.add(
          SubtitleTrack.uri(
            url,
            title: plexTrack.displayTitle ?? plexTrack.language ?? '轨道 ${plexTrack.id}',
            language: plexTrack.languageCode,
          ),
        );
      } catch (e) {
        // 静默回退 - 记录错误但继续处理其他字幕
        appLogger.w('添加外部字幕轨道 ${plexTrack.id} 失败', error: e);
      }
    }

    return externalSubtitles;
  }
}

/// 播放初始化的结果
class PlaybackInitializationResult {
  final List<dynamic> availableVersions;
  final String? videoUrl;
  final PlexMediaInfo? mediaInfo;
  final List<SubtitleTrack> externalSubtitles;
  final bool isOffline;

  PlaybackInitializationResult({
    required this.availableVersions,
    this.videoUrl,
    this.mediaInfo,
    this.externalSubtitles = const [],
    this.isOffline = false,
  });
}

/// Exception thrown when playback initialization fails
class PlaybackException implements Exception {
  final String message;

  PlaybackException(this.message);

  @override
  String toString() => message;
}
