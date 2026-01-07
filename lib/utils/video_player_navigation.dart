import 'package:flutter/material.dart';

import '../mpv/mpv.dart';
import '../models/plex_metadata.dart';
import '../screens/video_player_screen.dart';
import '../services/settings_service.dart';
import 'app_logger.dart';

const String kVideoPlayerRouteName = '/video_player';

/// 导航到 VideoPlayerScreen，使用即时过渡以防止白屏闪烁。
///
/// 此工具函数在整个应用程序中提供了一致的视频播放器导航方式，
/// 使用 PageRouteBuilder 配合零持续时间的过渡，
/// 以消除 MaterialPageRoute 中出现的白屏闪烁。
///
/// 参数：
/// - [context]: 用于导航的构建上下文
/// - [metadata]: 要播放内容的 Plex 元数据
/// - [preferredAudioTrack]: 可选，播放开始时选择的首选音频轨道
/// - [preferredSubtitleTrack]: 可选，播放开始时选择的首选字幕轨道
/// - [preferredPlaybackRate]: 可选，播放开始时设置的首选播放速度
/// - [selectedMediaIndex]: 可选，要使用的媒体版本索引；如果未提供，
///   则加载该系列/电影的保存偏好。如果没有偏好设置，则默认为 0。
/// - [usePushReplacement]: 如果为 true，则替换当前路由而不是推入新路由；
///   对剧集间的连续播放导航很有用。默认为 false。
/// - [isOffline]: 如果为 true，则从下载的内容播放，无需服务器连接。
///
/// 返回一个 Future，完成后返回一个布尔值，指示内容是否已被观看，
/// 如果导航被取消，则返回 null。
Future<bool?> navigateToVideoPlayer(
  BuildContext context, {
  required PlexMetadata metadata,
  AudioTrack? preferredAudioTrack,
  SubtitleTrack? preferredSubtitleTrack,
  double? preferredPlaybackRate,
  int? selectedMediaIndex,
  bool usePushReplacement = false,
  bool isOffline = false,
}) async {
  // 在任何异步操作之前提取 navigator
  final navigator = Navigator.of(context);

  // 如果没有明确提供，则加载保存的媒体版本偏好
  int mediaIndex = selectedMediaIndex ?? 0;
  if (selectedMediaIndex == null) {
    try {
      final settingsService = await SettingsService.getInstance();
      final seriesKey = metadata.grandparentRatingKey ?? metadata.ratingKey;
      final savedPreference = settingsService.getMediaVersionPreference(seriesKey);
      if (savedPreference != null) {
        mediaIndex = savedPreference;
      }
    } catch (e) {
      // 忽略加载偏好时的错误，使用默认值
    }
  }

  // 防止在已经激活时堆叠相同的视频播放器
  if (!usePushReplacement &&
      VideoPlayerScreenState.activeRatingKey == metadata.ratingKey &&
      VideoPlayerScreenState.activeMediaIndex == mediaIndex) {
    appLogger.d(
      '视频播放器已为 ${metadata.ratingKey} (mediaIndex=$mediaIndex) 激活，跳过重复导航',
    );
    return null;
  }

  final route = PageRouteBuilder<bool>(
    settings: const RouteSettings(name: kVideoPlayerRouteName),
    pageBuilder: (context, animation, secondaryAnimation) => VideoPlayerScreen(
      metadata: metadata,
      preferredAudioTrack: preferredAudioTrack,
      preferredSubtitleTrack: preferredSubtitleTrack,
      preferredPlaybackRate: preferredPlaybackRate,
      selectedMediaIndex: mediaIndex,
      isOffline: isOffline,
    ),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );

  if (usePushReplacement) {
    return navigator.pushReplacement<bool, bool>(route);
  } else {
    return navigator.push<bool>(route);
  }
}

/// 导航到视频播放器，并可选地在返回时刷新内容。
///
/// 此辅助方法整合了以下常见模式：
/// 1. 导航到视频播放器
/// 2. 记录返回日志
/// 3. 如果不是离线模式，则调用刷新回调
///
/// 参数：
/// - [context]: 用于导航的构建上下文
/// - [metadata]: 要播放内容的 Plex 元数据
/// - [isOffline]: 如果为 true，则从下载的内容播放
/// - [onRefresh]: 可选，从播放返回时刷新数据的回调
///   （仅在非离线模式下调用）
/// - 所有其他参数都传递给 [navigateToVideoPlayer]
Future<bool?> navigateToVideoPlayerWithRefresh(
  BuildContext context, {
  required PlexMetadata metadata,
  bool isOffline = false,
  VoidCallback? onRefresh,
  AudioTrack? preferredAudioTrack,
  SubtitleTrack? preferredSubtitleTrack,
  double? preferredPlaybackRate,
  int? selectedMediaIndex,
  bool usePushReplacement = false,
}) async {
  final result = await navigateToVideoPlayer(
    context,
    metadata: metadata,
    isOffline: isOffline,
    preferredAudioTrack: preferredAudioTrack,
    preferredSubtitleTrack: preferredSubtitleTrack,
    preferredPlaybackRate: preferredPlaybackRate,
    selectedMediaIndex: selectedMediaIndex,
    usePushReplacement: usePushReplacement,
  );

  appLogger.d('从播放返回，正在刷新元数据');

  // 从视频播放器返回时刷新数据（离线模式跳过）
  if (!isOffline && onRefresh != null) {
    onRefresh();
  }

  return result;
}
