class LogRedactionManager {
  // 受限集合的大小限制（超过时进行 FIFO 淘汰）
  static const int _maxTokens = 50;
  static const int _maxUrls = 20;
  static const int _maxCustomValues = 50;

  // 使用 LinkedHashSet 保持 FIFO 顺序
  static final Set<String> _tokens = <String>{};
  static final Set<String> _urls = <String>{};
  static final Set<String> _customValues = <String>{};

  static final RegExp _ipv4Pattern = RegExp(r'\b(\d{1,3})([.-])(\d{1,3})\2(\d{1,3})\2(\d{1,3})\b');
  static final RegExp _ipv4HostPattern = RegExp(r'^\d{1,3}([.-]\d{1,3}){3}$');

  // 用于单次脱敏的组合正则表达式（在集合更改时重建）
  static RegExp? _combinedPattern;

  /// 注册服务器访问令牌或 Plex.tv 令牌以进行脱敏。
  static void registerToken(String? token) {
    final normalized = _normalize(token);
    if (normalized == null) return;

    _addWithLimit(_tokens, normalized, _maxTokens);

    // 令牌经常在查询参数中以 URL 编码形式出现。
    final encoded = Uri.encodeQueryComponent(normalized);
    if (encoded != normalized) {
      _addWithLimit(_tokens, encoded, _maxTokens);
    }

    _rebuildCombinedPattern();
  }

  /// 注册当前使用的服务器/基础 URL。
  static void registerServerUrl(String? url) {
    final normalized = _normalize(url);
    if (normalized == null) return;

    final uri = Uri.tryParse(normalized);
    final host = uri?.host;
    if (host != null && host.isNotEmpty && _isIpv4Like(host)) {
      // 不要注册完整的基于 IP 的 URL；正则表达式脱敏会处理它们。
      return;
    }

    if (host == null && _isIpv4Like(normalized)) {
      return;
    }

    final strippedSlash = normalized.endsWith('/') ? normalized.substring(0, normalized.length - 1) : normalized;

    if (strippedSlash.isNotEmpty) {
      _addWithLimit(_urls, strippedSlash, _maxUrls);
      _addWithLimit(_urls, '$strippedSlash/', _maxUrls);
    }

    // 同时捕获源 (origin) 和主机级别的字符串，以覆盖大多数情况。
    if (uri != null && uri.host.isNotEmpty) {
      final origin = '${uri.scheme.isEmpty ? 'https' : uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      _addWithLimit(_urls, origin, _maxUrls);
      if (origin.endsWith('/')) {
        _addWithLimit(_urls, origin.substring(0, origin.length - 1), _maxUrls);
      }
    }

    _rebuildCombinedPattern();
  }

  /// 注册其他需要脱敏的敏感值。
  static void registerCustomValue(String? value) {
    final normalized = _normalize(value);
    if (normalized == null) return;
    _addWithLimit(_customValues, normalized, _maxCustomValues);
    _rebuildCombinedPattern();
  }

  /// 重置所有已跟踪的敏感值（例如在注销时）。
  static void clearTrackedValues() {
    _tokens.clear();
    _urls.clear();
    _customValues.clear();
    _combinedPattern = null;
  }

  /// 从提供的消息中脱敏已知的敏感值。
  static String redact(String message) {
    // 第一步：IPv4 地址（正则表达式模式）
    var redacted = message.replaceAllMapped(
      _ipv4Pattern,
      (match) => _maskIpv4(match.group(1)!, match.group(2)!, match.group(5)!),
    );

    // 第二步：单次遍历脱敏所有已跟踪的值
    if (_combinedPattern != null) {
      redacted = redacted.replaceAllMapped(_combinedPattern!, (match) {
        final value = match.group(0)!;
        if (_tokens.contains(value)) return '[REDACTED_TOKEN]';
        if (_urls.contains(value)) return _maskUrlPreview(value);
        return '[REDACTED]';
      });
    }

    return redacted;
  }

  /// 根据所有已跟踪的值重建组合正则表达式模式。
  static void _rebuildCombinedPattern() {
    final allLiterals = [
      ..._tokens.map(RegExp.escape),
      ..._urls.map(RegExp.escape),
      ..._customValues.map(RegExp.escape),
    ];

    if (allLiterals.isEmpty) {
      _combinedPattern = null;
      return;
    }

    // 按长度降序排序，以便优先匹配较长的字符串
    allLiterals.sort((a, b) => b.length.compareTo(a.length));
    _combinedPattern = RegExp(allLiterals.join('|'));
  }

  /// 将值添加到集合中，如果超过限制则进行 FIFO 淘汰。
  static void _addWithLimit(Set<String> set, String value, int maxSize) {
    if (set.contains(value)) return; // 已跟踪

    // 如果容量已满，则淘汰最旧的条目
    while (set.length >= maxSize) {
      set.remove(set.first);
    }
    set.add(value);
  }

  static String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static bool _isIpv4Like(String value) {
    return _ipv4HostPattern.hasMatch(value);
  }

  static String _maskIpv4(String first, String separator, String last) {
    return '$first$separator'
        'x$separator'
        'x$separator'
        '$last';
  }

  static String _maskUrlPreview(String url) {
    const startPreviewLength = 12;
    const endPreviewLength = 8;

    if (url.isEmpty) {
      return '[REDACTED_URL]';
    }

    if (url.length <= 4) {
      return '[REDACTED_URL]';
    }

    final startLength = url.length <= startPreviewLength ? (url.length / 2).ceil() : startPreviewLength;
    final remainingForEnd = url.length - startLength;
    final endLength = remainingForEnd <= endPreviewLength ? remainingForEnd : endPreviewLength;

    final start = url.substring(0, startLength);
    if (endLength <= 0) {
      return '$start...[REDACTED_URL]';
    }

    final end = url.substring(url.length - endLength);
    return '$start...[REDACTED_URL]...$end';
  }
}
