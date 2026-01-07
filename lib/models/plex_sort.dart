/// Plex 排序选项模型
class PlexSort {
  /// 排序键名
  final String key;
  /// 降序排序键名（如果存在）
  final String? descKey;
  /// 排序选项的显示标题
  final String title;
  /// 默认排序方向（'asc' 或 'desc'）
  final String? defaultDirection;

  PlexSort({required this.key, this.descKey, required this.title, this.defaultDirection});

  factory PlexSort.fromJson(Map<String, dynamic> json) {
    return PlexSort(
      key: json['key'] as String,
      descKey: json['descKey'] as String?,
      title: json['title'] as String,
      defaultDirection: json['defaultDirection'] as String?,
    );
  }

  /// 获取带有方向的完整排序键
  /// 如果 [descending] 为 true，返回 descKey 或 key:desc
  /// 否则返回用于升序排序的 key
  String getSortKey({bool descending = false}) {
    if (!descending) {
      return key;
    }

    // 如果有 descKey 则使用它，否则在 key 后添加 :desc
    return descKey ?? '$key:desc';
  }

  /// 如果此排序的默认方向是降序，则返回 true
  bool get isDefaultDescending {
    return defaultDirection?.toLowerCase() == 'desc';
  }

  @override
  String toString() {
    return 'PlexSort(key: $key, title: $title, defaultDirection: $defaultDirection)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlexSort && other.key == key;
  }

  @override
  int get hashCode => key.hashCode;
}
