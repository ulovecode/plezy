/// Plex 过滤器模型
class PlexFilter {
  /// 过滤器字段名
  final String filter;
  /// 过滤器类型（如 string, integer）
  final String filterType;
  /// 过滤器唯一键
  final String key;
  /// 过滤器显示标题
  final String title;
  /// 类型
  final String type;

  PlexFilter({
    required this.filter,
    required this.filterType,
    required this.key,
    required this.title,
    required this.type,
  });

  factory PlexFilter.fromJson(Map<String, dynamic> json) {
    return PlexFilter(
      filter: json['filter'] ?? '',
      filterType: json['filterType'] ?? 'string',
      key: json['key'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? 'filter',
    );
  }

  Map<String, dynamic> toJson() {
    return {'filter': filter, 'filterType': filterType, 'key': key, 'title': title, 'type': type};
  }
}

/// Plex 过滤器值模型
class PlexFilterValue {
  /// 值的唯一键
  final String key;
  /// 值的显示标题
  final String title;
  /// 类型
  final String? type;

  PlexFilterValue({required this.key, required this.title, this.type});

  factory PlexFilterValue.fromJson(Map<String, dynamic> json) {
    return PlexFilterValue(key: json['key'] ?? '', title: json['title'] ?? '', type: json['type']);
  }

  Map<String, dynamic> toJson() {
    return {'key': key, 'title': title, if (type != null) 'type': type};
  }
}
