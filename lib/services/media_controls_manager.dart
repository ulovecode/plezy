import 'package:os_media_controls/os_media_controls.dart';
import 'package:rate_limiter/rate_limiter.dart';

import 'plex_client.dart';
import '../models/plex_metadata.dart';
import '../utils/content_utils.dart';
import '../utils/app_logger.dart';

/// 管理视频播放的操作系统媒体控制集成。
///
/// 处理：
/// - 元数据更新 (标题、封面图等)
/// - 播放状态更新 (播放/暂停、位置、速度)
/// - 控制事件流 (播放、暂停、下一集、上一集、跳转)
/// - 位置更新节流以防止过多的 API 调用
class MediaControlsManager {
  /// 来自操作系统媒体控制的控制事件流
  Stream<dynamic> get controlEvents => OsMediaControls.controlEvents;

  /// 节流播放状态更新 (1 秒间隔，首位 + 末位)
  late final Throttle _throttledUpdate;

  /// 缓存控制启用状态以避免冗余的平台调用
  bool? _lastCanGoNext;
  bool? _lastCanGoPrevious;

  MediaControlsManager() {
    _throttledUpdate = throttle(
      _doUpdatePlaybackState,
      const Duration(seconds: 1),
      leading: true,
      trailing: true, // 在节流窗口结束时发送最终位置
    );
  }

  /// 更新操作系统媒体控制中显示的媒体元数据
  ///
  /// 这包括标题、艺术家、封面图和时长。
  Future<void> updateMetadata({required PlexMetadata metadata, PlexClient? client, Duration? duration}) async {
    try {
      // 如果客户端可用，构建封面图 URL
      String? artworkUrl;
      if (client != null && metadata.thumb != null) {
        try {
          artworkUrl = client.getThumbnailUrl(metadata.thumb!);
          appLogger.d('媒体控制的封面图 URL: $artworkUrl');
        } catch (e) {
          appLogger.w('构建封面图 URL 失败', error: e);
        }
      }

      // 更新操作系统媒体控制
      await OsMediaControls.setMetadata(
        MediaMetadata(
          title: metadata.title,
          artist: _buildArtist(metadata),
          artworkUrl: artworkUrl,
          duration: duration,
        ),
      );

      appLogger.d('已更新媒体控制元数据: ${metadata.title}');
    } catch (e) {
      appLogger.w('更新媒体控制元数据失败', error: e);
    }
  }

  /// 更新操作系统媒体控制中的播放状态
  ///
  /// 更新当前的播放状态、位置和播放速度。
  /// 位置更新经过节流以避免过多的 API 调用。
  Future<void> updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required double speed,
    bool force = false,
  }) async {
    final params = _PlaybackStateParams(isPlaying: isPlaying, position: position, speed: speed);

    if (force) {
      // 强制更新绕过节流
      await _doUpdatePlaybackState(params);
    } else {
      // 使用节流更新
      _throttledUpdate([params]);
    }
  }

  /// 实际执行播放状态更新的内部方法
  Future<void> _doUpdatePlaybackState(_PlaybackStateParams params) async {
    try {
      await OsMediaControls.setPlaybackState(
        MediaPlaybackState(
          state: params.isPlaying ? PlaybackState.playing : PlaybackState.paused,
          position: params.position,
          speed: params.speed,
        ),
      );
    } catch (e) {
      appLogger.w('更新媒体控制播放状态失败', error: e);
    }
  }

  /// 启用或禁用下一集/上一集轨道控制
  ///
  /// 应根据内容类型和播放模式调用。
  /// 例如：
  /// - 剧集：如果存在相邻剧集，则同时启用
  /// - 播放列表项目：根据播放列表位置启用
  /// - 电影：通常禁用
  Future<void> setControlsEnabled({bool canGoNext = false, bool canGoPrevious = false}) async {
    // 如果未更改则跳过 (避免冗余平台调用)
    if (canGoNext == _lastCanGoNext && canGoPrevious == _lastCanGoPrevious) {
      return;
    }

    _lastCanGoNext = canGoNext;
    _lastCanGoPrevious = canGoPrevious;

    try {
      final controls = <MediaControl>[];
      if (canGoPrevious) controls.add(MediaControl.previous);
      if (canGoNext) controls.add(MediaControl.next);

      if (controls.isNotEmpty) {
        await OsMediaControls.enableControls(controls);
        appLogger.d('媒体控制已启用 - 上一集: $canGoPrevious, 下一集: $canGoNext');
      } else {
        await OsMediaControls.disableControls([MediaControl.previous, MediaControl.next]);
        appLogger.d('媒体控制已禁用');
      }
    } catch (e) {
      appLogger.w('设置媒体控制启用状态失败', error: e);
    }
  }

  /// 清除所有媒体控制
  ///
  /// 应在播放停止或屏幕销毁时调用。
  Future<void> clear() async {
    try {
      await OsMediaControls.clear();
      _throttledUpdate.cancel();
      appLogger.d('已清除媒体控制');
    } catch (e) {
      appLogger.w('清除媒体控制失败', error: e);
    }
  }

  /// 释放资源
  void dispose() {
    _throttledUpdate.cancel();
  }

  /// 从元数据构建艺术家字符串
  ///
  /// 对于剧集: "剧集名称 - 第 X 季 第 Y 集"
  /// 对于电影: 导演或制片商
  /// 对于其他内容: 回退到年份或为空
  String _buildArtist(PlexMetadata metadata) {
    if (metadata.isEpisode) {
      final parts = <String>[];

      // 添加剧集名称
      if (metadata.grandparentTitle != null) {
        parts.add(metadata.grandparentTitle!);
      }

      // 添加季/集信息
      if (metadata.parentIndex != null && metadata.index != null) {
        parts.add('S${metadata.parentIndex} E${metadata.index}');
      } else if (metadata.parentTitle != null) {
        parts.add(metadata.parentTitle!);
      }

      return parts.join(' • ');
    } else if (metadata.isMovie) {
      // 对于电影，使用导演或制片商
      // 注意：这些字段可能需要添加到 PlexMetadata 模型中
      if (metadata.year != null) {
        return metadata.year.toString();
      }
    }

    return '';
  }
}

/// 播放状态更新的参数 (与节流一起使用)
class _PlaybackStateParams {
  final bool isPlaying;
  final Duration position;
  final double speed;

  const _PlaybackStateParams({required this.isPlaying, required this.position, required this.speed});
}
