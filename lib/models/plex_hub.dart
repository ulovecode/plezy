import 'plex_metadata.dart';

/// 表示 Plex Hub/推荐栏目（例如：热门电影、高分惊悚片）
class PlexHub {
  final String hubKey;
  final String title;
  final String type;
  final String? hubIdentifier;
  final int size;
  final bool more;
  final List<PlexMetadata> items;

  // 多服务器支持字段
  final String? serverId; // 服务器机器标识符
  final String? serverName; // 服务器显示名称

  PlexHub({
    required this.hubKey,
    required this.title,
    required this.type,
    this.hubIdentifier,
    required this.size,
    required this.more,
    required this.items,
    this.serverId,
    this.serverName,
  });

  factory PlexHub.fromJson(Map<String, dynamic> json) {
    final metadataList = <PlexMetadata>[];

    // 用于从 JSON 列表中解析条目的辅助函数
    void parseEntries(List? entries) {
      if (entries == null) return;
      for (final item in entries) {
        try {
          metadataList.add(PlexMetadata.fromJson(item));
        } catch (e) {
          // 跳过解析失败的项目
        }
      }
    }

    // Hub 可以包含 Metadata 或 Directory 条目
    parseEntries(json['Metadata'] as List?);
    parseEntries(json['Directory'] as List?);

    return PlexHub(
      hubKey: json['key'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown',
      type: json['type'] as String? ?? 'hub',
      hubIdentifier: json['hubIdentifier'] as String?,
      size: (json['size'] as num?)?.toInt() ?? metadataList.length,
      more: json['more'] == true || json['more'] == 1,
      items: metadataList,
    );
  }
}
