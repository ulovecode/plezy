import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/play_queue_response.dart';
import '../models/plex_metadata.dart';
import '../models/plex_playlist.dart';
import '../providers/playback_state_provider.dart';
import '../utils/app_logger.dart';
import '../utils/snackbar_helper.dart';
import '../utils/video_player_navigation.dart';
import '../i18n/strings.g.dart';
import 'plex_client.dart';

/// 播放队列操作的结果类型
sealed class PlayQueueResult {
  const PlayQueueResult();
}

class PlayQueueSuccess extends PlayQueueResult {
  const PlayQueueSuccess();
}

class PlayQueueEmpty extends PlayQueueResult {
  const PlayQueueEmpty();
}

class PlayQueueError extends PlayQueueResult {
  final Object error;
  const PlayQueueError(this.error);
}

/// 处理播放队列创建和导航的服务。
///
/// 集中处理以下常见模式：
/// 1. 通过各种方法创建播放队列
/// 2. 设置 PlaybackStateProvider
/// 3. 导航到视频播放器
/// 4. 处理带有适当反馈的错误
class PlayQueueLauncher {
  final BuildContext context;
  final PlexClient client;
  final String? serverId;
  final String? serverName;

  PlayQueueLauncher({required this.context, required this.client, this.serverId, this.serverName});

  /// 从集合或播放列表启动播放。
  Future<PlayQueueResult> launchFromCollectionOrPlaylist({
    required dynamic item, // PlexMetadata (集合) 或 PlexPlaylist
    required bool shuffle,
    bool showLoadingIndicator = true,
  }) async {
    final isCollection = item is PlexMetadata;
    final isPlaylist = item is PlexPlaylist;

    if (!isCollection && !isPlaylist) {
      return PlayQueueError(Exception('项目必须是集合或播放列表'));
    }

    return _executeWithLoading(
      showLoading: showLoadingIndicator,
      action: t.common.shuffle,
      execute: (dismissLoading) async {
        final String ratingKey = item.ratingKey;
        final String? itemServerId = item.serverId ?? serverId;
        final String? itemServerName = item.serverName ?? serverName;

        PlayQueueResponse? playQueue;

        if (isCollection) {
          // 获取机器标识符 (如果配置中未缓存则获取)
          final machineId = client.config.machineIdentifier ?? await client.getMachineIdentifier();

          if (machineId == null) {
            throw Exception('无法获取服务器机器标识符');
          }

          final collectionUri = 'server://$machineId/com.plexapp.plugins.library/library/collections/${item.ratingKey}';
          playQueue = await client.createPlayQueue(uri: collectionUri, type: 'video', shuffle: shuffle ? 1 : 0);
        } else {
          // 对于播放列表，使用 playlistID 参数
          playQueue = await client.createPlayQueue(
            playlistID: int.parse(item.ratingKey),
            type: 'video',
            shuffle: shuffle ? 1 : 0,
          );
        }

        // 如果队列为空，尝试使用 getPlayQueue 再次获取
        if (playQueue != null && (playQueue.items == null || playQueue.items!.isEmpty)) {
          final fetchedQueue = await client.getPlayQueue(playQueue.playQueueID);
          if (fetchedQueue != null && fetchedQueue.items != null && fetchedQueue.items!.isNotEmpty) {
            playQueue = fetchedQueue;
          }
        }

        // 在导航到播放器之前关闭加载对话框
        await dismissLoading();

        return _launchFromQueue(
          playQueue: playQueue,
          ratingKey: ratingKey,
          serverId: itemServerId,
          serverName: itemServerName,
        );
      },
    );
  }

  /// 从播放列表中的特定项目开始启动播放。
  Future<PlayQueueResult> launchFromPlaylistItem({
    required PlexPlaylist playlist,
    required PlexMetadata selectedItem,
    bool showLoadingIndicator = true,
  }) async {
    return _executeWithLoading(
      showLoading: showLoadingIndicator,
      action: t.discover.play,
      execute: (dismissLoading) async {
        final playQueue = await client.createPlayQueue(
          playlistID: int.parse(playlist.ratingKey),
          type: 'video',
          key: selectedItem.key,
        );

        // 在导航到播放器之前关闭加载对话框
        await dismissLoading();

        return _launchFromQueue(
          playQueue: playQueue,
          ratingKey: playlist.ratingKey,
          serverId: serverId,
          serverName: serverName,
          selectedItem: playQueue?.selectedItem,
        );
      },
    );
  }

