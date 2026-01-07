import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/plex_metadata.dart';

/// 应用程序中使用的内容类型常量
class ContentTypes {
  ContentTypes._();

  static const String movie = 'movie';
  static const String show = 'show';
  static const String season = 'season';
  static const String episode = 'episode';
  static const String artist = 'artist';
  static const String album = 'album';
  static const String track = 'track';
  static const String collection = 'collection';
  static const String playlist = 'playlist';
  static const String clip = 'clip';

  static const Set<String> musicTypes = {artist, album, track};
  static const Set<String> videoTypes = {movie, show, season, episode};
  static const Set<String> playableTypes = {movie, episode, clip, track};
}

/// 用于内容类型检查和过滤的工具类
class ContentTypeHelper {
  ContentTypeHelper._();

  /// 检查给定类型是否为音乐内容（艺术家、专辑或曲目）
  static bool isMusicContent(String type) => ContentTypes.musicTypes.contains(type.toLowerCase());

  /// 检查给定类型是否为视频内容（电影、剧集、单集或季）
  static bool isVideoContent(String type) => ContentTypes.videoTypes.contains(type.toLowerCase());

  /// 检查给定库是否为音乐库
  static bool isMusicLibrary(dynamic lib) {
    if (lib == null) return false;
    try {
      final type = (lib as dynamic).type as String?;
      return type?.toLowerCase() == ContentTypes.artist;
    } catch (e) {
      return false;
    }
  }

  /// 从项目列表中过滤掉音乐内容
  static List<T> filterOutMusic<T>(List<T> items, String Function(T) getType) {
    return items.where((item) => !isMusicContent(getType(item))).toList();
  }

  /// 返回给定库类型的相应图标
  static IconData getLibraryIcon(String type) {
    switch (type.toLowerCase()) {
      case ContentTypes.movie:
        return Symbols.movie_rounded;
      case ContentTypes.show:
        return Symbols.tv_rounded;
      case ContentTypes.artist:
        return Symbols.music_note_rounded;
      case 'photo':
        return Symbols.photo_rounded;
      default:
        return Symbols.folder_rounded;
    }
  }
}

/// 格式化内容分级的工具函数，通过移除国家前缀实现
String formatContentRating(String? contentRating) {
  if (contentRating == null || contentRating.isEmpty) {
    return '';
  }

  // 移除常见的国家前缀，如 "gb/"、"us/"、"de/" 等。
  // 该模式匹配：后面跟着正斜杠的两个或三个小写字母
  final regex = RegExp(r'^[a-z]{2,3}/(.+)$', caseSensitive: false);
  final match = regex.firstMatch(contentRating);

  if (match != null && match.groupCount >= 1) {
    return match.group(1) ?? contentRating;
  }

  return contentRating;
}

/// PlexMetadata 的扩展，提供类型检查的便捷方法
extension PlexMetadataType on PlexMetadata {
  String get _lowerType => type.toLowerCase();

  bool get isShow => _lowerType == ContentTypes.show;
  bool get isMovie => _lowerType == ContentTypes.movie;
  bool get isSeason => _lowerType == ContentTypes.season;
  bool get isEpisode => _lowerType == ContentTypes.episode;
  bool get isArtist => _lowerType == ContentTypes.artist;
  bool get isAlbum => _lowerType == ContentTypes.album;
  bool get isTrack => _lowerType == ContentTypes.track;
  bool get isCollection => _lowerType == ContentTypes.collection;
  bool get isPlaylist => _lowerType == ContentTypes.playlist;
  bool get isClip => _lowerType == ContentTypes.clip;
  bool get isMusicContent => ContentTypes.musicTypes.contains(_lowerType);
  bool get isVideoContent => ContentTypes.videoTypes.contains(_lowerType);
}
