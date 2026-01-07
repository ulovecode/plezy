import 'package:json_annotation/json_annotation.dart';

import 'mixins/multi_server_fields.dart';
import 'plex_role.dart';

part 'plex_metadata.g.dart';

/// 媒体类型枚举，用于类型安全的媒体类型处理
enum PlexMediaType {
  movie,
  show,
  season,
  episode,
  artist,
  album,
  track,
  collection,
  playlist,
  clip,
  photo,
  unknown;

  /// 此类型是否表示视频内容
  bool get isVideo => this == movie || this == episode || this == clip;

  /// 此类型是否属于剧集层级
  bool get isShowRelated => this == show || this == season || this == episode;

  /// 此类型是否表示音乐内容
  bool get isMusic => this == artist || this == album || this == track;

  /// 此类型是否可以直接播放
  bool get isPlayable => isVideo || this == track;
}

@JsonSerializable()
class PlexMetadata with MultiServerFields {
  final String ratingKey;
  final String key;
  final String? guid;
  final String? studio;
  final String type;
  final String title;
  final String? contentRating;
  final String? summary;
  final double? rating;
  final double? audienceRating;
  final int? year;
  final String? thumb;
  final String? art;
  final int? duration;
  final int? addedAt;
  final int? updatedAt;
  final int? lastViewedAt; // 上次观看的时间戳
  final String? grandparentTitle; // 剧集所属的剧集标题
  final String? grandparentThumb; // 剧集所属的剧集海报
  final String? grandparentArt; // 剧集所属的剧集艺术图
  final String? grandparentRatingKey; // 剧集所属的剧集评分键
  final String? parentTitle; // 剧集所属的季标题
  final String? parentThumb; // 剧集所属的季海报
  final String? parentRatingKey; // 剧集所属的季评分键
  final int? parentIndex; // 季序号
  final int? index; // 集序号
  final String? grandparentTheme; // 剧集主题曲
  final int? viewOffset; // 续播位置（毫秒）
  final int? viewCount;
  final int? leafCount; // 剧集/季中的总集数
  final int? viewedLeafCount; // 剧集/季中已观看的集数
  final int? childCount; // 收藏夹或播放列表中的项目数
  @JsonKey(name: 'Role')
  final List<PlexRole>? role; // 演职人员
  final String? audioLanguage; // 每个媒体的首选音频语言
  final String? subtitleLanguage; // 每个媒体的首选字幕语言
  final int? playlistItemID; // 播放列表项目 ID（仅适用于普通播放列表）
  final int? playQueueItemID; // 播放队列项目 ID（即使是重复项也是唯一的）
  final int? librarySectionID; // 此项目所属的库部分 ID

  // 多服务器支持字段（来自 MultiServerFields 混入）
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? serverId;
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? serverName;

  // Clear logo URL（从 Image 数组中提取，但为了离线存储而序列化）
  final String? clearLogo;

  /// 跨所有服务器的全局唯一标识符 (serverId:ratingKey)
  String get globalKey => serverId != null ? '$serverId:$ratingKey' : ratingKey;

  /// 解析后的媒体类型枚举，用于类型安全比较
  PlexMediaType get mediaType {
    return switch (type.toLowerCase()) {
      'movie' => PlexMediaType.movie,
      'show' => PlexMediaType.show,
      'season' => PlexMediaType.season,
      'episode' => PlexMediaType.episode,
      'artist' => PlexMediaType.artist,
      'album' => PlexMediaType.album,
      'track' => PlexMediaType.track,
      'collection' => PlexMediaType.collection,
      'playlist' => PlexMediaType.playlist,
      'clip' => PlexMediaType.clip,
      'photo' => PlexMediaType.photo,
      _ => PlexMediaType.unknown,
    };
  }

  PlexMetadata({
    required this.ratingKey,
    required this.key,
    this.guid,
    this.studio,
    required this.type,
    required this.title,
    this.contentRating,
    this.summary,
    this.rating,
    this.audienceRating,
    this.year,
    this.thumb,
    this.art,
    this.duration,
    this.addedAt,
    this.updatedAt,
    this.lastViewedAt,
    this.grandparentTitle,
    this.grandparentThumb,
    this.grandparentArt,
    this.grandparentRatingKey,
    this.parentTitle,
    this.parentThumb,
    this.parentRatingKey,
    this.parentIndex,
    this.index,
    this.grandparentTheme,
    this.viewOffset,
    this.viewCount,
    this.leafCount,
    this.viewedLeafCount,
    this.childCount,
    this.role,
    this.audioLanguage,
    this.subtitleLanguage,
    this.playlistItemID,
    this.playQueueItemID,
    this.librarySectionID,
    this.serverId,
    this.serverName,
    this.clearLogo,
  });

