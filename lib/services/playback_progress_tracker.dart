import 'dart:async';

import '../mpv/mpv.dart';

import 'plex_client.dart';
import 'offline_watch_sync_service.dart';
import '../models/plex_metadata.dart';
import '../utils/app_logger.dart';

/// 跟踪播放进度并将其报告给 Plex 服务器。
///
/// 处理：
/// - 播放期间的定期时间线更新 (在线) 或排队 (离线)
/// - 续播位置跟踪
/// - 状态更改报告 (播放中、已暂停、已停止)
/// - 用于以后同步的离线进度排队
class PlaybackProgressTracker {
  /// 用于在线进度更新的 Plex 客户端 (离线时为 null)
  final PlexClient? client;

  /// 正在播放的媒体元数据
  final PlexMetadata metadata;

  /// 视频播放器实例
  final Player player;

  /// 是否处于离线模式播放
  final bool isOffline;

  /// 用于排队离线进度更新的服务
  final OfflineWatchSyncService? offlineWatchService;

  /// 定期进度更新的定时器
  Timer? _progressTimer;

  /// 更新间隔 (默认: 10 秒)
  final Duration updateInterval;

  PlaybackProgressTracker({
    required this.client,
    required this.metadata,
    required this.player,
    this.isOffline = false,
    this.offlineWatchService,
    this.updateInterval = const Duration(seconds: 10),
  }) : assert(!isOffline || offlineWatchService != null, '离线模式下需要提供 offlineWatchService'),
       assert(isOffline || client != null, '在线模式下需要提供 client');

  /// 开始跟踪播放进度
  ///
  /// 开始向 Plex 服务器进行定期时间线更新 (在线)
  /// 或在本地排队进度更新 (离线)。
  void startTracking() {
    if (_progressTimer != null) {
      appLogger.w('进度跟踪已启动');
      return;
    }

    // 立即发送初始进度 (不等待第一次定时器触发)
    if (player.state.playing) {
      _sendProgress('playing');
    }

    _progressTimer = Timer.periodic(updateInterval, (timer) {
      if (player.state.playing) {
        _sendProgress('playing');
      }
    });

    appLogger.d('已启动进度跟踪 (间隔: ${updateInterval.inSeconds}s, 离线: $isOffline)');
  }

  /// 停止跟踪播放进度
  ///
  /// 取消定期定时器。
  void stopTracking() {
    _progressTimer?.cancel();
    _progressTimer = null;
    appLogger.d('已停止进度跟踪');
  }

  /// 向 Plex 服务器发送进度更新或在本地排队
  ///
  /// [state] 可以是 'playing' (播放中), 'paused' (已暂停), 或 'stopped' (已停止)
  Future<void> sendProgress(String state) async {
    await _sendProgress(state);
  }

  Future<void> _sendProgress(String state) async {
    try {
      final position = player.state.position;
      final duration = player.state.duration;

      // 如果没有时长 (尚未就绪)，则不发送进度
      if (duration.inMilliseconds == 0) {
        return;
      }

      if (isOffline) {
        // 排队进度更新以便以后同步
        await _sendOfflineProgress(position, duration);
      } else {
        // 立即向服务器发送进度
        await _sendOnlineProgress(state, position, duration);
      }
    } catch (e) {
      appLogger.d('发送进度更新失败 (非关键)', error: e);
    }
  }

  /// 向 Plex 服务器发送进度更新 (在线模式)
  Future<void> _sendOnlineProgress(String state, Duration position, Duration duration) async {
    await client!.updateProgress(
      metadata.ratingKey,
      time: position.inMilliseconds,
      state: state,
      duration: duration.inMilliseconds,
    );

    appLogger.d('进度更新已发送: $state 位于 ${position.inSeconds}s / ${duration.inSeconds}s');
  }

  /// 在本地排队进度更新 (离线模式)
  Future<void> _sendOfflineProgress(Duration position, Duration duration) async {
    final serverId = metadata.serverId;
    if (serverId == null) {
      appLogger.w('无法排队离线进度: serverId 为 null');
      return;
    }

    await offlineWatchService!.queueProgressUpdate(
      serverId: serverId,
      ratingKey: metadata.ratingKey,
      viewOffset: position.inMilliseconds,
      duration: duration.inMilliseconds,
    );

    final percent = (position.inMilliseconds / duration.inMilliseconds * 100);
    appLogger.d(
      '离线进度已排队: ${position.inSeconds}s / ${duration.inSeconds}s (${percent.toStringAsFixed(1)}%)',
    );
  }

  /// 释放资源
  void dispose() {
    stopTracking();
  }
}
