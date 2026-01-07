import 'dart:async';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'storage_service.dart';
import 'plex_client.dart';
import '../models/plex_user_profile.dart';
import '../models/plex_home.dart';
import '../models/user_switch_response.dart';
import '../utils/app_logger.dart';

class PlexAuthService {
  static const String _appName = 'Plezy';
  static const String _plexApiBase = 'https://plex.tv/api/v2';
  static const String _clientsApi = 'https://clients.plex.tv/api/v2';

  final Dio _dio;
  final String _clientIdentifier;

  PlexAuthService._(this._dio, this._clientIdentifier);

  /// 创建 PlexAuthService 实例
  static Future<PlexAuthService> create() async {
    final storage = await StorageService.getInstance();
    final dio = Dio();

    // 获取或创建客户端标识符
    String? clientIdentifier = storage.getClientIdentifier();
    if (clientIdentifier == null) {
      clientIdentifier = const Uuid().v4();
      await storage.saveClientIdentifier(clientIdentifier);
    }

    return PlexAuthService._(dio, clientIdentifier);
  }

  String get clientIdentifier => _clientIdentifier;

  /// 获取通用请求选项
  Options _getCommonOptions({String? authToken}) {
    final headers = {
      'Accept': 'application/json',
      'X-Plex-Product': _appName,
      'X-Plex-Client-Identifier': _clientIdentifier,
    };

    if (authToken != null) {
      headers['X-Plex-Token'] = authToken;
    }

    return Options(headers: headers);
  }

  /// 获取用户信息
  Future<Response> _getUser(String authToken) {
    return _dio.get('$_plexApiBase/user', options: _getCommonOptions(authToken: authToken));
  }

