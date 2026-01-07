import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:dio/dio.dart';

import '../models/plex_metadata.dart';
import '../utils/app_logger.dart';
import 'plex_client.dart';
import 'settings_service.dart';

/// 缓存的 Litterbox URL 及其过期时间
class _CachedUrl {
  final String url;
  final DateTime expiresAt;

  _CachedUrl(this.url, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// 管理 Discord Rich Presence (RPC) 集成的服务。
///
/// 仅限桌面端 (Windows, macOS, Linux)。在视频播放时显示“正在观看”活动。
/// 能够优雅地处理 Discord 未运行的情况。
class DiscordRPCService {
  static const String _applicationId = '1453773470306402439';
  static const String _litterboxUrl = 'https://litterbox.catbox.moe/resources/internals/api.php';

  /// Plex 缩略图路径到 Litterbox URL 的缓存，过期时间为 1 小时
  static final Map<String, _CachedUrl> _litterboxCache = {};

  static DiscordRPCService? _instance;
  static DiscordRPCService get instance {
    _instance ??= DiscordRPCService._();
    return _instance!;
  }

  DiscordRPC? _rpc;
  bool _isConnected = false;
  bool _isEnabled = false;
  bool _isInitialized = false;
  PlexMetadata? _currentMetadata;
  PlexClient? _currentClient;
  String? _cachedThumbnailUrl;
  DateTime? _playbackStartTime;
  Duration? _mediaDuration;
  Duration? _currentPosition;
  Timer? _reconnectTimer;
  DateTime? _lastPresenceUpdate;
  StreamSubscription<void>? _readySubscription;
  StreamSubscription<void>? _disconnectedSubscription;
  StreamSubscription<dynamic>? _errorSubscription;

  DiscordRPCService._();

  /// 检查当前平台是否支持 Discord RPC
  static bool get isAvailable {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return false;
    }
    return DiscordRPC.isAvailable;
  }

  /// 初始化服务。在应用启动时调用一次 (main.dart)。
  Future<void> initialize() async {
    if (!isAvailable) {
      appLogger.d('当前平台不支持 Discord RPC');
      return;
    }

    if (_isInitialized) return;
    _isInitialized = true;

    final settings = await SettingsService.getInstance();
    _isEnabled = settings.getEnableDiscordRPC();

    if (_isEnabled) {
      await _connect();
    }
  }

  /// 启用或禁用 Discord RPC
  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;

    _isEnabled = enabled;

    if (enabled) {
      await _connect();
      // 如果当前正在播放，恢复状态显示
      if (_currentMetadata != null) {
        await _updatePresence();
      }
    } else {
      await _disconnect();
    }
  }

  /// 开始显示媒体播放状态
  Future<void> startPlayback(PlexMetadata metadata, PlexClient client) async {
    _currentMetadata = metadata;
    _currentClient = client;
    _playbackStartTime = DateTime.now();
    _mediaDuration = metadata.duration != null
        ? Duration(milliseconds: metadata.duration!)
        : null;
    _currentPosition = Duration.zero;
    _cachedThumbnailUrl = null;

    if (_isEnabled && _isConnected) {
      // 在后台上传缩略图，不阻塞播放
      _uploadThumbnailAndUpdatePresence();
    }
  }

  /// 更新当前播放位置 (用于进度条)
  void updatePosition(Duration position) {
    final previousPosition = _currentPosition;
    _currentPosition = position;

    // 如果位置发生显著跳变 (检测到跳转/拖动)，更新状态显示
    if (_isEnabled && _isConnected && _playbackStartTime != null && previousPosition != null) {
      final drift = (position - previousPosition).abs();
      // 如果位置变化超过 5 秒，可能发生了跳转
      if (drift > const Duration(seconds: 5)) {
        // 限制更新频率，最高每秒一次
        final now = DateTime.now();
        if (_lastPresenceUpdate == null || now.difference(_lastPresenceUpdate!) > const Duration(seconds: 1)) {
          _lastPresenceUpdate = now;
          _updatePresence();
        }
      }
    }
  }

