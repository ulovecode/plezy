import 'package:flutter/material.dart';
import '../models/plex_metadata.dart';
import '../models/plex_playlist.dart';
import '../screens/collection_detail_screen.dart';
import '../screens/media_detail_screen.dart';
import '../screens/season_detail_screen.dart';
import '../screens/playlist/playlist_detail_screen.dart';
import 'video_player_navigation.dart';

/// 媒体导航结果，指示采取了什么操作
enum MediaNavigationResult {
  /// 导航成功完成
  navigated,

  /// 导航已完成，父列表需要刷新（例如，集合已删除）
  listRefreshNeeded,

  /// 不支持的项目类型（例如，音乐内容）
  unsupported,
}

/// 根据项目类型导航到相应的屏幕。
///
/// 对于单集 (episode)，直接通过视频播放器开始播放。
/// 对于季 (season)，导航到季详情屏幕。
/// 对于播放列表 (playlist)，导航到播放列表详情屏幕。
/// 对于集合 (collection)，导航到集合详情屏幕。
/// 对于其他类型（剧集 show、电影 movie），导航到媒体详情屏幕。
/// 对于音乐类型（艺术家 artist、专辑 album、曲目 track），返回 [MediaNavigationResult.unsupported]。
///
/// 从详情屏幕返回后，会使用项目的 ratingKey 调用 [onRefresh] 回调，允许调用者刷新状态。
///
/// 对于没有服务器访问权限的已下载内容，将 [isOffline] 设置为 true。
///
/// 返回一个 [MediaNavigationResult]，指示采取了什么操作：
/// - [MediaNavigationResult.navigated]：导航已完成，项目刷新已处理
/// - [MediaNavigationResult.listRefreshNeeded]：调用者应刷新整个列表
/// - [MediaNavigationResult.unsupported]：不支持项目类型，调用者应自行处理
Future<MediaNavigationResult> navigateToMediaItem(
  BuildContext context,
  dynamic item, {
  void Function(String)? onRefresh,
  bool isOffline = false,
}) async {
  // 处理播放列表
  if (item is PlexPlaylist) {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => PlaylistDetailScreen(playlist: item)));
    return MediaNavigationResult.navigated;
  }

  final metadata = item as PlexMetadata;

  switch (metadata.mediaType) {
    case PlexMediaType.collection:
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => CollectionDetailScreen(collection: metadata)),
      );
      // 如果集合已删除，发出需要刷新列表的信号
      if (result == true) {
        return MediaNavigationResult.listRefreshNeeded;
      }
      return MediaNavigationResult.navigated;

    case PlexMediaType.artist:
    case PlexMediaType.album:
    case PlexMediaType.track:
      // 不支持音乐类型
      return MediaNavigationResult.unsupported;

    case PlexMediaType.episode:
      // 对于单集，直接开始播放
      final result = await navigateToVideoPlayer(context, metadata: metadata, isOffline: isOffline);
      if (result == true) {
        onRefresh?.call(metadata.ratingKey);
      }
      return MediaNavigationResult.navigated;

    case PlexMediaType.season:
      await Navigator.push(context, MaterialPageRoute(builder: (context) => SeasonDetailScreen(season: metadata)));
      onRefresh?.call(metadata.ratingKey);
      return MediaNavigationResult.navigated;

    default:
      // 对于所有其他类型（剧集、电影），显示详情屏幕
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => MediaDetailScreen(metadata: metadata, isOffline: isOffline),
        ),
      );
      if (result == true) {
        onRefresh?.call(metadata.ratingKey);
      }
      return MediaNavigationResult.navigated;
  }
}
