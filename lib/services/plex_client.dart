import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/plex_config.dart';
import '../models/play_queue_response.dart';
import '../models/plex_file_info.dart';
import '../models/plex_filter.dart';
import '../models/plex_hub.dart';
import '../models/plex_library.dart';
import '../models/plex_media_info.dart';
import '../models/plex_media_version.dart';
import '../models/plex_metadata.dart';
import '../utils/content_utils.dart';
import '../models/plex_playlist.dart';
import '../models/plex_sort.dart';
import '../models/plex_video_playback_data.dart';
import '../utils/endpoint_failover_interceptor.dart';
import '../utils/app_logger.dart';
import '../utils/log_redaction_manager.dart';
import '../utils/plex_cache_parser.dart';
import '../utils/plex_url_helper.dart';
import 'plex_api_cache.dart';

/// Plex 流类型的常量
class PlexStreamType {
  static const int video = 1;
  static const int audio = 2;
  static const int subtitle = 3;
}

/// 测试连接的结果，包括成功状态和延迟
class ConnectionTestResult {
  final bool success;
  final int latencyMs;

  ConnectionTestResult({required this.success, required this.latencyMs});
}

/// Plex 客户端类，负责与 Plex 媒体服务器 (PMS) 进行所有的 API 交互。
///
/// 该类集成了以下核心功能：
/// 1. **身份验证与配置**：管理服务器 URL、Token 以及基础请求头。
/// 2. **自动故障转移 (Failover)**：当主连接失败时，自动尝试备用端点（如局域网 IP 与远程 URL 切换）。
/// 3. **离线支持**：内置 API 响应缓存层 ([PlexApiCache])，支持离线模式下的元数据浏览。
/// 4. **响应解析与数据标记**：将原始 JSON 转换为强类型的模型对象，并自动标记服务器 ID。
/// 5. **连接测试**：测量连接延迟并选择最优端点。
class PlexClient {
  /// 当前客户端使用的 Plex 配置信息
  PlexConfig config;

  /// 用于发起 HTTP 请求的 Dio 实例
  late final Dio _dio;

  /// 负责管理多个备用连接端点的故障转移管理器
  final EndpointFailoverManager? _endpointManager;

  /// 当检测到更优端点并发生切换时的回调函数
  final Future<void> Function(String newBaseUrl)? _onEndpointChanged;

  /// 服务器的唯一标识符（Machine Identifier）
  /// 由此客户端创建的所有 [PlexMetadata] 都会标记此 ID。
  final String serverId;

  /// 服务器的显示名称
  final String? serverName;

  /// API 响应缓存实例，用于支持离线浏览
  final PlexApiCache _cache = PlexApiCache.instance;

  /// 是否处于离线模式（仅使用缓存数据）
  bool _offlineMode = false;

  /// 设置离线模式。开启后，所有请求将直接从本地缓存读取。
  void setOfflineMode(bool offline) {
    _offlineMode = offline;
  }

  /// 获取当前是否处于离线模式
  bool get isOfflineMode => _offlineMode;

  /// 自定义响应解码器，用于优雅地处理格式错误的 UTF-8 字符（常见于某些元数据）
  static String _lenientUtf8Decoder(List<int> responseBytes, RequestOptions options, ResponseBody responseBody) {
    return utf8.decode(responseBytes, allowMalformed: true);
  }