  /// 恢复播放 (恢复时间戳)
  Future<void> resumePlayback() async {
    if (_currentMetadata == null) return;

    // 重置开始时间以显示已播放时间
    _playbackStartTime = DateTime.now();

    if (_isEnabled && _isConnected) {
      await _updatePresence();
    }
  }

  /// 暂停播放 - 清除时间戳但保留显示内容
  Future<void> pausePlayback() async {
    // 清除开始时间，以便 Discord 停止计时
    _playbackStartTime = null;

    if (_isEnabled && _isConnected) {
      await _updatePresence();
    }
  }

  /// 播放结束时停止显示状态
  Future<void> stopPlayback() async {
    _currentMetadata = null;
    _currentClient = null;
    _playbackStartTime = null;
    _cachedThumbnailUrl = null;

    if (_isEnabled && _isConnected) {
      await clearPresence();
    }
  }

  /// 清除状态显示
  Future<void> clearPresence() async {
    try {
      _rpc?.clearPresence();
    } catch (e) {
      appLogger.d('清除 Discord 状态失败', error: e);
    }
  }

  /// 释放服务 (应用关闭时调用)
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await _disconnect();
  }

  // 私有方法

  Future<void> _connect() async {
    if (_rpc != null) return;

    try {
      _rpc = DiscordRPC();

      _readySubscription = _rpc!.onReady.listen((_) async {
        _isConnected = true;
        appLogger.i('Discord RPC 已连接');

        // 连接后稍作延迟以待 Discord 稳定
        await Future.delayed(const Duration(milliseconds: 200));

        // 如果当前正在播放，上传缩略图并更新状态
        if (_currentMetadata != null) {
          await _uploadThumbnailAndUpdatePresence();
        }
      });

      _disconnectedSubscription = _rpc!.onDisconnected.listen((_) {
        _isConnected = false;
        appLogger.i('Discord RPC 已断开');
        _scheduleReconnect();
      });

      _errorSubscription = _rpc!.onError.listen((error) {
        appLogger.w('Discord RPC 错误: $error');
      });

      await _rpc!.initialize(_applicationId);
    } catch (e) {
      appLogger.w('初始化 Discord RPC 失败', error: e);
      // 失败时清理以便重试
      await _readySubscription?.cancel();
      await _disconnectedSubscription?.cancel();
      await _errorSubscription?.cancel();
      _readySubscription = null;
      _disconnectedSubscription = null;
      _errorSubscription = null;
      try {
        _rpc?.dispose();
      } catch (_) {}
      _rpc = null;
      _scheduleReconnect();
    }
  }

  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    _isConnected = false;

    await _readySubscription?.cancel();
    await _disconnectedSubscription?.cancel();
    await _errorSubscription?.cancel();
    _readySubscription = null;
    _disconnectedSubscription = null;
    _errorSubscription = null;

    try {
      _rpc?.dispose();
    } catch (e) {
      appLogger.d('释放 Discord RPC 错误', error: e);
    }
    _rpc = null;
  }

  void _scheduleReconnect() {
    if (!_isEnabled) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 30), () {
      if (_isEnabled && !_isConnected) {
        _connect();
      }
    });
  }

  Future<void> _uploadThumbnailAndUpdatePresence() async {
    // 尝试上传缩略图，失败时不阻塞
    if (_cachedThumbnailUrl == null && _currentMetadata != null && _currentClient != null) {
      _cachedThumbnailUrl = await _uploadThumbnail(_currentMetadata!, _currentClient!);
    }
    await _updatePresence();
  }

  Future<String?> _uploadThumbnail(PlexMetadata metadata, PlexClient client) async {
    try {
      // 获取缩略图路径 (剧集优先使用剧集海报)
      final thumbPath = metadata.grandparentThumb ?? metadata.thumb;
      if (thumbPath == null || thumbPath.isEmpty) return null;

      // 首先检查缓存 (包含过期检查)
      final cached = _litterboxCache[thumbPath];
      if (cached != null && !cached.isExpired) {
        appLogger.d('正在使用缓存的 Litterbox URL: $thumbPath');
        return cached.url;
      }

      // 获取包含认证令牌的完整 URL
      final imageUrl = client.getThumbnailUrl(thumbPath);
      if (imageUrl.isEmpty) return null;

      // 获取图片数据
      final dio = Dio();
      final imageResponse = await dio.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 10)),
      );

      final imageBytes = imageResponse.data;
      if (imageBytes == null || imageBytes.isEmpty) return null;

      // 上传至 Litterbox
      final formData = FormData.fromMap({
        'reqtype': 'fileupload',
        'time': '1h',
        'fileToUpload': MultipartFile.fromBytes(Uint8List.fromList(imageBytes), filename: 'thumbnail.jpg'),
      });

      final uploadResponse = await dio.post<String>(
        _litterboxUrl,
        data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );

      final uploadedUrl = uploadResponse.data?.trim();
      if (uploadedUrl != null && uploadedUrl.startsWith('http')) {
        // 缓存 URL，过期时间 1 小时 (与 Litterbox 一致)
        _litterboxCache[thumbPath] = _CachedUrl(uploadedUrl, DateTime.now().add(const Duration(hours: 1)));
        appLogger.d('已上传并缓存缩略图: $uploadedUrl');
        return uploadedUrl;
      }
    } catch (e) {
      appLogger.d('上传缩略图至 Litterbox 失败', error: e);
    }
    return null;
  }

  Future<void> _updatePresence() async {
    if (_rpc == null || !_isConnected || _currentMetadata == null) return;

    try {
      final metadata = _currentMetadata!;
      final details = _buildDetails(metadata);
      final state = _buildState(metadata);

      await _rpc!.setPresence(
        DiscordPresence(
          type: DiscordActivityType.watching,
          details: details,
          state: state,
          timestamps: _buildTimestamps(),
          statusDisplayType: DiscordStatusDisplayType.details,
          largeAsset: _cachedThumbnailUrl != null
              ? DiscordAsset(url: _cachedThumbnailUrl!, text: metadata.grandparentTitle ?? metadata.title)
              : null,
        ),
      );
    } catch (e) {
      appLogger.d('更新 Discord 状态失败', error: e);
    }
  }

  /// 为 Discord 进度条构建时间戳
  DiscordTimestamps? _buildTimestamps() {
    // 暂停时不显示时间戳 (进度条会不准确)
    if (_playbackStartTime == null) return null;

    // 如果有持续时间，显示进度条
    if (_mediaDuration != null) {
      final now = DateTime.now();
      final position = _currentPosition ?? Duration.zero;

      // 计算播放“开始”时间 (当前时间减去已播放位置)
      final effectiveStart = now.subtract(position);

      // 计算播放将要“结束”的时间 (开始时间加总时长)
      final effectiveEnd = effectiveStart.add(_mediaDuration!);

      return DiscordTimestamps.range(effectiveStart, effectiveEnd);
    }

    // 回退方案：仅显示已播放时间
    return DiscordTimestamps.started(_playbackStartTime!);
  }

  /// 构建主详情行 (状态的第一行)
  String _buildDetails(PlexMetadata metadata) {
    switch (metadata.mediaType) {
      case PlexMediaType.movie:
        final year = metadata.year != null ? ' (${metadata.year})' : '';
        return metadata.title + year;

      case PlexMediaType.episode:
        // 显示：剧集名称，如果没有剧集名称则仅显示剧集标题
        return metadata.grandparentTitle ?? metadata.title;

      default:
        return metadata.title;
    }
  }

  /// 构建状态行 (状态的第二行)
  String? _buildState(PlexMetadata metadata) {
    switch (metadata.mediaType) {
      case PlexMediaType.episode:
        // 格式："S1 E5 - 剧集标题"
        final season = metadata.parentIndex;
        final episode = metadata.index;
        if (season != null && episode != null) {
          return 'S$season E$episode - ${metadata.title}';
        }
        return metadata.title;

      case PlexMediaType.movie:
        return metadata.studio;

      default:
        return null;
    }
  }
}