  /// 为剧集或季启动随机播放。
  Future<PlayQueueResult> launchShuffledShow({required PlexMetadata metadata, bool showLoadingIndicator = true}) async {
    final mediaType = metadata.mediaType;

    if (mediaType != PlexMediaType.show && mediaType != PlexMediaType.season) {
      return PlayQueueError(Exception('随机播放仅适用于剧集和季'));
    }

    return _executeWithLoading(
      showLoading: showLoadingIndicator,
      action: t.common.shuffle,
      execute: (dismissLoading) async {
        // 确定播放队列的 rating key
        String showRatingKey;
        if (mediaType == PlexMediaType.show) {
          showRatingKey = metadata.ratingKey;
        } else {
          // 对于季，我们需要剧集的 rating key
          if (metadata.parentRatingKey == null) {
            throw Exception('季缺少 parentRatingKey');
          }
          showRatingKey = metadata.parentRatingKey!;
        }

        final playQueue = await client.createShowPlayQueue(showRatingKey: showRatingKey, shuffle: 1);

        // 在导航到播放器之前关闭加载对话框
        await dismissLoading();

        return _launchFromQueue(
          playQueue: playQueue,
          ratingKey: showRatingKey,
          serverId: metadata.serverId ?? serverId,
          serverName: metadata.serverName ?? serverName,
          copyServerInfo: true,
        );
      },
    );
  }

  /// 从播放队列启动播放的核心方法。
  Future<PlayQueueResult> _launchFromQueue({
    required PlayQueueResponse? playQueue,
    required String ratingKey,
    String? serverId,
    String? serverName,
    PlexMetadata? selectedItem,
    bool copyServerInfo = false,
  }) async {
    if (playQueue == null || playQueue.items == null || playQueue.items!.isEmpty) {
      return const PlayQueueEmpty();
    }

    if (!context.mounted) return const PlayQueueError('Context not mounted');

    // 设置播放状态
    final playbackState = context.read<PlaybackStateProvider>();
    playbackState.setClient(client);
    await playbackState.setPlaybackFromPlayQueue(playQueue, ratingKey, serverId: serverId, serverName: serverName);

    if (!context.mounted) return const PlayQueueError('Context not mounted');

    // 确定导航到哪个项目
    var itemToPlay = selectedItem ?? playQueue.items!.first;

    // 如果需要，复制服务器信息
    if (copyServerInfo && serverId != null) {
      itemToPlay = itemToPlay.copyWith(serverId: serverId, serverName: serverName);
    }

    // 导航到视频播放器
    await navigateToVideoPlayer(context, metadata: itemToPlay);

    return const PlayQueueSuccess();
  }

  /// 执行带有可选加载指示器和错误处理的操作。
  Future<PlayQueueResult> _executeWithLoading({
    required bool showLoading,
    required String action,
    required Future<PlayQueueResult> Function(Future<void> Function() dismissLoading) execute,
  }) async {
    BuildContext? loadingDialogContext;
    var loadingVisible = false;

    // 显示加载指示器
    if (showLoading && context.mounted) {
      loadingVisible = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          loadingDialogContext = dialogContext;
          return const Center(child: CircularProgressIndicator());
        },
      );
    }

    Future<void> dismissLoading() async {
      if (!showLoading || !loadingVisible) return;
      final dialogContext = loadingDialogContext;
      if (dialogContext == null) return;

      // 仅当对话框仍然是当前路由时才关闭，以避免
      // 在导航后意外关闭播放器。
      final route = ModalRoute.of(dialogContext);
      if (route?.isCurrent ?? false) {
        Navigator.of(dialogContext).pop();
      }

      loadingVisible = false;
    }

    try {
      final result = await execute(dismissLoading);

      // 处理空队列结果
      if (result is PlayQueueEmpty && context.mounted) {
        showErrorSnackBar(context, t.messages.failedToCreatePlayQueueNoItems);
      }

      await dismissLoading();
      return result;
    } catch (e) {
      appLogger.e('操作失败: $action', error: e);

      if (context.mounted) {
        showErrorSnackBar(context, t.messages.failedPlayback(action: action, error: e.toString()));
      }

      await dismissLoading();
      return PlayQueueError(e);
    } finally {
      await dismissLoading();
    }
  }
}
