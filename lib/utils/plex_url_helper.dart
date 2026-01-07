/// 为 URL 追加 Plex 身份验证令牌的扩展方法。
extension PlexUrlExtension on String {
  /// 向此 URL 字符串追加 Plex 身份验证令牌。
  ///
  /// 根据 URL 是否已包含查询参数，自动确定使用 '?' 还是 '&' 作为分隔符。
  ///
  /// 如果 [token] 为 null 或为空，则返回原 URL。
  ///
  /// 示例：
  /// ```dart
  /// final url = '/library/metadata/123'.withPlexToken('abc123');
  /// // 结果：'/library/metadata/123?X-Plex-Token=abc123'
  ///
  /// final urlWithParams = '/library/metadata/123?type=1'.withPlexToken('abc123');
  /// // 结果：'/library/metadata/123?type=1&X-Plex-Token=abc123'
  /// ```
  String withPlexToken(String? token) {
    if (token == null || token.isEmpty) return this;
    final separator = contains('?') ? '&' : '?';
    return '$this${separator}X-Plex-Token=$token';
  }

  /// 向此路径字符串追加基础 URL 和 Plex 身份验证令牌。
  ///
  /// 如果 [token] 为 null 或为空，则返回不带令牌参数的 URL。
  ///
  /// 示例：
  /// ```dart
  /// final fullUrl = '/library/metadata/123'.toPlexUrl('http://server:32400', 'abc123');
  /// // 结果：'http://server:32400/library/metadata/123?X-Plex-Token=abc123'
  /// ```
  String toPlexUrl(String baseUrl, String? token) {
    return '$baseUrl$this'.withPlexToken(token);
  }
}