  PlexClient(
    this.config, {
    required this.serverId,
    this.serverName,
    List<String>? prioritizedEndpoints,
    Future<void> Function(String newBaseUrl)? onEndpointChanged,
  }) : _endpointManager = (prioritizedEndpoints != null && prioritizedEndpoints.isNotEmpty)
           ? EndpointFailoverManager(prioritizedEndpoints)
           : null,
       _onEndpointChanged = onEndpointChanged {
    // 注册敏感信息到日志脱敏管理器
    LogRedactionManager.registerServerUrl(config.baseUrl);
    LogRedactionManager.registerToken(config.token);

    _dio = Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        headers: config.headers,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 120),
        validateStatus: (status) => status != null && status < 500,
        responseType: ResponseType.json,
        contentType: 'application/json; charset=utf-8',
        responseDecoder: _lenientUtf8Decoder,
      ),
    );

    // 添加日志拦截器（仅在调试时有用）
    _dio.interceptors.add(
      LogInterceptor(requestBody: false, responseBody: false, error: true, requestHeader: false, responseHeader: false),
    );

    // 如果提供了备用端点，则添加故障转移拦截器
    if (_endpointManager != null) {
      _dio.interceptors.add(
        EndpointFailoverInterceptor(
          dio: _dio,
          endpointManager: _endpointManager,
          onEndpointSwitch: _handleEndpointSwitch,
        ),
      );
    }
  }

  /// 更新客户端使用的 Token
  void updateToken(String newToken) {
    // 同时更新 Dio 请求头和内部配置，确保一致性
    _dio.options.headers['X-Plex-Token'] = newToken;
    config = config.copyWith(token: newToken);
    LogRedactionManager.registerToken(newToken);
    appLogger.d('PlexClient token updated (headers and config)');
  }

  /// 更新端点优先级列表，并可选地立即切换到最优端点
  Future<void> updateEndpointPreferences(List<String> prioritizedEndpoints, {bool switchToFirst = false}) async {
    if (_endpointManager == null || prioritizedEndpoints.isEmpty) {
      return;
    }

    final targetBaseUrl = switchToFirst ? prioritizedEndpoints.first : config.baseUrl;
    _endpointManager.reset(prioritizedEndpoints, currentBaseUrl: targetBaseUrl);

    if (switchToFirst && targetBaseUrl != config.baseUrl) {
      await _handleEndpointSwitch(targetBaseUrl);
    }
  }

  /// 测试与服务器的连接是否通畅
  Future<bool> testConnection() async {
    try {
      final response = await _dio.get('/');
      return response.statusCode == 200 || response.statusCode == 401;
    } catch (e) {
      return false;
    }
  }

  /// 测试指定 URL 的连接状况并测量延迟
  static Future<ConnectionTestResult> testConnectionWithLatency(
    String baseUrl,
    String token, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.json,
          contentType: 'application/json; charset=utf-8',
        ),
      );

      final response = await dio.get('/', options: Options(headers: {'X-Plex-Token': token}));

      stopwatch.stop();
      final success = response.statusCode == 200 || response.statusCode == 401;

      return ConnectionTestResult(success: success, latencyMs: stopwatch.elapsedMilliseconds);
    } catch (e) {
      stopwatch.stop();
      return ConnectionTestResult(success: false, latencyMs: stopwatch.elapsedMilliseconds);
    }
  }

  /// 多次测试连接并返回平均延迟，用于更准确地评估端点质量
  static Future<ConnectionTestResult> testConnectionWithAverageLatency(
    String baseUrl,
    String token, {
    int attempts = 3,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final results = <ConnectionTestResult>[];

    for (int i = 0; i < attempts; i++) {
      final result = await testConnectionWithLatency(baseUrl, token, timeout: timeout);

      // 只要有一次尝试失败，就立即返回失败结果
      if (!result.success) {
        return ConnectionTestResult(success: false, latencyMs: result.latencyMs);
      }

      results.add(result);
    }

    // 计算所有成功尝试的平均延迟
    final avgLatency = results.fold<int>(0, (sum, result) => sum + result.latencyMs) ~/ results.length;

    return ConnectionTestResult(success: true, latencyMs: avgLatency);
  }

  // ============================================================================
  // API 响应解析助手
  // ============================================================================

  /// 从 API 响应中提取 MediaContainer 对象
  Map<String, dynamic>? _getMediaContainer(Response response) {
    if (response.data is Map && response.data.containsKey('MediaContainer')) {
      return response.data['MediaContainer'];
    }
    return null;
  }

  /// 为 [PlexMetadata] 标记当前客户端的 serverId 和 serverName
  PlexMetadata _tagMetadata(PlexMetadata metadata) => metadata.copyWith(serverId: serverId, serverName: serverName);

  /// 从 JSON 创建并标记 [PlexMetadata]
  PlexMetadata _createTaggedMetadata(Map<String, dynamic> json) => _tagMetadata(PlexMetadata.fromJson(json));

  /// 从响应中提取 [PlexMetadata] 列表
  /// 自动为所有项目标记当前客户端的 serverId 和 serverName
  List<PlexMetadata> _extractMetadataList(Response response) {
    final container = _getMediaContainer(response);
    if (container != null && container['Metadata'] != null) {
      return (container['Metadata'] as List).map((json) => _createTaggedMetadata(json)).toList();
    }
    return [];
  }

  /// 从响应中提取第一个元数据 JSON（返回原始 Map 或 null）
  Map<String, dynamic>? _getFirstMetadataJson(Response response) {
    final container = _getMediaContainer(response);
    if (container != null && container['Metadata'] != null && (container['Metadata'] as List).isNotEmpty) {
      return container['Metadata'][0] as Map<String, dynamic>;
    }
    return null;
  }

  /// 通用的 Directory 列表提取与转换助手
  List<T> _extractDirectoryList<T>(Response response, T Function(Map<String, dynamic>) fromJson) {
    final container = _getMediaContainer(response);
    if (container != null && container['Directory'] != null) {
      return (container['Directory'] as List).map((json) => fromJson(json as Map<String, dynamic>)).toList();
    }
    return [];
  }

  /// 从响应中提取 [PlexLibrary] 列表并自动标记服务器信息
  List<PlexLibrary> _extractLibraryList(Response response) {
    final container = _getMediaContainer(response);
    if (container != null && container['Directory'] != null) {
      return (container['Directory'] as List)
          .map(
            (json) =>
                PlexLibrary.fromJson(json as Map<String, dynamic>).copyWith(serverId: serverId, serverName: serverName),
          )
          .toList();
    }
    return [];
  }

  /// 从响应中提取 [PlexPlaylist] 列表并自动标记服务器信息
  List<PlexPlaylist> _extractPlaylistList(Response response) {
    final container = _getMediaContainer(response);
    if (container != null && container['Metadata'] != null) {
      return (container['Metadata'] as List)
          .map(
            (json) => PlexPlaylist.fromJson(
              json as Map<String, dynamic>,
            ).copyWith(serverId: serverId, serverName: serverName),
          )
          .toList();
    }
    return [];
  }

  // ============================================================================
  // API 方法
  // ============================================================================

  /// 获取服务器标识信息
  Future<Map<String, dynamic>> getServerIdentity() async {
    final response = await _dio.get('/identity');
    return response.data;
  }

  /// 获取媒体库列表
  /// 返回自动标记了 serverId 和 serverName 的媒体库
  Future<List<PlexLibrary>> getLibraries() async {
    final response = await _dio.get('/library/sections');
    return _extractLibraryList(response);
  }

  /// 根据媒体库 ID 获取其内容
  Future<List<PlexMetadata>> getLibraryContent(
    String sectionId, {
    int? start,
    int? size,
    Map<String, String>? filters,
    CancelToken? cancelToken,
  }) async {
    final queryParams = <String, dynamic>{};
    if (start != null) queryParams['X-Plex-Container-Start'] = start;
    if (size != null) queryParams['X-Plex-Container-Size'] = size;

    // 添加筛选参数
    if (filters != null) {
      queryParams.addAll(filters);
    }

    final response = await _dio.get(
      '/library/sections/$sectionId/all',
      queryParameters: queryParams,
      cancelToken: cancelToken,
    );

    return _extractMetadataList(response);
  }

  /// 从缓存响应中解析 [PlexMetadata] 列表
  List<PlexMetadata> _parseMetadataListFromCachedResponse(Map<String, dynamic> cached) {
    final metadataList = PlexCacheParser.extractMetadataList(cached);
    if (metadataList != null) {
      return metadataList.map((json) => _createTaggedMetadata(json)).toList();
    }
    return [];
  }

  /// 获取服务器的机器标识符 (Machine Identifier)
  Future<String?> getMachineIdentifier() async {
    try {
      final response = await _dio.get('/');
      final container = _getMediaContainer(response);
      if (container == null) return null;
      return container['machineIdentifier'] as String?;
    } catch (e) {
      appLogger.e('Failed to get machine identifier', error: e);
      return null;
    }
  }

  /// 构建用于添加到播放列表的元数据 URI
  /// 返回格式：server://{machineId}/com.plexapp.plugins.library/library/metadata/{ratingKey}
  Future<String> buildMetadataUri(String ratingKey) async {
    // 优先从配置中使用缓存的 machineIdentifier
    final machineId = config.machineIdentifier ?? await getMachineIdentifier();
    if (machineId == null) {
      throw Exception('Could not get server machine identifier');
    }
    return 'server://$machineId/com.plexapp.plugins.library/library/metadata/$ratingKey';
  }

  /// 获取元数据，包含图片（clearLogo）和 OnDeck（在播）信息
  /// 离线时使用缓存，或作为网络错误的备选
  /// 注意：OnDeck 数据在离线模式下不适用
  Future<Map<String, dynamic>> getMetadataWithImagesAndOnDeck(String ratingKey) async {
    // 缓存键始终为基础端点（不含查询参数）
    final cacheKey = '/library/metadata/$ratingKey';

    // OnDeck 需要特殊处理 - 不能简单使用 _fetchWithCacheFallback，
    // 因为 OnDeck 仅在网络响应中可用，缓存中通常不存储这部分动态数据。
    return await _fetchWithCacheFallback<Map<String, dynamic>>(
          cacheKey: cacheKey,
          networkCall: () => _dio.get(
            '/library/metadata/$ratingKey',
            queryParameters: {'includeChapters': 1, 'includeMarkers': 1, 'includeOnDeck': 1},
          ),
          parseCache: (cachedData) {
            final metadata = _parseMetadataWithImagesFromCachedResponse(cachedData);
            return {'metadata': metadata, 'onDeckEpisode': null};
          },
          parseResponse: (response) {
            PlexMetadata? metadata;
            PlexMetadata? onDeckEpisode;

            final metadataJson = _getFirstMetadataJson(response);

            if (metadataJson != null) {
              metadata = _tagMetadata(PlexMetadata.fromJsonWithImages(metadataJson));

              // 检查 Metadata 中是否嵌套了 OnDeck 信息
              if (metadataJson.containsKey('OnDeck') && metadataJson['OnDeck'] != null) {
                final onDeckData = metadataJson['OnDeck'];

                // OnDeck 可以是包含 'Metadata' 键的 Map，也可以是直接的元数据
                if (onDeckData is Map && onDeckData.containsKey('Metadata')) {
                  final onDeckMetadata = onDeckData['Metadata'];
                  if (onDeckMetadata != null) {
                    onDeckEpisode = _createTaggedMetadata(onDeckMetadata);
                  }
                }
              }
            }

            return {'metadata': metadata, 'onDeckEpisode': onDeckEpisode};
          },
        ) ??
        {'metadata': null, 'onDeckEpisode': null};
  }

  /// 获取元数据，包含图片（clearLogo）
  /// 离线时使用缓存，或作为网络错误的备选
  Future<PlexMetadata?> getMetadataWithImages(String ratingKey) async {
    final cacheKey = '/library/metadata/$ratingKey';

    return _fetchWithCacheFallback<PlexMetadata>(
      cacheKey: cacheKey,
      networkCall: () =>
          _dio.get('/library/metadata/$ratingKey', queryParameters: {'includeChapters': 1, 'includeMarkers': 1}),
      parseCache: (cachedData) => _parseMetadataWithImagesFromCachedResponse(cachedData),
      parseResponse: (response) {
        final metadataJson = _getFirstMetadataJson(response);
        return metadataJson != null ? _tagMetadata(PlexMetadata.fromJsonWithImages(metadataJson)) : null;
      },
    );
  }

  /// 从缓存响应中解析带图片的 [PlexMetadata]
  PlexMetadata? _parseMetadataWithImagesFromCachedResponse(Map<String, dynamic> cached) {
    final firstMetadata = PlexCacheParser.extractFirstMetadata(cached);
    if (firstMetadata != null) {
      return _tagMetadata(PlexMetadata.fromJsonWithImages(firstMetadata));
    }
    return null;
  }

  /// 带有缓存支持的元数据获取，用于播放逻辑
  ///
  /// 返回原始响应数据 (Map) 或 null。
  Future<Map<String, dynamic>?> _fetchMetadataWithCache(String ratingKey, {Map<String, dynamic>? queryParams}) async {
    final cacheKey = '/library/metadata/$ratingKey';

    // 离线模式：仅使用缓存
    if (_offlineMode) {
      return await _cache.get(serverId, cacheKey);
    }

    // 在线：优先尝试网络
    try {
      final response = await _dio.get('/library/metadata/$ratingKey', queryParameters: queryParams);

      // 将响应缓存到基础端点
      if (response.data != null) {
        await _cache.put(serverId, cacheKey, response.data);
      }

      return response.data;
    } catch (e) {
      // 网络失败 - 尝试缓存作为备选
      appLogger.w('Network request failed for metadata, trying cache', error: e);
      return await _cache.get(serverId, cacheKey);
    }
  }

  /// 通用的“网络优先，缓存备选”助手方法
  ///
  /// 实现了客户端通用的数据获取模式：
  /// 1. 如果开启了离线模式，仅返回缓存数据。
  /// 2. 否则，优先发起网络请求。
  /// 3. 如果请求成功且 cacheResponse 为 true，则缓存该响应。
  /// 4. 如果请求失败，回退到本地缓存。
  /// 5. 如果缓存也没有，则重新抛出网络异常。
  Future<T?> _fetchWithCacheFallback<T>({
    required String cacheKey,
    required Future<Response> Function() networkCall,
    required T? Function(dynamic cachedData) parseCache,
    required T? Function(Response response) parseResponse,
    bool cacheResponse = true,
  }) async {
    if (_offlineMode) {
      final cached = await _cache.get(serverId, cacheKey);
      if (cached != null) return parseCache(cached);
      return null;
    }
    try {
      final response = await networkCall();
      if (cacheResponse && response.data != null) {
        await _cache.put(serverId, cacheKey, response.data);
      }
      return parseResponse(response);
    } catch (e) {
      appLogger.w('Network request failed for $cacheKey, trying cache', error: e);
      final cached = await _cache.get(serverId, cacheKey);
      if (cached != null) return parseCache(cached);
      rethrow;
    }
  }

  /// 获取响应数据中的第一个元数据 JSON
  Map<String, dynamic>? _getFirstMetadataJsonFromData(Map<String, dynamic>? data) =>
      PlexCacheParser.extractFirstMetadata(data);

  /// 包装返回布尔状态的 API 调用
  Future<bool> _wrapBoolApiCall(Future<Response> Function() apiCall, String errorMessage) async {
    try {
      final response = await apiCall();
      return response.statusCode == 200;
    } catch (e) {
      appLogger.e(errorMessage, error: e);
      return false;
    }
  }

  /// 包装返回列表的 API 调用，出错时返回空列表
  Future<List<T>> _wrapListApiCall<T>(
    Future<Response> Function() apiCall,
    List<T> Function(Response response) parseResponse,
    String errorMessage,
  ) async {
    try {
      final response = await apiCall();
      return parseResponse(response);
    } catch (e) {
      appLogger.e(errorMessage, error: e);
      return [];
    }
  }

  /// 从流列表中解析音频和字幕轨道
  ({List<PlexAudioTrack> audio, List<PlexSubtitleTrack> subtitles}) _parseStreams(List<dynamic>? streams) {
    final audioTracks = <PlexAudioTrack>[];
    final subtitleTracks = <PlexSubtitleTrack>[];

    if (streams == null) return (audio: audioTracks, subtitles: subtitleTracks);

    for (var stream in streams) {
      final streamType = stream['streamType'] as int?;

      if (streamType == PlexStreamType.audio) {
        audioTracks.add(
          PlexAudioTrack(
            id: stream['id'] as int,
            index: stream['index'] as int?,
            codec: stream['codec'] as String?,
            language: stream['language'] as String?,
            languageCode: stream['languageCode'] as String?,
            title: stream['title'] as String?,
            displayTitle: stream['displayTitle'] as String?,
            channels: stream['channels'] as int?,
            selected: stream['selected'] == 1 || stream['selected'] == true,
          ),
        );
      } else if (streamType == PlexStreamType.subtitle) {
        subtitleTracks.add(
          PlexSubtitleTrack(
            id: stream['id'] as int,
            index: stream['index'] as int?,
            codec: stream['codec'] as String?,
            language: stream['language'] as String?,
            languageCode: stream['languageCode'] as String?,
            title: stream['title'] as String?,
            displayTitle: stream['displayTitle'] as String?,
            selected: stream['selected'] == 1 || stream['selected'] == true,
            forced: stream['forced'] == 1,
            key: stream['key'] as String?,
          ),
        );
      }
    }

    return (audio: audioTracks, subtitles: subtitleTracks);
  }

  /// 从元数据 JSON 中解析章节信息
  List<PlexChapter> _parseChapters(Map<String, dynamic>? metadataJson) {
    if (metadataJson == null || metadataJson['Chapter'] == null) {
      return [];
    }

    final chapterList = metadataJson['Chapter'] as List<dynamic>;
    return chapterList.map((chapter) {
      return PlexChapter(
        id: chapter['id'] as int,
        index: chapter['index'] as int?,
        startTimeOffset: chapter['startTimeOffset'] as int?,
        endTimeOffset: chapter['endTimeOffset'] as int?,
        title: chapter['tag'] as String? ?? chapter['title'] as String?,
        thumb: chapter['thumb'] as String?,
      );
    }).toList();
  }

  /// 设置媒体的语言偏好（音频和字幕）
  /// 对于电视剧，建议使用 grandparentRatingKey 来为整个系列设置偏好
  /// 对于电影，使用其 ratingKey
  Future<bool> setMetadataPreferences(String ratingKey, {String? audioLanguage, String? subtitleLanguage}) async {
    final queryParams = <String, dynamic>{};
    if (audioLanguage != null) {
      queryParams['audioLanguage'] = audioLanguage;
    }
    if (subtitleLanguage != null) {
      queryParams['subtitleLanguage'] = subtitleLanguage;
    }

    // 如果没有偏好需要设置，直接返回
    if (queryParams.isEmpty) {
      return true;
    }

    return _wrapBoolApiCall(
      () => _dio.put('/library/metadata/$ratingKey/prefs', queryParameters: queryParams),
      'Failed to set metadata preferences',
    );
  }

  /// 为播放选择特定的音频和字幕流
  /// 这会更新媒体元数据中哪些流被标记为“已选择”
  Future<bool> selectStreams(int partId, {int? audioStreamID, int? subtitleStreamID, bool allParts = true}) async {
    final queryParams = <String, dynamic>{};
    if (audioStreamID != null) {
      queryParams['audioStreamID'] = audioStreamID;
    }
    if (subtitleStreamID != null) {
      queryParams['subtitleStreamID'] = subtitleStreamID;
    }
    if (allParts) {
      // 如果没有流需要选择，直接返回
      if (queryParams.isEmpty) {
        return true;
      }

      // 对 /library/parts/{partId} 发起 PUT 请求
      return _wrapBoolApiCall(
        () => _dio.put('/library/parts/$partId', queryParameters: queryParams),
        'Failed to select streams',
      );
    }
    return true;
  }

  /// 在所有媒体库中进行搜索（使用 hub 搜索端点）
  /// 仅返回电影和剧集，过滤掉季和单集
  Future<List<PlexMetadata>> search(String query, {int limit = 10}) async {
    final response = await _dio.get(
      '/hubs/search',
      queryParameters: {'query': query, 'limit': limit, 'includeCollections': 1},
    );

    final results = <PlexMetadata>[];

    final container = _getMediaContainer(response);
    if (container != null) {
      if (container['Hub'] != null) {
        // 每个 Hub 包含特定类型的结果（电影、剧集等）
        for (final hub in container['Hub'] as List) {
          final hubType = hub['type'] as String?;

          // 仅包含电影和剧集 Hub
          if (hubType != 'movie' && hubType != 'show') {
            continue;
          }

          // Hub 可以包含 Metadata（电影）或 Directory（剧集）
          if (hub['Metadata'] != null) {
            for (final json in hub['Metadata'] as List) {
              try {
                results.add(_createTaggedMetadata(json));
              } catch (e) {
                // 跳过解析失败的项目
                appLogger.w('Failed to parse search result', error: e);
                appLogger.d('Problematic JSON: $json');
              }
            }
          }
          if (hub['Directory'] != null) {
            for (final json in hub['Directory'] as List) {
              try {
                results.add(_createTaggedMetadata(json));
              } catch (e) {
                // 跳过解析失败的项目
                appLogger.w('Failed to parse search result', error: e);
                appLogger.d('Problematic JSON: $json');
              }
            }
          }
        }
      }
    }

    return results;
  }

  /// 获取最近添加的媒体（仅限视频内容）
  Future<List<PlexMetadata>> getRecentlyAdded({int limit = 50}) async {
    final response = await _dio.get(
      '/library/recentlyAdded',
      queryParameters: {'X-Plex-Container-Size': limit, 'includeGuids': 1},
    );
    final allItems = _extractMetadataList(response);

    // 过滤掉音乐内容（艺术家、专辑、音轨）
    return allItems.where((item) => !item.isMusicContent).toList();
  }

  /// 获取 On Deck 项目（继续观看，仅限视频内容）
  Future<List<PlexMetadata>> getOnDeck() async {
    final response = await _dio.get('/library/onDeck');
    final container = _getMediaContainer(response);
    if (container != null && container['Metadata'] != null) {
      final allItems = (container['Metadata'] as List)
          .map((json) => _tagMetadata(PlexMetadata.fromJsonWithImages(json)))
          .toList();

      // 过滤掉音乐内容
      return allItems.where((item) => !item.isMusicContent).toList();
    }
    return [];
  }

  /// 获取特定媒体库的 On Deck 项目
  Future<List<PlexMetadata>> getOnDeckForLibrary(String sectionId) async {
    final allOnDeck = await getOnDeck();

    // 仅保留属于指定媒体库的项目
    return allOnDeck.where((item) {
      return item.librarySectionID == int.tryParse(sectionId);
    }).toList();
  }

  /// 获取元数据的子项（例如剧集的季，季的单集）
  /// 离线时使用缓存，或作为网络错误的备选
  Future<List<PlexMetadata>> getChildren(String ratingKey) async {
    final endpoint = '/library/metadata/$ratingKey/children';

    return await _fetchWithCacheFallback<List<PlexMetadata>>(
          cacheKey: endpoint,
          networkCall: () => _dio.get(endpoint),
          parseCache: (cachedData) => _parseMetadataListFromCachedResponse(cachedData),
          parseResponse: (response) => _extractMetadataList(response),
        ) ??
        [];
  }

  /// 获取某部剧集的所有未观看剧集
  Future<List<PlexMetadata>> getAllUnwatchedEpisodes(String showRatingKey) async {
    final allEpisodes = <PlexMetadata>[];

    // 获取该剧集的所有季
    final seasons = await getChildren(showRatingKey);

    // 遍历每一季获取剧集
    for (final season in seasons) {
      if (season.isSeason) {
        final episodes = await getChildren(season.ratingKey);

        // 筛选未观看的单集
        final unwatchedEpisodes = episodes.where((ep) => ep.isEpisode && (ep.viewCount ?? 0) == 0).toList();

        allEpisodes.addAll(unwatchedEpisodes);
      }
    }

    return allEpisodes;
  }

  /// 获取某一季中所有未观看的剧集
  Future<List<PlexMetadata>> getUnwatchedEpisodesInSeason(String seasonRatingKey) async {
    final episodes = await getChildren(seasonRatingKey);

    // 筛选未观看的单集
    return episodes.where((ep) => ep.isEpisode && (ep.viewCount ?? 0) == 0).toList();
  }

  /// 获取缩略图 URL
  String getThumbnailUrl(String? thumbPath) {
    if (thumbPath == null || thumbPath.isEmpty) return '';

    // 如果路径以 / 开头，移除它
    final path = thumbPath.startsWith('/') ? thumbPath.substring(1) : thumbPath;

    return '${config.baseUrl}/$path'.withPlexToken(config.token);
  }

  /// 获取视频的直接播放 URL
  /// [mediaIndex] 指定使用哪个媒体版本（默认为 0 - 第一个版本）
  Future<String?> getVideoUrl(String ratingKey, {int mediaIndex = 0}) async {
    final data = await _fetchMetadataWithCache(ratingKey);
    final metadataJson = _getFirstMetadataJsonFromData(data);

    if (metadataJson != null && metadataJson['Media'] != null && (metadataJson['Media'] as List).isNotEmpty) {
      final mediaList = metadataJson['Media'] as List;

      // 确保请求的索引有效
      if (mediaIndex < 0 || mediaIndex >= mediaList.length) {
        mediaIndex = 0;
      }

      final media = mediaList[mediaIndex];
      if (media['Part'] != null && (media['Part'] as List).isNotEmpty) {
        final part = media['Part'][0];
        final partKey = part['key'] as String?;

        if (partKey != null) {
          // 返回直连播放 URL
          return '${config.baseUrl}$partKey'.withPlexToken(config.token);
        }
      }
    }

    return null;
  }

  /// 获取媒体项目的章节信息
  Future<List<PlexChapter>> getChapters(String ratingKey) async {
    final response = await _dio.get('/library/metadata/$ratingKey', queryParameters: {'includeChapters': 1});

    final metadataJson = _getFirstMetadataJson(response);
    if (metadataJson != null && metadataJson['Chapter'] != null) {
      final chapterList = metadataJson['Chapter'] as List<dynamic>;
      return chapterList.map((chapter) {
        return PlexChapter(
          id: chapter['id'] as int,
          index: chapter['index'] as int?,
          startTimeOffset: chapter['startTimeOffset'] as int?,
          endTimeOffset: chapter['endTimeOffset'] as int?,
          title: chapter['tag'] as String?,
          thumb: chapter['thumb'] as String?,
        );
      }).toList();
    }

    return [];
  }

  /// 获取媒体项目的标记信息（如片头、片尾标记）
  Future<List<PlexMarker>> getMarkers(String ratingKey) async {
    final response = await _dio.get('/library/metadata/$ratingKey', queryParameters: {'includeMarkers': 1});

    final metadataJson = _getFirstMetadataJson(response);

    if (metadataJson != null && metadataJson['Marker'] != null) {
      final markerList = metadataJson['Marker'] as List;
      return markerList.map((marker) {
        return PlexMarker(
          id: marker['id'] as int,
          type: marker['type'] as String,
          startTimeOffset: marker['startTimeOffset'] as int,
          endTimeOffset: marker['endTimeOffset'] as int,
        );
      }).toList();
    }

    return [];
  }

  /// 从缓存或网络获取播放额外信息（章节和标记）
  Future<PlaybackExtras> getPlaybackExtras(String ratingKey) async {
    final cacheKey = '/library/metadata/$ratingKey';

    // 离线模式：仅从缓存返回
    if (_offlineMode) {
      final cached = await _cache.get(serverId, cacheKey);
      if (cached != null) {
        return _parsePlaybackExtrasFromCachedResponse(cached);
      }
      return PlaybackExtras(chapters: [], markers: []);
    }

    // 在线模式：先检查缓存（可能之前已经获取过包含章节/标记的元数据）
    final cached = await _cache.get(serverId, cacheKey);
    if (cached != null) {
      return _parsePlaybackExtrasFromCachedResponse(cached);
    }

    // 缓存未命中 - 获取并缓存
    try {
      final response = await _dio.get(
        '/library/metadata/$ratingKey',
        queryParameters: {'includeChapters': 1, 'includeMarkers': 1},
      );

      // 缓存到基础端点
      if (response.data != null) {
        await _cache.put(serverId, cacheKey, response.data);
      }

      return _parsePlaybackExtrasFromResponse(response);
    } catch (e) {
      appLogger.w('Network request failed for playback extras', error: e);
      return PlaybackExtras(chapters: [], markers: []);
    }
  }

  /// 从 API 响应中解析 [PlaybackExtras]
  PlaybackExtras _parsePlaybackExtrasFromResponse(Response response) {
    final metadataJson = _getFirstMetadataJson(response);
    return _parsePlaybackExtrasFromMetadataJson(metadataJson);
  }

  /// 从缓存响应中解析 [PlaybackExtras]
  PlaybackExtras _parsePlaybackExtrasFromCachedResponse(Map<String, dynamic> cached) {
    final metadataJson = PlexCacheParser.extractFirstMetadata(cached);
    return _parsePlaybackExtrasFromMetadataJson(metadataJson);
  }

  /// 从元数据 JSON 中解析 [PlaybackExtras]
  PlaybackExtras _parsePlaybackExtrasFromMetadataJson(Map<String, dynamic>? metadataJson) {
    final chapters = <PlexChapter>[];
    final markers = <PlexMarker>[];

    if (metadataJson != null) {
      // 解析章节
      if (metadataJson['Chapter'] != null) {
        final chapterList = metadataJson['Chapter'] as List<dynamic>;
        for (var chapter in chapterList) {
          chapters.add(
            PlexChapter(
              id: chapter['id'] as int,
              index: chapter['index'] as int?,
              startTimeOffset: chapter['startTimeOffset'] as int?,
              endTimeOffset: chapter['endTimeOffset'] as int?,
              title: chapter['tag'] as String?,
              thumb: chapter['thumb'] as String?,
            ),
          );
        }
      }

      // 解析标记
      if (metadataJson['Marker'] != null) {
        final markerList = metadataJson['Marker'] as List;
        for (var marker in markerList) {
          markers.add(
            PlexMarker(
              id: marker['id'] as int,
              type: marker['type'] as String,
              startTimeOffset: marker['startTimeOffset'] as int,
              endTimeOffset: marker['endTimeOffset'] as int,
            ),
          );
        }
      }
    }

    return PlaybackExtras(chapters: chapters, markers: markers);
  }

  /// 获取详细的媒体信息，包含章节和轨道
  /// [mediaIndex] 指定使用哪个媒体版本（默认为 0）
  Future<PlexMediaInfo?> getMediaInfo(String ratingKey, {int mediaIndex = 0}) async {
    final data = await _fetchMetadataWithCache(ratingKey);
    final metadataJson = _getFirstMetadataJsonFromData(data);

    if (metadataJson != null && metadataJson['Media'] != null && (metadataJson['Media'] as List).isNotEmpty) {
      final mediaList = metadataJson['Media'] as List;

      // 确保请求的索引有效
      if (mediaIndex < 0 || mediaIndex >= mediaList.length) {
        mediaIndex = 0;
      }

      final media = mediaList[mediaIndex];
      if (media['Part'] != null && (media['Part'] as List).isNotEmpty) {
        final part = media['Part'][0];
        final partKey = part['key'] as String?;

        if (partKey != null) {
          // 使用助手解析轨道
          final streams = _parseStreams(part['Stream'] as List<dynamic>?);
          // 使用助手解析章节
          final chapters = _parseChapters(metadataJson);

          return PlexMediaInfo(
            videoUrl: '${config.baseUrl}$partKey'.withPlexToken(config.token),
            audioTracks: streams.audio,
            subtitleTracks: streams.subtitles,
            chapters: chapters,
          );
        }
      }
    }

    return null;
  }

  /// 获取媒体项目的所有可用版本（例如不同分辨率或格式）
  Future<List<PlexMediaVersion>> getMediaVersions(String ratingKey) async {
    final data = await _fetchMetadataWithCache(ratingKey);
    final metadataJson = _getFirstMetadataJsonFromData(data);

    if (metadataJson != null && metadataJson['Media'] != null && (metadataJson['Media'] as List).isNotEmpty) {
      final mediaList = metadataJson['Media'] as List;
      return mediaList.map((media) => PlexMediaVersion.fromJson(media as Map<String, dynamic>)).toList();
    }

    return [];
  }

  /// 在一次 API 调用中获取完整的视频播放数据（URL、媒体信息和版本列表）
  /// 该方法结合了 getVideoUrl()、getMediaInfo() 和 getMediaVersions() 的功能，
  /// 以减少视频播放初始化时的冗余 API 调用。
  Future<PlexVideoPlaybackData> getVideoPlaybackData(String ratingKey, {int mediaIndex = 0}) async {
    final data = await _fetchMetadataWithCache(ratingKey);
    final metadataJson = _getFirstMetadataJsonFromData(data);

    String? videoUrl;
    PlexMediaInfo? mediaInfo;
    List<PlexMediaVersion> availableVersions = [];

    if (metadataJson != null && metadataJson['Media'] != null && (metadataJson['Media'] as List).isNotEmpty) {
      final mediaList = metadataJson['Media'] as List;

      // 首先解析所有可用的媒体版本
      availableVersions = mediaList.map((media) => PlexMediaVersion.fromJson(media as Map<String, dynamic>)).toList();

      // 确保请求的索引有效
      if (mediaIndex < 0 || mediaIndex >= mediaList.length) {
        mediaIndex = 0;
      }

      final media = mediaList[mediaIndex];
      if (media['Part'] != null && (media['Part'] as List).isNotEmpty) {
        final part = media['Part'][0];
        final partKey = part['key'] as String?;

        if (partKey != null) {
          // 获取视频 URL
          videoUrl = '${config.baseUrl}$partKey'.withPlexToken(config.token);

          // 使用助手解析轨道
          final streams = _parseStreams(part['Stream'] as List<dynamic>?);
          // 使用助手解析章节
          final chapters = _parseChapters(metadataJson);

          // 创建媒体信息对象
          mediaInfo = PlexMediaInfo(
            videoUrl: videoUrl,
            audioTracks: streams.audio,
            subtitleTracks: streams.subtitles,
            chapters: chapters,
            partId: part['id'] as int?,
          );
        }
      }
    }

    return PlexVideoPlaybackData(videoUrl: videoUrl, mediaInfo: mediaInfo, availableVersions: availableVersions);
  }

  /// 获取媒体项目的文件详细信息
  Future<PlexFileInfo?> getFileInfo(String ratingKey) async {
    try {
      final data = await _fetchMetadataWithCache(ratingKey);
      final metadataJson = _getFirstMetadataJsonFromData(data);

      if (metadataJson != null && metadataJson['Media'] != null && (metadataJson['Media'] as List).isNotEmpty) {
        final media = metadataJson['Media'][0];
        final part = media['Part'] != null && (media['Part'] as List).isNotEmpty ? media['Part'][0] : null;

        // 提取视频流详情
        final streams = part?['Stream'] as List<dynamic>? ?? [];
        Map<String, dynamic>? videoStream;
        Map<String, dynamic>? audioStream;

        for (var stream in streams) {
          final streamType = stream['streamType'] as int?;
          if (streamType == PlexStreamType.video && videoStream == null) {
            videoStream = stream;
          } else if (streamType == PlexStreamType.audio && audioStream == null) {
            audioStream = stream;
          }
        }

        return PlexFileInfo(
          // 媒体层级属性
          container: media['container'] as String?,
          videoCodec: media['videoCodec'] as String?,
          videoResolution: media['videoResolution'] as String?,
          videoFrameRate: media['videoFrameRate'] as String?,
          videoProfile: media['videoProfile'] as String?,
          width: media['width'] as int?,
          height: media['height'] as int?,
          aspectRatio: (media['aspectRatio'] as num?)?.toDouble(),
          bitrate: media['bitrate'] as int?,
          duration: media['duration'] as int?,
          audioCodec: media['audioCodec'] as String?,
          audioProfile: media['audioProfile'] as String?,
          audioChannels: media['audioChannels'] as int?,
          optimizedForStreaming: media['optimizedForStreaming'] as bool?,
          has64bitOffsets: media['has64bitOffsets'] as bool?,
          // 文件层级属性 (Part)
          filePath: part?['file'] as String?,
          fileSize: part?['size'] as int?,
          // 视频流详情
          colorSpace: videoStream?['colorSpace'] as String?,
          colorRange: videoStream?['colorRange'] as String?,
          colorPrimaries: videoStream?['colorPrimaries'] as String?,
          colorTrc: videoStream?['colorTrc'] as String?,
          chromaSubsampling: videoStream?['chromaSubsampling'] as String?,
          frameRate: (videoStream?['frameRate'] as num?)?.toDouble(),
          bitDepth: videoStream?['bitDepth'] as int?,
          // 音频流详情
          audioChannelLayout: audioStream?['audioChannelLayout'] as String?,
        );
      }

      return null;
    } catch (e) {
      appLogger.e('Failed to get file info: $e');
      return null;
    }
  }

  /// 将媒体标记为已观看
  Future<void> markAsWatched(String ratingKey) async {
    await _dio.get('/:/scrobble', queryParameters: {'key': ratingKey, 'identifier': 'com.plexapp.plugins.library'});
  }

  /// 将媒体标记为未观看
  Future<void> markAsUnwatched(String ratingKey) async {
    await _dio.get('/:/unscrobble', queryParameters: {'key': ratingKey, 'identifier': 'com.plexapp.plugins.library'});
  }

  /// 更新播放进度
  Future<void> updateProgress(
    String ratingKey, {
    required int time,
    required String state, // 'playing', 'paused', 'stopped', 'buffering'
    int? duration,
  }) async {
    await _dio.post(
      '/:/timeline',
      queryParameters: {
        'ratingKey': ratingKey,
        'key': '/library/metadata/$ratingKey',
        'time': time,
        'state': state,
        if (duration != null) 'duration': duration,
      },
    );
  }

  /// 从“继续观看”列表中移除项目，而不影响观看状态或进度
  Future<void> removeFromOnDeck(String ratingKey) async {
    await _dio.put('/actions/removeFromContinueWatching', queryParameters: {'ratingKey': ratingKey});
  }

  /// 获取服务器偏好设置
  Future<Map<String, dynamic>> getServerPreferences() async {
    final response = await _dio.get('/:/prefs');
    return response.data;
  }

  /// 获取当前正在播放的会话
  Future<List<dynamic>> getSessions() async {
    final response = await _dio.get('/status/sessions');
    final container = _getMediaContainer(response);
    if (container != null && container['Metadata'] != null) {
      return container['Metadata'] as List;
    }
    return [];
  }

  /// 获取媒体库节可用的筛选器
  Future<List<PlexFilter>> getLibraryFilters(String sectionId) async {
    final response = await _dio.get('/library/sections/$sectionId/filters');
    return _extractDirectoryList(response, PlexFilter.fromJson);
  }

  /// 获取筛选器的具体值（例如：流派列表、年份列表等）
  Future<List<PlexFilterValue>> getFilterValues(String filterKey) async {
    final response = await _dio.get(filterKey);
    return _extractDirectoryList(response, PlexFilterValue.fromJson);
  }

  /// 获取媒体库节可用的排序选项
  Future<List<PlexSort>> getLibrarySorts(String sectionId, {String? libraryType}) async {
    try {
      // 使用专门的 sorts 端点
      final response = await _dio.get('/library/sections/$sectionId/sorts');

      // 根据 API 规范解析 Directory 数组
      final sorts = _extractDirectoryList(response, PlexSort.fromJson);

      if (sorts.isNotEmpty) {
        return sorts;
      }

      // 备选方案：如果 API 未提供，则返回通用的排序选项
      return _getFallbackSorts(libraryType);
    } catch (e) {
      appLogger.e('Failed to get library sorts: $e');
      // 发生错误时返回备选排序选项
      return _getFallbackSorts(libraryType);
    }
  }

  /// 根据媒体库类型构建备选排序选项。
  ///
  /// 如果 [libraryType] 为 null，则返回不包含剧集特定选项的通用排序。
  List<PlexSort> _getFallbackSorts(String? libraryType) {
    final fallbackSorts = <PlexSort>[
      PlexSort(key: 'titleSort', title: 'Title', defaultDirection: 'asc'),
      PlexSort(key: 'addedAt', descKey: 'addedAt:desc', title: 'Date Added', defaultDirection: 'desc'),
    ];

    // 仅为电视剧媒体库添加“最近集播出日期”
    if (libraryType?.toLowerCase() == 'show') {
      fallbackSorts.add(
        PlexSort(
          key: 'episode.originallyAvailableAt',
          descKey: 'episode.originallyAvailableAt:desc',
          title: 'Latest Episode Air Date',
          defaultDirection: 'desc',
        ),
      );
    }

    fallbackSorts.addAll([
      PlexSort(
        key: 'originallyAvailableAt',
        descKey: 'originallyAvailableAt:desc',
        title: 'Release Date',
        defaultDirection: 'desc',
      ),
      PlexSort(key: 'rating', descKey: 'rating:desc', title: 'Rating', defaultDirection: 'desc'),
    ]);

    return fallbackSorts;
  }

  /// 获取媒体库推荐中心（特定媒体库的推荐内容）
  /// 返回“热门电影”“流派顶部”等推荐中心列表。
  Future<List<PlexHub>> getLibraryHubs(String sectionId, {int limit = 10}) async {
    try {
      final response = await _dio.get(
        '/hubs/sections/$sectionId',
        queryParameters: {'count': limit, 'includeGuids': 1},
      );

      final container = _getMediaContainer(response);
      if (container != null && container['Hub'] != null) {
        final hubs = <PlexHub>[];
        for (final hubJson in container['Hub'] as List) {
          try {
            final hub = PlexHub.fromJson(hubJson);
            // 仅包含有内容的视频类推荐中心
            if (hub.items.isNotEmpty) {
              // 过滤掉非视频内容类型，并标记服务器信息
              final videoItems = hub.items
                  .where((item) {
                    return item.isMovie || item.isShow;
                  })
                  .map((item) => item.copyWith(serverId: serverId, serverName: serverName))
                  .toList();

              if (videoItems.isNotEmpty) {
                hubs.add(
                  PlexHub(
                    hubKey: hub.hubKey,
                    title: hub.title,
                    type: hub.type,
                    hubIdentifier: hub.hubIdentifier,
                    size: hub.size,
                    more: hub.more,
                    items: videoItems,
                    serverId: serverId,
                    serverName: serverName,
                  ),
                );
              }
            }
          } catch (e) {
            appLogger.w('Failed to parse hub', error: e);
          }
        }
        return hubs;
      }
    } catch (e) {
      appLogger.e('Failed to get library hubs: $e');
    }
    return [];
  }

  /// 通过推荐中心 Key 获取完整内容
  /// 返回推荐中心中完整的元数据项列表
  Future<List<PlexMetadata>> getHubContent(String hubKey) async {
    return _wrapListApiCall<PlexMetadata>(() => _dio.get(hubKey), (response) {
      final allItems = _extractMetadataList(response);
      // 过滤掉非视频内容类型
      return allItems.where((item) {
        return item.isMovie || item.isShow;
      }).toList();
    }, 'Failed to get hub content');
  }

  /// 通过播放列表 ID 获取播放列表内容
  /// 返回播放列表中的元数据项列表
  Future<List<PlexMetadata>> getPlaylist(String playlistId) async {
    return _wrapListApiCall<PlexMetadata>(
      () => _dio.get('/playlists/$playlistId/items'),
      _extractMetadataList,
      'Failed to get playlist',
    );
  }

  /// 获取所有播放列表
  /// 默认按 playlistType=video 过滤
  /// 设置 smart 为 true/false 以过滤智能播放列表，或设为 null 以获取全部
  Future<List<PlexPlaylist>> getPlaylists({String playlistType = 'video', bool? smart}) async {
    final queryParams = <String, dynamic>{'playlistType': playlistType};
    if (smart != null) {
      queryParams['smart'] = smart ? '1' : '0';
    }

    return _wrapListApiCall<PlexPlaylist>(
      () => _dio.get('/playlists', queryParameters: queryParams),
      _extractPlaylistList,
      'Failed to get playlists',
    );
  }

  /// 通过播放列表 ID 获取播放列表元数据
  /// 返回播放列表详情（而非列表项）
  Future<PlexPlaylist?> getPlaylistMetadata(String playlistId) async {
    try {
      final response = await _dio.get('/playlists/$playlistId');
      final container = _getMediaContainer(response);

      if (container == null || container['Metadata'] == null) {
        return null;
      }

      final List<dynamic> metadata = container['Metadata'] as List;

      if (metadata.isEmpty) {
        return null;
      }

      return PlexPlaylist.fromJson(metadata.first as Map<String, dynamic>);
    } catch (e) {
      appLogger.e('Failed to get playlist metadata: $e');
      return null;
    }
  }

  /// 创建新播放列表
  /// [title] - 播放列表名称
  /// [uri] - 可选的逗号分隔的项目 URI 列表（例如 "server://uuid/com.plexapp.plugins.library/library/metadata/1234"）
  /// [playQueueId] - 可选的用于创建播放列表的播放队列 ID
  Future<PlexPlaylist?> createPlaylist({required String title, String? uri, int? playQueueId}) async {
    try {
      final queryParams = <String, dynamic>{'type': 'video', 'title': title, 'smart': '0'};

      if (uri != null) {
        queryParams['uri'] = uri;
      }
      if (playQueueId != null) {
        queryParams['playQueueID'] = playQueueId.toString();
      }

      final response = await _dio.post('/playlists', queryParameters: queryParams);
      final container = _getMediaContainer(response);

      if (container == null || container['Metadata'] == null) {
        return null;
      }

      final List<dynamic> metadata = container['Metadata'] as List;

      if (metadata.isEmpty) {
        return null;
      }

      return PlexPlaylist.fromJson(metadata.first as Map<String, dynamic>);
    } catch (e) {
      appLogger.e('Failed to create playlist: $e');
      return null;
    }
  }

  /// 删除播放列表
  Future<bool> deletePlaylist(String playlistId) async {
    return _wrapBoolApiCall(() => _dio.delete('/playlists/$playlistId'), 'Failed to delete playlist');
  }

  /// 向播放列表添加项目
  /// [playlistId] - 目标播放列表 ID
  /// [uri] - 要添加项目的逗号分隔 URI 列表
  Future<bool> addToPlaylist({required String playlistId, required String uri}) async {
    appLogger.d(
      'Adding to playlist $playlistId with URI: ${uri.substring(0, uri.length > 100 ? 100 : uri.length)}${uri.length > 100 ? "..." : ""}',
    );
    final result = await _wrapBoolApiCall(
      () => _dio.put('/playlists/$playlistId/items', queryParameters: {'uri': uri}),
      'Failed to add to playlist',
    );
    if (result) {
      appLogger.d('Add to playlist response status: 200');
    }
    return result;
  }

  /// 从播放列表移除项目
  /// [playlistId] - 目标播放列表 ID
  /// [playlistItemId] - 要移除的播放列表项 ID（来自项目的 playlistItemID 字段）
  Future<bool> removeFromPlaylist({required String playlistId, required String playlistItemId}) async {
    return _wrapBoolApiCall(
      () => _dio.delete('/playlists/$playlistId/items/$playlistItemId'),
      'Failed to remove from playlist',
    );
  }

  /// 移动播放列表项到新位置
  /// 仅适用于非智能播放列表
  /// [playlistId] - 播放列表评分键
  /// [playlistItemId] - 要移动的播放列表项 ID
  /// [afterPlaylistItemId] - 将项目移动到此播放列表项 ID 之后（0 = 移至顶部）
  Future<bool> movePlaylistItem({
    required String playlistId,
    required int playlistItemId,
    required int afterPlaylistItemId,
  }) async {
    appLogger.d('Moving playlist item $playlistItemId after $afterPlaylistItemId in playlist $playlistId');
    final result = await _wrapBoolApiCall(
      () => _dio.put(
        '/playlists/$playlistId/items/$playlistItemId/move',
        queryParameters: {'after': afterPlaylistItemId},
      ),
      'Failed to move playlist item',
    );
    if (result) {
      appLogger.d('Successfully moved playlist item');
    }
    return result;
  }

  /// 清空播放列表中的所有项目
  Future<bool> clearPlaylist(String playlistId) async {
    return _wrapBoolApiCall(() => _dio.delete('/playlists/$playlistId/items'), 'Failed to clear playlist');
  }

  /// 更新播放列表元数据（例如标题、摘要）
  /// 使用与其他项目相同的元数据编辑机制
  Future<bool> updatePlaylist({required String playlistId, String? title, String? summary}) async {
    final queryParams = <String, dynamic>{'type': 'playlist', 'id': playlistId};

    if (title != null) {
      queryParams['title.value'] = title;
      queryParams['title.locked'] = '1';
    }
    if (summary != null) {
      queryParams['summary.value'] = summary;
      queryParams['summary.locked'] = '1';
    }

    return _wrapBoolApiCall(
      () => _dio.put('/library/metadata/$playlistId', queryParameters: queryParams),
      'Failed to update playlist',
    );
  }

  // ============================================================================
  // 收藏集方法 (Collection Methods)
  // ============================================================================

  /// 获取媒体库节的所有收藏集
  /// 返回收藏集作为 PlexMetadata 对象，type="collection"
  Future<List<PlexMetadata>> getLibraryCollections(String sectionId) async {
    return _wrapListApiCall<PlexMetadata>(
      () => _dio.get('/library/sections/$sectionId/collections', queryParameters: {'includeGuids': 1}),
      (response) {
        final allItems = _extractMetadataList(response);
        // 收藏集的 type 应该为 "collection"
        return allItems.where((item) {
          return item.isCollection;
        }).toList();
      },
      'Failed to get library collections',
    );
  }

  /// 获取收藏集中的项目
  /// 返回收藏集中的元数据项列表
  Future<List<PlexMetadata>> getCollectionItems(String collectionId) async {
    return _wrapListApiCall<PlexMetadata>(
      () => _dio.get('/library/collections/$collectionId/children'),
      _extractMetadataList,
      'Failed to get collection items',
    );
  }

  /// 删除收藏集
  /// 从服务器删除媒体库收藏集
  Future<bool> deleteCollection(String sectionId, String collectionId) async {
    appLogger.d('Deleting collection: sectionId=$sectionId, collectionId=$collectionId');
    final result = await _wrapBoolApiCall(
      () => _dio.delete('/library/collections/$collectionId'),
      'Failed to delete collection',
    );
    if (result) {
      appLogger.d('Delete collection response: 200');
    }
    return result;
  }

  /// 创建新收藏集
  /// 创建新收藏集并可选地向其添加项目
  /// 返回创建的收藏集 ID，如果失败则返回 null
  Future<String?> createCollection({
    required String sectionId,
    required String title,
    required String uri,
    int? type,
  }) async {
    try {
      appLogger.d('Creating collection: sectionId=$sectionId, title=$title, type=$type');
      final response = await _dio.post(
        '/library/collections',
        queryParameters: {
          if (type != null) 'type': type,
          'title': title,
          'smart': 0,
          'sectionId': sectionId,
          'uri': uri,
        },
      );
      appLogger.d('Create collection response: ${response.statusCode}');

      // 从响应中提取收藏集 ID
      // 响应应包含创建的收藏集元数据
      final container = _getMediaContainer(response);
      if (container != null) {
        final metadata = container['Metadata'];
        if (metadata != null && (metadata as List).isNotEmpty) {
          final collectionId = metadata[0]['ratingKey']?.toString();
          appLogger.d('Created collection with ID: $collectionId');
          return collectionId;
        }
      }

      return null;
    } catch (e) {
      appLogger.e('Failed to create collection', error: e);
      return null;
    }
  }

  /// 向现有收藏集添加项目
  /// 向现有收藏集添加一个或多个项目（通过 URI 指定）
  Future<bool> addToCollection({required String collectionId, required String uri}) async {
    appLogger.d('Adding items to collection: collectionId=$collectionId');
    final result = await _wrapBoolApiCall(
      () => _dio.put('/library/collections/$collectionId/items', queryParameters: {'uri': uri}),
      'Failed to add items to collection',
    );
    if (result) {
      appLogger.d('Add to collection response: 200');
    }
    return result;
  }

  /// 从收藏集中移除项目
  /// 从现有收藏集中移除单个项目
  Future<bool> removeFromCollection({required String collectionId, required String itemId}) async {
    appLogger.d('Removing item from collection: collectionId=$collectionId, itemId=$itemId');
    final result = await _wrapBoolApiCall(
      () => _dio.delete('/library/collections/$collectionId/items/$itemId'),
      'Failed to remove item from collection',
    );
    if (result) {
      appLogger.d('Remove from collection response: 200');
    }
    return result;
  }

  // ============================================================================
  // 播放队列方法 (Play Queue Methods)
  // ============================================================================

  /// 创建新播放队列
  /// 必须指定 uri 或 playlistID 之一
  Future<PlayQueueResponse?> createPlayQueue({
    String? uri,
    int? playlistID,
    required String type,
    String? key,
    int shuffle = 0,
    int repeat = 0,
    int continuous = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'type': type,
        'shuffle': shuffle,
        'repeat': repeat,
        'continuous': continuous,
      };

      if (uri != null) {
        queryParams['uri'] = uri;
      }
      if (playlistID != null) {
        queryParams['playlistID'] = playlistID;
      }
      if (key != null) {
        queryParams['key'] = key;
      }

      final response = await _dio.post('/playQueues', queryParameters: queryParams);

      return PlayQueueResponse.fromJson(response.data, serverId: serverId, serverName: serverName);
    } catch (e) {
      appLogger.e('Failed to create play queue', error: e);
      return null;
    }
  }

  /// 获取播放队列，支持可选的分页/窗口请求
  /// 可以请求特定项目周围的一窗口项目
  Future<PlayQueueResponse?> getPlayQueue(
    int playQueueId, {
    String? center,
    int window = 50,
    int includeBefore = 1,
    int includeAfter = 1,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'window': window,
        'includeBefore': includeBefore,
        'includeAfter': includeAfter,
      };

      if (center != null) {
        queryParams['center'] = center;
      }

      final response = await _dio.get('/playQueues/$playQueueId', queryParameters: queryParams);

      return PlayQueueResponse.fromJson(response.data, serverId: serverId, serverName: serverName);
    } catch (e) {
      appLogger.e('Failed to get play queue: $e');
      return null;
    }
  }

  /// 打乱播放队列
  /// 保持当前选定的项目不变
  Future<PlayQueueResponse?> shufflePlayQueue(int playQueueId) async {
    try {
      final response = await _dio.put('/playQueues/$playQueueId/shuffle');
      return PlayQueueResponse.fromJson(response.data);
    } catch (e) {
      appLogger.e('Failed to shuffle play queue: $e');
      return null;
    }
  }

  /// 清空播放队列中的所有项目
  Future<bool> clearPlayQueue(int playQueueId) async {
    return _wrapBoolApiCall(() => _dio.delete('/playQueues/$playQueueId/items'), 'Failed to clear play queue');
  }

  /// 为电视剧创建播放队列（所有剧集）
  ///
  /// 这是一个便捷方法，通过剧集的 URI 创建播放队列。
  /// 非常适合按顺序或随机播放整个系列。
  ///
  /// 参数：
  /// - [showRatingKey]: 剧集的 ratingKey
  /// - [shuffle]: 是否打乱剧集（0 = 关闭，1 = 开启）
  /// - [startingEpisodeKey]: 可选的起始剧集 ratingKey
  ///
  /// 返回包含该剧集所有分集的 PlayQueueResponse
  Future<PlayQueueResponse?> createShowPlayQueue({
    required String showRatingKey,
    int shuffle = 0,
    String? startingEpisodeKey,
  }) async {
    try {
      // 获取机器标识符以构建 URI
      final machineId = config.machineIdentifier ?? await getMachineIdentifier();
      if (machineId == null) {
        throw Exception('Could not get server machine identifier');
      }

      // 构建剧集分集的 URI
      final uri = 'server://$machineId/com.plexapp.plugins.library/library/metadata/$showRatingKey/children';

      // 创建播放队列，并可选指定起始剧集
      return await createPlayQueue(
        uri: uri,
        type: 'video',
        shuffle: shuffle,
        key: startingEpisodeKey != null ? '/library/metadata/$startingEpisodeKey' : null,
      );
    } catch (e) {
      appLogger.e('Failed to create show play queue', error: e);
      return null;
    }
  }

  /// 从响应中提取元数据 (Metadata) 和目录 (Directory) 项
  /// 文件夹可以作为其中任一类型返回
  /// 自动为所有项目标记此客户端的 serverId 和 serverName
  List<PlexMetadata> _extractMetadataAndDirectories(Response response) {
    final List<PlexMetadata> items = [];
    final container = _getMediaContainer(response);

    if (container != null) {
      // 提取 Metadata 项 - 首先尝试完整解析
      if (container['Metadata'] != null) {
        for (final json in container['Metadata'] as List) {
          try {
            // 首先尝试使用完整的 PlexMetadata.fromJson 解析
            items.add(_createTaggedMetadata(json));
          } catch (e) {
            // 如果完整解析失败，使用最小化安全解析
            appLogger.d('Using minimal parsing for metadata item: $e');
            try {
              items.add(
                PlexMetadata(
                  ratingKey: json['key'] ?? json['ratingKey'] ?? '',
                  key: json['key'] ?? '',
                  type: json['type'] ?? 'folder',
                  title: json['title'] ?? 'Untitled',
                  thumb: json['thumb'],
                  art: json['art'],
                  year: json['year'],
                  serverId: serverId,
                  serverName: serverName,
                ),
              );
            } catch (e2) {
              appLogger.e('Failed to parse metadata item: $e2');
            }
          }
        }
      }

      // 提取 Directory 项（文件夹）
      if (container['Directory'] != null) {
        for (final json in container['Directory'] as List) {
          try {
            // 首先尝试作为 PlexMetadata 解析
            items.add(_createTaggedMetadata(json));
          } catch (e) {
            // 如果失败，使用最小化的文件夹表示
            try {
              items.add(
                PlexMetadata(
                  ratingKey: json['key'] ?? json['ratingKey'] ?? '',
                  key: json['key'] ?? '',
                  type: json['type'] ?? 'folder',
                  title: json['title'] ?? 'Untitled',
                  thumb: json['thumb'],
                  art: json['art'],
                  serverId: serverId,
                  serverName: serverName,
                ),
              );
            } catch (e2) {
              appLogger.e('Failed to parse directory item: $e2');
            }
          }
        }
      }
    }

    return items;
  }

  /// 获取媒体库节的根文件夹
  /// 返回用于文件系统浏览的顶层文件夹结构
  Future<List<PlexMetadata>> getLibraryFolders(String sectionId) async {
    try {
      final response = await _dio.get(
        '/library/sections/$sectionId/folder',
        queryParameters: {'includeCollections': 0},
      );
      return _extractMetadataAndDirectories(response);
    } catch (e) {
      appLogger.e('Failed to get library folders: $e');
      return [];
    }
  }

  /// 获取特定文件夹的子项
  /// 返回给定文件夹内的文件和子文件夹
  Future<List<PlexMetadata>> getFolderChildren(String folderKey) async {
    try {
      final response = await _dio.get(folderKey);
      return _extractMetadataAndDirectories(response);
    } catch (e) {
      appLogger.e('Failed to get folder children: $e');
      return [];
    }
  }

  /// 获取媒体库特定的播放列表
  /// 通过检查播放列表是否包含指定媒体库的项目来过滤播放列表
  /// 这是一个客户端过滤器，因为 API 不支持按 sectionId 过滤播放列表
  Future<List<PlexPlaylist>> getLibraryPlaylists({required String sectionId, String playlistType = 'video'}) async {
    // 目前返回所有视频播放列表
    // 未来增强：通过检查播放列表项的媒体库进行过滤
    return getPlaylists(playlistType: playlistType);
  }

  // ============================================================================
  // 媒体库管理方法 (Library Management Methods)
  // ============================================================================

  /// 扫描/刷新媒体库节以检测新文件
  Future<void> scanLibrary(String sectionId) async {
    await _dio.get('/library/sections/$sectionId/refresh');
  }

  /// 刷新媒体库节的元数据
  Future<void> refreshLibraryMetadata(String sectionId) async {
    await _dio.get('/library/sections/$sectionId/refresh?force=1');
  }

  /// 清空媒体库节的回收站
  Future<void> emptyLibraryTrash(String sectionId) async {
    await _dio.put('/library/sections/$sectionId/emptyTrash');
  }

  /// 分析媒体库节
  Future<void> analyzeLibrary(String sectionId) async {
    await _dio.get('/library/sections/$sectionId/analyze');
  }

  // ============================================================================
  // 媒体库统计方法 (Library Statistics Methods)
  // ============================================================================

  /// 高效获取媒体库节的项目总数。
  /// 使用 X-Plex-Container-Size: 1 以最小的数据传输量获取 totalSize。
  Future<int> getLibraryTotalCount(String sectionId) async {
    try {
      final response = await _dio.get(
        '/library/sections/$sectionId/all',
        queryParameters: {'X-Plex-Container-Start': 0, 'X-Plex-Container-Size': 1},
      );
      final container = _getMediaContainer(response);
      // 首先尝试获取 totalSize，如果不可用则退而求其次使用 size
      return container?['totalSize'] as int? ?? container?['size'] as int? ?? 0;
    } catch (e) {
      appLogger.e('Failed to get library total count: $e');
      return 0;
    }
  }

  /// 获取电视剧媒体库的总分集数。
  /// 使用 allLeaves 端点统计所有剧集。
  Future<int> getLibraryEpisodeCount(String sectionId) async {
    try {
      final response = await _dio.get(
        '/library/sections/$sectionId/allLeaves',
        queryParameters: {'X-Plex-Container-Start': 0, 'X-Plex-Container-Size': 1},
      );
      final container = _getMediaContainer(response);
      return container?['totalSize'] as int? ?? container?['size'] as int? ?? 0;
    } catch (e) {
      appLogger.e('Failed to get library episode count: $e');
      return 0;
    }
  }

  /// 获取指定时间段内的观看历史数量。
  /// [since] - 可选的 DateTime，用于过滤此日期之后的历史记录。
  /// 返回已观看项目的总数。
  Future<int> getWatchHistoryCount({DateTime? since}) async {
    try {
      final queryParams = <String, dynamic>{'X-Plex-Container-Start': 0, 'X-Plex-Container-Size': 1};
      if (since != null) {
        final epochSeconds = since.millisecondsSinceEpoch ~/ 1000;
        queryParams['viewedAt>'] = epochSeconds;
      }
      final response = await _dio.get('/status/sessions/history/all', queryParameters: queryParams);
      final container = _getMediaContainer(response);
      return container?['totalSize'] as int? ?? container?['size'] as int? ?? 0;
    } catch (e) {
      appLogger.e('Failed to get watch history count: $e');
      return 0;
    }
  }

  /// 处理端点切换
  Future<void> _handleEndpointSwitch(String newBaseUrl) async {
    if (config.baseUrl == newBaseUrl) {
      return;
    }

    appLogger.i('Applying Plex endpoint switch', error: newBaseUrl);
    _dio.options.baseUrl = newBaseUrl;
    config = config.copyWith(baseUrl: newBaseUrl);
    LogRedactionManager.registerServerUrl(newBaseUrl);

    if (_onEndpointChanged != null) {
      await _onEndpointChanged(newBaseUrl);
    }
  }
}
