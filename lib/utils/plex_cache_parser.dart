/// 用于解析 Plex API 缓存响应的工具类
///
/// 在整个代码库中提供一致的 MediaContainer 数据提取。
class PlexCacheParser {
  PlexCacheParser._();

  /// 从缓存响应中提取元数据 (Metadata) 列表
  ///
  /// 如果 MediaContainer 或 Metadata 不存在，则返回 null
  static List<dynamic>? extractMetadataList(Map<String, dynamic>? cached) {
    if (cached == null) return null;
    return cached['MediaContainer']?['Metadata'] as List?;
  }

  /// 从缓存响应中提取第一个元数据项目
  ///
  /// 如果元数据不存在，则返回 null
  static Map<String, dynamic>? extractFirstMetadata(Map<String, dynamic>? cached) {
    final list = extractMetadataList(cached);
    if (list == null || list.isEmpty) return null;
    return list[0] as Map<String, dynamic>;
  }

  /// 检查缓存响应是否具有有效的元数据
  static bool hasMetadata(Map<String, dynamic>? cached) {
    final list = extractMetadataList(cached);
    return list != null && list.isNotEmpty;
  }

  /// 从缓存响应中提取目录 (Directory) 列表（用于媒体库、播放列表）
  static List<dynamic>? extractDirectoryList(Map<String, dynamic>? cached) {
    if (cached == null) return null;
    return cached['MediaContainer']?['Directory'] as List?;
  }

  /// 从缓存响应中提取 Hub 列表
  static List<dynamic>? extractHubList(Map<String, dynamic>? cached) {
    if (cached == null) return null;
    return cached['MediaContainer']?['Hub'] as List?;
  }

  /// 从第一个元数据项目中提取章节 (Chapter) 列表
  static List<dynamic>? extractChapters(Map<String, dynamic>? cached) {
    final metadata = extractFirstMetadata(cached);
    if (metadata == null) return null;
    return metadata['Chapter'] as List?;
  }

  /// 从第一个元数据项目中提取标记 (Marker) 列表
  static List<dynamic>? extractMarkers(Map<String, dynamic>? cached) {
    final metadata = extractFirstMetadata(cached);
    if (metadata == null) return null;
    return metadata['Marker'] as List?;
  }
}