  /// 创建此元数据的一个副本，并可选地覆盖字段
  PlexMetadata copyWith({
    String? ratingKey,
    String? key,
    String? guid,
    String? studio,
    String? type,
    String? title,
    String? contentRating,
    String? summary,
    double? rating,
    double? audienceRating,
    int? year,
    String? thumb,
    String? art,
    int? duration,
    int? addedAt,
    int? updatedAt,
    int? lastViewedAt,
    String? grandparentTitle,
    String? grandparentThumb,
    String? grandparentArt,
    String? grandparentRatingKey,
    String? parentTitle,
    String? parentThumb,
    String? parentRatingKey,
    int? parentIndex,
    int? index,
    String? grandparentTheme,
    int? viewOffset,
    int? viewCount,
    int? leafCount,
    int? viewedLeafCount,
    int? childCount,
    List<PlexRole>? role,
    String? audioLanguage,
    String? subtitleLanguage,
    int? playlistItemID,
    int? playQueueItemID,
    int? librarySectionID,
    String? serverId,
    String? serverName,
    String? clearLogo,
  }) {
    return PlexMetadata(
      ratingKey: ratingKey ?? this.ratingKey,
      key: key ?? this.key,
      guid: guid ?? this.guid,
      studio: studio ?? this.studio,
      type: type ?? this.type,
      title: title ?? this.title,
      contentRating: contentRating ?? this.contentRating,
      summary: summary ?? this.summary,
      rating: rating ?? this.rating,
      audienceRating: audienceRating ?? this.audienceRating,
      year: year ?? this.year,
      thumb: thumb ?? this.thumb,
      art: art ?? this.art,
      duration: duration ?? this.duration,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
      grandparentTitle: grandparentTitle ?? this.grandparentTitle,
      grandparentThumb: grandparentThumb ?? this.grandparentThumb,
      grandparentArt: grandparentArt ?? this.grandparentArt,
      grandparentRatingKey: grandparentRatingKey ?? this.grandparentRatingKey,
      parentTitle: parentTitle ?? this.parentTitle,
      parentThumb: parentThumb ?? this.parentThumb,
      parentRatingKey: parentRatingKey ?? this.parentRatingKey,
      parentIndex: parentIndex ?? this.parentIndex,
      index: index ?? this.index,
      grandparentTheme: grandparentTheme ?? this.grandparentTheme,
      viewOffset: viewOffset ?? this.viewOffset,
      viewCount: viewCount ?? this.viewCount,
      leafCount: leafCount ?? this.leafCount,
      viewedLeafCount: viewedLeafCount ?? this.viewedLeafCount,
      childCount: childCount ?? this.childCount,
      role: role ?? this.role,
      audioLanguage: audioLanguage ?? this.audioLanguage,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      playlistItemID: playlistItemID ?? this.playlistItemID,
      playQueueItemID: playQueueItemID ?? this.playQueueItemID,
      librarySectionID: librarySectionID ?? this.librarySectionID,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      clearLogo: clearLogo ?? this.clearLogo,
    );
  }

  /// 从原始 JSON 的 Image 数组中提取 clearLogo
  static String? _extractClearLogoFromJson(Map<String, dynamic> json) {
    if (!json.containsKey('Image')) return null;

    final images = json['Image'] as List?;
    if (images == null) return null;

    for (var image in images) {
      if (image is Map && image['type'] == 'clearLogo') {
        return image['url'] as String?;
      }
    }
    return null;
  }

  /// 从带有从 Image 数组提取的 clearLogo 的 JSON 创建
  factory PlexMetadata.fromJsonWithImages(Map<String, dynamic> json) {
    // 解析前提取 clearLogo
    final clearLogoUrl = _extractClearLogoFromJson(json);
    // 将其添加到 json 中以便解析
    if (clearLogoUrl != null) {
      json['clearLogo'] = clearLogoUrl;
    }
    return PlexMetadata.fromJson(json);
  }

  /// 获取显示标题（剧集/季显示剧名，其他显示标题）
  String get displayTitle {
    final itemType = type.toLowerCase();

    // 对于剧集和季，优先使用 grandparentTitle（剧名）
    if ((itemType == 'episode' || itemType == 'season') && grandparentTitle != null) {
      return grandparentTitle!;
    }
    // 对于没有 grandparent 的季，检查这是否就是剧集（parentTitle 可能含有剧名）
    if (itemType == 'season' && parentTitle != null) {
      return parentTitle!;
    }
    return title;
  }

  /// 获取显示副标题（集/季标题）
  String? get displaySubtitle {
    final itemType = type.toLowerCase();

    if (itemType == 'episode' || itemType == 'season') {
      // 如果我们将 grandparent/parent 显示为标题，则将此项的标题显示为副标题
      if (grandparentTitle != null || (itemType == 'season' && parentTitle != null)) {
        return title;
      }
    }
    return null;
  }

  /// 获取海报（剧集/季显示剧集海报，其他显示 thumb）
  /// 如果 useSeasonPoster 为 true，则剧集将使用季海报而不是剧集总海报
  String? posterThumb({bool useSeasonPoster = false}) {
    final itemType = type.toLowerCase();

    if (itemType == 'episode') {
      // 如果启用了季海报且可用，则使用它
      if (useSeasonPoster && parentThumb != null) {
        return parentThumb!;
      }
      // 否则回退到剧集海报，然后是项目缩略图
      if (grandparentThumb != null) {
        return grandparentThumb!;
      }
    } else if (itemType == 'season' && grandparentThumb != null) {
      // 对于季，始终使用剧集海报
      return grandparentThumb!;
    }
    return thumb;
  }

  /// 判断内容是否已观看
  bool get isWatched {
    // 对于剧集/季，检查是否所有集都已观看
    if (leafCount != null && viewedLeafCount != null) {
      return viewedLeafCount! >= leafCount!;
    }

    // 对于单个项目（电影、集），检查 viewCount
    return viewCount != null && viewCount! > 0;
  }

  factory PlexMetadata.fromJson(Map<String, dynamic> json) => _$PlexMetadataFromJson(json);

  Map<String, dynamic> toJson() => _$PlexMetadataToJson(this);
}