  /// 验证 plex.tv 令牌是否有效
  Future<bool> verifyToken(String authToken) async {
    try {
      await _getUser(authToken);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 创建用于身份验证的 PIN
  Future<Map<String, dynamic>> createPin() async {
    final response = await _dio.post('$_plexApiBase/pins?strong=true', options: _getCommonOptions());

    return response.data as Map<String, dynamic>;
  }

  /// 构建供用户访问的身份验证应用 URL
  String getAuthUrl(String pinCode) {
    final params = {'clientID': _clientIdentifier, 'code': pinCode, 'context[device][product]': _appName};

    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'https://app.plex.tv/auth#?$queryString';
  }

  /// 轮询 PIN 以检查其是否已被认领
  Future<String?> checkPin(int pinId) async {
    try {
      final response = await _dio.get('$_plexApiBase/pins/$pinId', options: _getCommonOptions());

      final data = response.data as Map<String, dynamic>;
      return data['authToken'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// 轮询 PIN 直到其被认领或超时
  Future<String?> pollPinUntilClaimed(
    int pinId, {
    Duration timeout = const Duration(minutes: 2),
    bool Function()? shouldCancel,
  }) async {
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      // 检查是否应取消轮询
      if (shouldCancel != null && shouldCancel()) {
        return null;
      }

      final token = await checkPin(pinId);
      if (token != null) {
        return token;
      }

      // 在再次轮询前等待 1 秒
      await Future.delayed(const Duration(seconds: 1));
    }

    return null; // 超时
  }

  /// 获取已验证用户的可用 Plex 服务器
  Future<List<PlexServer>> fetchServers(String authToken) async {
    final response = await _dio.get(
      '$_clientsApi/resources?includeHttps=1&includeRelay=1&includeIPv6=1',
      options: _getCommonOptions(authToken: authToken),
    );

    final List<dynamic> resources = response.data as List<dynamic>;

    // 过滤服务器资源并映射到 PlexServer 对象
    final servers = <PlexServer>[];
    final invalidServers = <Map<String, dynamic>>[];

    for (final resource in resources.where((r) => r['provides'] == 'server')) {
      try {
        final server = PlexServer.fromJson(resource as Map<String, dynamic>);
        servers.add(server);
      } catch (e) {
        // 收集无效服务器以便调试
        invalidServers.add(resource as Map<String, dynamic>);
        continue;
      }
    }

    // 如果我们有一些有效的服务器但也有一些无效的，那没关系
    // 如果没有有效的服务器但有一些无效的，则抛出带有调试信息的异常
    if (servers.isEmpty && invalidServers.isNotEmpty) {
      throw ServerParsingException(
        '未找到有效的服务器。所有 ${invalidServers.length} 个服务器的数据均异常。',
        invalidServers,
      );
    }

    return servers;
  }

  /// 获取用户信息
  Future<Map<String, dynamic>> getUserInfo(String authToken) async {
    final response = await _getUser(authToken);

    return response.data as Map<String, dynamic>;
  }

  /// 获取带有偏好设置（音频/字幕设置）的用户个人资料
  Future<PlexUserProfile> getUserProfile(String authToken) async {
    final response = await _dio.get('$_clientsApi/user', options: _getCommonOptions(authToken: authToken));

    return PlexUserProfile.fromJson(response.data as Map<String, dynamic>);
  }

  /// 获取已验证用户的家庭用户
  Future<PlexHome> getHomeUsers(String authToken) async {
    final response = await _dio.get('$_clientsApi/home/users', options: _getCommonOptions(authToken: authToken));

    return PlexHome.fromJson(response.data as Map<String, dynamic>);
  }

  /// 切换到家庭中的不同用户
  Future<UserSwitchResponse> switchToUser(String userUUID, String currentToken, {String? pin}) async {
    final queryParams = {
      'includeSubscriptions': '1', // 包含订阅信息
      'includeProviders': '1', // 包含提供商信息
      'includeSettings': '1', // 包含设置信息
      'includeSharedSettings': '1', // 包含共享设置信息
      'X-Plex-Product': _appName,
      'X-Plex-Version': '1.1.0',
      'X-Plex-Client-Identifier': _clientIdentifier,
      'X-Plex-Platform': 'Flutter',
      'X-Plex-Platform-Version': '3.8.1',
      'X-Plex-Token': currentToken,
      'X-Plex-Language': 'en',
      if (pin != null) 'pin': pin,
    };

    final queryString = queryParams.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final response = await _dio.post(
      '$_clientsApi/home/users/$userUUID/switch?$queryString',
      options: Options(headers: {'Accept': 'application/json', 'Content-Length': '0'}),
    );

    return UserSwitchResponse.fromJson(response.data as Map<String, dynamic>);
  }
}

/// 辅助类，用于在测试期间跟踪连接候选者
class _ConnectionCandidate {
  final PlexConnection connection;
  final String url;
  final bool isPlexDirectUri;
  final bool isHttps;

  _ConnectionCandidate(this.connection, this.url, this.isPlexDirectUri, this.isHttps);
}

/// 表示一个 Plex 媒体服务器 (Plex Media Server)
class PlexServer {
  final String name;
  final String clientIdentifier;
  final String accessToken;
  final List<PlexConnection> connections;
  final bool owned;
  final String? product;
  final String? platform;
  final DateTime? lastSeenAt;
  final bool presence;

  PlexServer({
    required this.name,
    required this.clientIdentifier,
    required this.accessToken,
    required this.connections,
    required this.owned,
    this.product,
    this.platform,
    this.lastSeenAt,
    this.presence = false,
  });

  factory PlexServer.fromJson(Map<String, dynamic> json) {
    // 首先验证必填字段
    if (!_isValidServerJson(json)) {
      throw FormatException(
        '无效的服务器数据：缺少必填字段 (name, clientIdentifier, accessToken, 或 connections)',
      );
    }

    final List<dynamic> connectionsJson = json['connections'] as List<dynamic>;
    final connections = <PlexConnection>[];

    // 解析连接并为 HTTPS 连接生成 HTTP 备用方案
    for (final c in connectionsJson) {
      try {
        final connection = PlexConnection.fromJson(c as Map<String, dynamic>);
        connections.add(connection);

        // 为 HTTPS 连接生成 HTTP 备用方案
        if (connection.protocol == 'https') {
          connections.add(connection.toHttpFallback());
        }
      } catch (e) {
        // 跳过无效连接，而不是使整个服务器解析失败
        continue;
      }
    }

    // 如果没有解析出有效的连接，则此服务器不可用
    if (connections.isEmpty) {
      throw FormatException('服务器没有有效的连接');
    }

    DateTime? lastSeenAt;
    if (json['lastSeenAt'] != null) {
      try {
        lastSeenAt = DateTime.parse(json['lastSeenAt'] as String);
      } catch (e) {
        lastSeenAt = null;
      }
    }

    return PlexServer(
      name: json['name'] as String, // 在上面已验证，此处安全
      clientIdentifier: json['clientIdentifier'] as String, // 在上面已验证，此处安全
      accessToken: json['accessToken'] as String, // 在上面已验证，此处安全
      connections: connections,
      owned: json['owned'] as bool? ?? false,
      product: json['product'] as String?,
      platform: json['platform'] as String?,
      lastSeenAt: lastSeenAt,
      presence: json['presence'] as bool? ?? false,
    );
  }

  /// 验证服务器 JSON 是否包含所有必填字段且类型正确
  static bool _isValidServerJson(Map<String, dynamic> json) {
    // 检查必填字符串字段
    if (json['name'] is! String || (json['name'] as String).isEmpty) {
      return false;
    }
    if (json['clientIdentifier'] is! String || (json['clientIdentifier'] as String).isEmpty) {
      return false;
    }
    if (json['accessToken'] is! String || (json['accessToken'] as String).isEmpty) {
      return false;
    }

    // 检查连接数组
    if (json['connections'] is! List || (json['connections'] as List).isEmpty) {
      return false;
    }

    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'clientIdentifier': clientIdentifier,
      'accessToken': accessToken,
      'connections': connections.map((c) => c.toJson()).toList(),
      'owned': owned,
      'product': product,
      'platform': platform,
      'lastSeenAt': lastSeenAt?.toIso8601String(),
      'presence': presence,
    };
  }

  /// 使用 presence 字段检查服务器是否在线
  bool get isOnline => presence;

  PlexConnection? _selectBest(Iterable<PlexConnection> candidates) {
    final local = candidates.where((c) => c.local && !c.relay).toList();
    if (local.isNotEmpty) return local.first;

    final remote = candidates.where((c) => !c.local && !c.relay).toList();
    if (remote.isNotEmpty) return remote.first;

    final relay = candidates.where((c) => c.relay).toList();
    if (relay.isNotEmpty) return relay.first;

    if (candidates.isNotEmpty) return candidates.first;
    return null;
  }

  /// 获取最佳连接 URL
  /// 优先级：本地 (local) > 远程 (remote) > 中继 (relay)
  PlexConnection? getBestConnection() {
    return _selectBest(connections);
  }

  /// 通过测试连接找到最佳的可运行连接
  /// 返回一个 Stream，该 Stream 逐步发出连接：
  /// 1. 第一次发出：第一个成功响应的连接
  /// 2. 第二次发出（可选）：经过延迟测试后的最佳连接
  /// 优先级：本地 > 远程 > 中继，然后是 HTTPS > HTTP，最后是最低延迟
  /// 为每个连接测试 plex.direct URI 和直接 IP
  /// HTTPS 连接首先被测试，HTTP 作为备用
  Stream<PlexConnection> findBestWorkingConnection({String? preferredUri}) async* {
    if (connections.isEmpty) {
      appLogger.w('没有可用于服务器发现的连接');
      return;
    }

    const preferredTimeout = Duration(seconds: 2);
    const raceTimeout = Duration(seconds: 4);

    final candidates = _buildPrioritizedCandidates();
    if (candidates.isEmpty) {
      appLogger.w('未生成用于服务器发现的候选连接');
      return;
    }

    final totalCandidates = candidates.length;
    appLogger.d(
      '开始服务器连接发现',
      error: {'preferred': preferredUri, 'candidateCount': totalCandidates},
    );

    _ConnectionCandidate? firstCandidate;

    // 快速路径：如果我们有缓存的可运行 URI，使用短超时进行探测
    if (preferredUri != null) {
      final cachedCandidate = _candidateForUrl(preferredUri);
      if (cachedCandidate != null) {
        appLogger.d('在运行完整竞争之前测试缓存端点', error: {'uri': preferredUri});
        final result = await PlexClient.testConnectionWithLatency(
          cachedCandidate.url,
          accessToken,
          timeout: preferredTimeout,
        );

        if (result.success) {
          appLogger.i('缓存端点测试成功，立即使用', error: {'uri': preferredUri});
          firstCandidate = cachedCandidate;
        } else {
          appLogger.w('缓存端点测试失败，回退到候选竞争', error: {'uri': preferredUri});
        }
      }
    }

    // 如果没有缓存候选者或其失败，则竞争候选者以找到第一个成功的连接
    if (firstCandidate == null) {
      final completer = Completer<_ConnectionCandidate?>();
      int completedTests = 0;

      appLogger.d('正在运行连接竞争以找到第一个工作的端点', error: {'candidateCount': totalCandidates});

      for (final candidate in candidates) {
        PlexClient.testConnectionWithLatency(candidate.url, accessToken, timeout: raceTimeout).then((result) {
          completedTests++;

          if (result.success && !completer.isCompleted) {
            completer.complete(candidate);
          }

          if (completedTests == candidates.length && !completer.isCompleted) {
            completer.complete(null);
          }
        });
      }

      firstCandidate = await completer.future;
      if (firstCandidate == null) {
        appLogger.e('竞争后未找到工作的服务器连接');
        return; // 未找到可运行的连接
      }
      appLogger.i(
        '连接竞争找到了第一个工作的端点',
        error: {'uri': firstCandidate.url, 'type': firstCandidate.connection.displayType},
      );
    }

    final firstConnection = _updateConnectionUrl(firstCandidate.connection, firstCandidate.url);
    yield firstConnection;
    appLogger.d(
      '已发出第一个工作的连接，继续在后台进行延迟测试',
      error: {'uri': firstConnection.uri},
    );

    // 第 2 阶段：继续在后台进行测试以找到最佳连接
    // 对每个候选者进行 2-3 次测试并计算平均延迟
    final candidateResults = <_ConnectionCandidate, ConnectionTestResult>{};

    await Future.wait(
      candidates.map((candidate) async {
        final result = await PlexClient.testConnectionWithAverageLatency(candidate.url, accessToken, attempts: 2);

        if (result.success) {
          candidateResults[candidate] = result;
        }
      }),
    );

    // 如果没有连接成功，则完成
    if (candidateResults.isEmpty) {
      appLogger.w('延迟扫描未发现额外工作的端点');
      return;
    }

    appLogger.d(
      '已完成服务器连接的延迟扫描',
      error: {'successfulCandidates': candidateResults.length},
    );

    // 综合考虑优先级、延迟和 URL 类型找到最佳连接
    final bestCandidate = _selectBestCandidateWithLatency(candidateResults);

    // 如果最佳连接与第一个连接不同，则发出它
    if (bestCandidate != null) {
      final upgradedCandidate = await _upgradeCandidateToHttpsIfPossible(bestCandidate) ?? bestCandidate;

      final bestConnection = _updateConnectionUrl(upgradedCandidate.connection, upgradedCandidate.url);
      if (bestConnection.uri != firstConnection.uri) {
        appLogger.i('延迟扫描选择了更好的端点', error: {'uri': bestConnection.uri});
        yield bestConnection;
      } else {
        appLogger.d('延迟扫描确认初始端点是最优的', error: {'uri': bestConnection.uri});
      }
    }
  }

  /// 将连接的 URI 更新为指定的 URL
  PlexConnection _updateConnectionUrl(PlexConnection connection, String url) {
    // 如果 URL 与原始 URI 匹配，则原样返回
    if (url == connection.uri) {
      return connection;
    }

    // 否则，创建一个以 directUrl 作为 uri 的新连接
    return PlexConnection(
      protocol: connection.protocol,
      address: connection.address,
      port: connection.port,
      uri: url,
      local: connection.local,
      relay: connection.relay,
      ipv6: connection.ipv6,
    );
  }

  _ConnectionCandidate? _candidateForUrl(String url) {
    for (final connection in connections) {
      final httpUrl = connection.httpDirectUrl;
      if (httpUrl == url) {
        return _ConnectionCandidate(connection, httpUrl, false, false);
      }

      final uri = connection.uri;
      if (uri == url) {
        final isHttps = uri.startsWith('https://');
        final parsedHost = Uri.tryParse(uri)?.host ?? '';
        final isPlexDirect = parsedHost.toLowerCase().contains('plex.direct');
        return _ConnectionCandidate(connection, uri, isPlexDirect, isHttps);
      }
    }
    return null;
  }

  List<_ConnectionCandidate> _buildPrioritizedCandidates({Set<String>? excludeUrls}) {
    final seen = <String>{};
    if (excludeUrls != null) {
      seen.addAll(excludeUrls);
    }

    final httpsLocal = <_ConnectionCandidate>[];
    final httpsRemote = <_ConnectionCandidate>[];
    final httpsRelay = <_ConnectionCandidate>[];
    final httpLocal = <_ConnectionCandidate>[];
    final httpRemote = <_ConnectionCandidate>[];
    final httpRelay = <_ConnectionCandidate>[];

    List<_ConnectionCandidate> bucketFor(PlexConnection connection, bool isHttps) {
      if (isHttps) {
        if (connection.relay) return httpsRelay;
        if (connection.local) return httpsLocal;
        return httpsRemote;
      } else {
        if (connection.relay) return httpRelay;
        if (connection.local) return httpLocal;
        return httpRemote;
      }
    }

    void addCandidate(PlexConnection connection, String url, bool isPlexDirectUri, bool isHttps) {
      if (url.isEmpty || seen.contains(url)) {
        return;
      }
      seen.add(url);
      bucketFor(connection, isHttps).add(_ConnectionCandidate(connection, url, isPlexDirectUri, isHttps));
    }

    for (final connection in connections) {
      // 首先尝试实际的连接 URI（可能是 HTTPS plex.direct）
      final isPlexDirect = connection.uri.contains('.plex.direct');
      final isHttps = connection.protocol == 'https';
      addCandidate(connection, connection.uri, isPlexDirect, isHttps);

      // 对于 HTTPS 连接，还添加 HTTP 直接 IP 作为备用
      // 这提供了向后兼容性和证书问题的备用方案
      if (isHttps) {
        addCandidate(connection, connection.httpDirectUrl, false, false);
      }
    }

    return [...httpsLocal, ...httpsRemote, ...httpsRelay, ...httpLocal, ...httpRemote, ...httpRelay];
  }

  List<String> prioritizedEndpointUrls({String? preferredFirst}) {
    final urls = <String>[];
    final exclude = <String>{};

    if (preferredFirst != null && preferredFirst.isNotEmpty) {
      urls.add(preferredFirst);
      exclude.add(preferredFirst);
    }

    final candidates = _buildPrioritizedCandidates(excludeUrls: exclude);
    urls.addAll(candidates.map((candidate) => candidate.url));
    return urls;
  }

  Future<_ConnectionCandidate?> _upgradeCandidateToHttpsIfPossible(_ConnectionCandidate candidate) async {
    final currentUrl = candidate.url;
    if (currentUrl.startsWith('https://')) {
      return null;
    }

    late final String httpsUrl;
    bool resultingIsPlexDirect = candidate.isPlexDirectUri;

    if (candidate.isPlexDirectUri) {
      if (!currentUrl.startsWith('http://')) {
        return null;
      }
      httpsUrl = currentUrl.replaceFirst('http://', 'https://');
    } else {
      // 原始 IP 端点无法提供 HTTPS 证书——首选其 plex.direct 别名。
      final plexDirectUri = candidate.connection.uri;
      if (plexDirectUri.isEmpty) {
        return null;
      }

      if (plexDirectUri.startsWith('https://')) {
        httpsUrl = plexDirectUri;
      } else if (plexDirectUri.startsWith('http://')) {
        httpsUrl = plexDirectUri.replaceFirst('http://', 'https://');
      } else {
        return null;
      }

      final upgradedHost = Uri.tryParse(httpsUrl)?.host;
      if (upgradedHost == null || !upgradedHost.toLowerCase().endsWith('.plex.direct')) {
        appLogger.d(
          '跳过原始 IP 候选者的 HTTPS 升级：没有可用的 plex.direct 别名',
          error: {'candidate': currentUrl, 'target': httpsUrl},
        );
        return null;
      }
      resultingIsPlexDirect = true;
    }

    if (httpsUrl == currentUrl) {
      return null;
    }

    appLogger.d('尝试对候选端点进行 HTTPS 升级', error: {'from': currentUrl, 'to': httpsUrl});

    final result = await PlexClient.testConnectionWithLatency(
      httpsUrl,
      accessToken,
      timeout: const Duration(seconds: 4),
    );

    if (!result.success) {
      appLogger.w('HTTPS 升级失败，保留 HTTP 候选者', error: {'url': currentUrl});
      return null;
    }

    appLogger.i('候选端点 HTTPS 升级成功', error: {'httpsUrl': httpsUrl});

    final httpsConnection = PlexConnection(
      protocol: 'https',
      address: candidate.connection.address,
      port: candidate.connection.port,
      uri: httpsUrl,
      local: candidate.connection.local,
      relay: candidate.connection.relay,
      ipv6: candidate.connection.ipv6,
    );

    return _ConnectionCandidate(httpsConnection, httpsUrl, resultingIsPlexDirect, true);
  }

  /// 尝试将连接升级为 HTTPS
  Future<PlexConnection?> upgradeConnectionToHttps(PlexConnection current) async {
    if (current.uri.startsWith('https://')) {
      return current;
    }

    final baseConnection = _findMatchingBaseConnection(current);
    if (baseConnection == null) {
      return null;
    }

    final candidate = _ConnectionCandidate(
      baseConnection,
      current.uri,
      current.uri.contains('.plex.direct'),
      current.uri.startsWith('https://'),
    );
    final upgradedCandidate = await _upgradeCandidateToHttpsIfPossible(candidate);
    if (upgradedCandidate == null) {
      return null;
    }
    return _updateConnectionUrl(upgradedCandidate.connection, upgradedCandidate.url);
  }

  /// 查找匹配的基础连接
  PlexConnection? _findMatchingBaseConnection(PlexConnection connection) {
    for (final base in connections) {
      final sameAddress = base.address == connection.address;
      final samePort = base.port == connection.port;
      final sameLocal = base.local == connection.local;
      final sameRelay = base.relay == connection.relay;
      if (sameAddress && samePort && sameLocal && sameRelay) {
        return base;
      }
    }
    return null;
  }

  /// 综合考虑优先级、延迟和 URL 类型，选择最佳候选者
  _ConnectionCandidate? _selectBestCandidateWithLatency(Map<_ConnectionCandidate, ConnectionTestResult> results) {
    // 按连接类型（本地/远程/中继）对候选者进行分组
    final localCandidates = results.entries.where((e) => e.key.connection.local && !e.key.connection.relay).toList();
    final remoteCandidates = results.entries.where((e) => !e.key.connection.local && !e.key.connection.relay).toList();
    final relayCandidates = results.entries.where((e) => e.key.connection.relay).toList();

    // 找到每个类别中最好的
    return _findLowestLatencyCandidate(localCandidates) ??
        _findLowestLatencyCandidate(remoteCandidates) ??
        _findLowestLatencyCandidate(relayCandidates);
  }

  /// 找到延迟最低的候选者，在平局时优先选择 HTTPS 和 plex.direct URI
  _ConnectionCandidate? _findLowestLatencyCandidate(
    List<MapEntry<_ConnectionCandidate, ConnectionTestResult>> entries,
  ) {
    if (entries.isEmpty) return null;

    // 首先按延迟排序，然后按协议（HTTPS > HTTP），最后按 URL 类型（优先选择 plex.direct）
    entries.sort((a, b) {
      final latencyCompare = a.value.latencyMs.compareTo(b.value.latencyMs);
      if (latencyCompare != 0) return latencyCompare;

      // 如果延迟相等，优先选择 HTTPS 而不是 HTTP
      final aIsHttps = a.key.isHttps;
      final bIsHttps = b.key.isHttps;
      if (aIsHttps && !bIsHttps) return -1;
      if (!aIsHttps && bIsHttps) return 1;

      // 如果延迟和协议相等，优先选择 plex.direct URI (isPlexDirectUri = true)
      if (a.key.isPlexDirectUri && !b.key.isPlexDirectUri) return -1;
      if (!a.key.isPlexDirectUri && b.key.isPlexDirectUri) return 1;
      return 0;
    });

    return entries.first.key;
  }
}

/// 代表与 Plex 服务器的连接
class PlexConnection {
  final String protocol;
  final String address;
  final int port;
  final String uri;
  final bool local;
  final bool relay;
  final bool ipv6;

  PlexConnection({
    required this.protocol,
    required this.address,
    required this.port,
    required this.uri,
    required this.local,
    required this.relay,
    required this.ipv6,
  });

  factory PlexConnection.fromJson(Map<String, dynamic> json) {
    // 验证必需字段
    if (!_isValidConnectionJson(json)) {
      throw FormatException('Invalid connection data: missing required fields (protocol, address, port, or uri)');
    }

    return PlexConnection(
      protocol: json['protocol'] as String, // 因为上面已经验证过，所以是安全的
      address: json['address'] as String, // 因为上面已经验证过，所以是安全的
      port: json['port'] as int, // 因为上面已经验证过，所以是安全的
      uri: json['uri'] as String, // 因为上面已经验证过，所以是安全的
      local: json['local'] as bool? ?? false,
      relay: json['relay'] as bool? ?? false,
      ipv6: json['IPv6'] as bool? ?? false,
    );
  }

  /// 验证连接 JSON 是否包含具有正确类型的所有必需字段
  static bool _isValidConnectionJson(Map<String, dynamic> json) {
    // 检查必需的字符串字段
    if (json['protocol'] is! String || (json['protocol'] as String).isEmpty) {
      return false;
    }
    if (json['address'] is! String || (json['address'] as String).isEmpty) {
      return false;
    }
    if (json['uri'] is! String || (json['uri'] as String).isEmpty) {
      return false;
    }

    // 检查必需的端口（整数）
    if (json['port'] is! int) {
      return false;
    }

    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'protocol': protocol,
      'address': address,
      'port': port,
      'uri': uri,
      'local': local,
      'relay': relay,
      'IPv6': ipv6,
    };
  }

  /// 获取由地址和端口构建的直接 URL
  /// 这会绕过 plex.direct DNS 并直接连接到 IP
  String get directUrl => '$protocol://$address:$port';

  /// 始终返回指向 IP/端口组合的 HTTP URL。
  String get httpDirectUrl {
    final needsBrackets = address.contains(':') && !address.startsWith('['); // 处理 IPv6 地址
    final safeAddress = needsBrackets ? '[$address]' : address;
    return 'http://$safeAddress:$port';
  }

  String get displayType {
    if (relay) return 'Relay'; // 中继
    if (local) return 'Local'; // 本地
    return 'Remote'; // 远程
  }

  /// 创建此 HTTPS 连接的 HTTP 备用版本
  /// 这允许在 HTTPS 不可用时（例如证书问题）测试 HTTP
  PlexConnection toHttpFallback() {
    assert(protocol == 'https', 'Can only create HTTP fallback for HTTPS connections');

    return PlexConnection(
      protocol: 'http',
      address: address,
      port: port,
      uri: uri.replaceFirst('https://', 'http://'),
      local: local,
      relay: relay,
      ipv6: ipv6,
    );
  }
}

/// 包含调试数据的服务器解析错误自定义异常
class ServerParsingException implements Exception {
  final String message;
  final List<Map<String, dynamic>> invalidServerData;

  ServerParsingException(this.message, this.invalidServerData);

  @override
  String toString() => message;
}
