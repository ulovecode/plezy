import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mpv/mpv.dart';
import 'plex_client.dart';
import '../models/plex_metadata.dart';
import '../providers/playback_state_provider.dart';
import '../utils/app_logger.dart';
import '../utils/video_player_navigation.dart';

/// 加载相邻剧集的结果
class AdjacentEpisodes {
  final PlexMetadata? next;
  final PlexMetadata? previous;

  AdjacentEpisodes({this.next, this.previous});

  bool get hasNext => next != null;
  bool get hasPrevious => previous != null;
}

/// 管理电视剧播放的剧集导航。
///
/// 处理：
/// - 从播放队列加载下一集/前一集
/// - 在剧集之间导航，同时保留轨道选择
/// - 支持顺序和随机播放模式
///
/// 所有剧集导航都使用 Plex 播放队列以获得一致的行为。
class EpisodeNavigationService {
  /// 加载当前剧集的下一集和前一集
  ///
  /// 如果出现以下情况，剧集返回 null：
  /// - 不适用 (例如电影内容)
  /// - 下一集不存在 (季末/剧终)
  /// - 前一集不存在 (第一集)
  Future<AdjacentEpisodes> loadAdjacentEpisodes({
    required BuildContext context,
    required PlexClient client,
    required PlexMetadata metadata,
  }) async {
    try {
      final playbackState = context.read<PlaybackStateProvider>();

      // 所有剧集导航现在都使用播放队列 (顺序、随机、播放列表)
      // 如果没有活动的队列，导航将不可用
      if (!playbackState.isQueueActive) {
        return AdjacentEpisodes();
      }

      // 使用播放队列进行下一集/前一集导航
      final next = await playbackState.getNextEpisode(metadata.ratingKey, loopQueue: false);
      final previous = await playbackState.getPreviousEpisode(metadata.ratingKey);

      final mode = playbackState.isShuffleActive ? '随机' : '顺序';
      appLogger.d('$mode 模式 - 下一集: ${next?.title}, 上一集: ${previous?.title}');

      return AdjacentEpisodes(next: next, previous: previous);
    } catch (e) {
      // 非关键错误：加载下一集/前一集元数据失败
      appLogger.d('无法加载相邻剧集', error: e);
      return AdjacentEpisodes();
    }
  }

  /// 导航到下一集或前一集
  ///
  /// 在剧集转换时保留当前的音频轨道、字幕轨道和播放速度。
  Future<void> navigateToEpisode({
    required BuildContext context,
    required PlexMetadata episode,
    required Player? player,
    bool usePushReplacement = true,
  }) async {
    if (!context.mounted) return;

    // 在导航前捕获当前的播放器状态
    AudioTrack? currentAudioTrack;
    SubtitleTrack? currentSubtitleTrack;
    double? currentPlaybackRate;

    if (player != null) {
      currentAudioTrack = player.state.track.audio;
      currentSubtitleTrack = player.state.track.subtitle;
      currentPlaybackRate = player.state.rate;

      appLogger.d(
        '正在导航到剧集，保留设置 - 音频: ${currentAudioTrack?.id}, 字幕: ${currentSubtitleTrack?.id}, 速度: ${currentPlaybackRate}x',
      );
    }

    // 导航到新剧集
    if (context.mounted) {
      navigateToVideoPlayer(
        context,
        metadata: episode,
        preferredAudioTrack: currentAudioTrack,
        preferredSubtitleTrack: currentSubtitleTrack,
        preferredPlaybackRate: currentPlaybackRate,
        usePushReplacement: usePushReplacement,
      );
    }
  }
}
