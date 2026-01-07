import 'package:json_annotation/json_annotation.dart';
import 'plex_metadata.dart';

part 'play_queue_response.g.dart';

/// 用于处理来自 Plex API 的 int (0/1) 和 bool 值的转换器
class BoolOrIntConverter implements JsonConverter<bool, Object> {
  const BoolOrIntConverter();

  @override
  bool fromJson(Object json) {
    if (json is bool) return json;
    if (json is int) return json != 0;
    if (json is String) return json.toLowerCase() == 'true' || json == '1';
    return false;
  }

  @override
  Object toJson(bool object) => object;
}

/// 来自 Plex 播放队列（Play Queue）API 的响应
/// 包含队列元数据和一组项目
@JsonSerializable(createToJson: false)
class PlayQueueResponse {
  final int playQueueID;
  final int? playQueueSelectedItemID;
  final int? playQueueSelectedItemOffset;
  final String? playQueueSelectedMetadataItemID;
  @BoolOrIntConverter()
  final bool playQueueShuffled;
  final String? playQueueSourceURI;
  final int? playQueueTotalCount;
  final int playQueueVersion;
  final int? size; // 此响应窗口中的项目数
  @JsonKey(name: 'Metadata')
  final List<PlexMetadata>? items;

  PlayQueueResponse({
    required this.playQueueID,
    this.playQueueSelectedItemID,
    this.playQueueSelectedItemOffset,
    this.playQueueSelectedMetadataItemID,
    required this.playQueueShuffled,
    this.playQueueSourceURI,
    required this.playQueueTotalCount,
    required this.playQueueVersion,
    this.size,
    this.items,
  });

  factory PlayQueueResponse.fromJson(Map<String, dynamic> json, {String? serverId, String? serverName}) {
    // API 返回的数据包装在 MediaContainer 中
    final container = json['MediaContainer'] as Map<String, dynamic>? ?? json;
    final response = _$PlayQueueResponseFromJson(container);

    // 为所有项目标记服务器信息
    if (response.items != null && (serverId != null || serverName != null)) {
      final taggedItems = response.items!
          .map((item) => item.copyWith(serverId: serverId, serverName: serverName))
          .toList();
      return PlayQueueResponse(
        playQueueID: response.playQueueID,
        playQueueSelectedItemID: response.playQueueSelectedItemID,
        playQueueSelectedItemOffset: response.playQueueSelectedItemOffset,
        playQueueSelectedMetadataItemID: response.playQueueSelectedMetadataItemID,
        playQueueShuffled: response.playQueueShuffled,
        playQueueSourceURI: response.playQueueSourceURI,
        playQueueTotalCount: response.playQueueTotalCount,
        playQueueVersion: response.playQueueVersion,
        size: response.size,
        items: taggedItems,
      );
    }

    return response;
  }

  /// 获取队列中当前选中的项目
  PlexMetadata? get selectedItem {
    if (items == null || playQueueSelectedItemID == null) return null;
    try {
      return items!.firstWhere((item) => item.playQueueItemID == playQueueSelectedItemID);
    } catch (e) {
      return null;
    }
  }

  /// 获取选中项目在当前窗口中的索引
  int? get selectedItemIndex {
    if (items == null || playQueueSelectedItemID == null) return null;
    return items!.indexWhere((item) => item.playQueueItemID == playQueueSelectedItemID);
  }
}
