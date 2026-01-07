import 'dart:math';
import '../services/plex_client.dart';

/// 不同转码策略的图像类型
enum ImageType {
  poster, // 2:3 比例海报
  art, // 宽屏背景艺术图
  thumb, // 16:9 剧集缩略图
  logo, // 比例可变的透明 Logo
  avatar, // 近似正方形的用户头像
}

class PlexImageHelper {
  static const int _widthRoundingFactor = 40;
  static const int _heightRoundingFactor = 60;

  static const int _maxTranscodedWidth = 1920;
  static const int _maxTranscodedHeight = 1080;

  static const int _minTranscodedWidth = 160;
  static const int _minTranscodedHeight = 240;

  /// 将尺寸舍入到缓存友好的值，以提高缓存命中率
  static (int width, int height) roundDimensions(double width, double height) {
    final roundedWidth = (width / _widthRoundingFactor).ceil() * _widthRoundingFactor;
    final roundedHeight = (height / _heightRoundingFactor).ceil() * _heightRoundingFactor;

    return (
      roundedWidth.clamp(_minTranscodedWidth, _maxTranscodedWidth),
      roundedHeight.clamp(_minTranscodedHeight, _maxTranscodedHeight),
    );
  }

  /// 根据图像类型和约束计算最佳图像尺寸
  static (int width, int height) calculateOptimalDimensions({
    required double maxWidth,
    required double maxHeight,
    required double devicePixelRatio,
    ImageType imageType = ImageType.poster,
  }) {
    final targetWidth = maxWidth.isFinite ? maxWidth * devicePixelRatio : 300 * devicePixelRatio;
    final targetHeight = maxHeight.isFinite ? maxHeight * devicePixelRatio : 450 * devicePixelRatio;

    switch (imageType) {
      case ImageType.art:
        // 对于艺术图/背景图像，在覆盖容器的同时保持宽高比
        // 计算尺寸，确保图像覆盖容器而不拉伸
        // 这模仿了转码请求的 BoxFit.cover 行为

        // 使用较大的尺寸以确保覆盖，同时保持宽高比
        // 这将请求一个稍大的图像，可以由 Flutter 的 BoxFit.cover 进行裁剪
        final coverWidth = targetWidth * 1.1; // 增加 10% 以获得更好的覆盖效果
        final coverHeight = targetHeight * 1.1;

        return roundDimensions(coverWidth, coverHeight);

      case ImageType.logo:
        // 对于 logo，使用宽松的边界以避免强制宽高比
        // 对于大多数 logo，优先使用基于宽度的缩放
        final logoWidth = targetWidth;
        final logoHeight = targetHeight; // 允许高度充分灵活
        return roundDimensions(logoWidth, logoHeight);

      case ImageType.thumb:
        // 对于剧集缩略图，针对 16:9 进行优化，但允许灵活性
        final thumbHeight = targetHeight;
        final thumbWidth = min(targetWidth, thumbHeight * (16 / 9));
        return roundDimensions(thumbWidth, thumbHeight);

      case ImageType.avatar:
        // 对于头像，根据较小的约束使用正方形尺寸
        final size = min(targetWidth, targetHeight);
        return roundDimensions(size, size);

      case ImageType.poster:
        // 对于海报，保持 2:3 的宽高比
        final calculatedWidth = min(targetWidth, targetHeight / (2 / 3));
        final calculatedHeight = calculatedWidth * (2 / 3);
        return roundDimensions(calculatedWidth, calculatedHeight);
    }
  }

  /// 构建具有优化参数的 Plex 照片转码 URL
  static String buildTranscodeUrl({
    required PlexClient client,
    required String originalPath,
    required int width,
    int? height,
  }) {
    final baseUrl = client.config.baseUrl;
    final token = client.config.token;

    // 对原始路径进行 URL 编码并带上令牌
    final encodedPath = Uri.encodeComponent(
      '$originalPath${originalPath.contains('?') ? '&' : '?'}X-Plex-Token=$token',
    );

    // 构建转码 URL
    final transcodeParams = {
      'width': width.toString(),
      if (height != null) 'height': height.toString(),
      'minSize': '1', // 确保保持最小尺寸
      'upscale': '1', // 允许放大以获得更好的质量
      'url': encodedPath,
      'X-Plex-Token': token,
    };

    final queryString = transcodeParams.entries.map((e) => '${e.key}=${e.value}').join('&');

    return '$baseUrl/photo/:/transcode?$queryString';
  }

  /// 为 Plex 内容创建优化的图像 URL
  /// 如果不适合转码，则回退到原始 URL
  /// 如果 client 为空（离线模式），则对相对路径返回空字符串
  static String getOptimizedImageUrl({
    PlexClient? client,
    required String? thumbPath,
    required double maxWidth,
    required double maxHeight,
    required double devicePixelRatio,
    bool enableTranscoding = true,
    ImageType imageType = ImageType.poster,
  }) {
    if (thumbPath == null || thumbPath.isEmpty) {
      return '';
    }

    final basePath = thumbPath;

    // 如果我们不能/不应该转码（已经是完整的 URL），直接返回。
    if (basePath.startsWith('http://') || basePath.startsWith('https://')) {
      return basePath;
    }

    // 如果没有 client（离线模式），我们无法为相对路径构建 URL
    // 图像应该在最初加载时就已经被缓存了
    if (client == null) {
      return '';
    }

    // 对于艺术图/背景图和透明 logo，优先使用原始图像，以避免
    // Plex 照片转码导致的任何宽高比变化。
    if (imageType == ImageType.art || imageType == ImageType.logo) {
      return client.getThumbnailUrl(basePath);
    }

    final canTranscode = enableTranscoding && shouldTranscode(basePath);

    // 如果标记为不可转码或禁用转码，则使用直接的缩略图 URL。
    if (!canTranscode) {
      return client.getThumbnailUrl(basePath);
    }

    // 对于非常小的图像，使用原始 URL
    if (maxWidth < 80 || maxHeight < 120) {
      return client.getThumbnailUrl(basePath);
    }

    // 计算最佳尺寸
    final (width, height) = calculateOptimalDimensions(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      devicePixelRatio: devicePixelRatio,
      imageType: imageType,
    );

    // 对于艺术图和 logo，我们只限制宽度以保持原生宽高比。
    final useWidthOnly = imageType == ImageType.art || imageType == ImageType.logo;

    // 对于接近最小尺寸的维度，使用原始图像以避免不必要的处理
    if (width <= _minTranscodedWidth * 1.2 && height <= _minTranscodedHeight * 1.2) {
      return client.getThumbnailUrl(basePath);
    }

    try {
      return buildTranscodeUrl(
        client: client,
        originalPath: basePath,
        width: width,
        height: useWidthOnly ? null : height,
      );
    } catch (e) {
      // 发生任何错误时回退到原始 URL
      return client.getThumbnailUrl(basePath);
    }
  }

  /// 为内存缓存生成缓存友好的尺寸
  static (int memWidth, int memHeight) getMemCacheDimensions({
    required int displayWidth,
    required int displayHeight,
    double scaleFactor = 1.0,
  }) {
    final scaledWidth = (displayWidth * scaleFactor).round();
    final scaledHeight = (displayHeight * scaleFactor).round();

    return (scaledWidth.clamp(120, 1200), scaledHeight.clamp(180, 1800));
  }

  /// 确定图像路径是否适合转码
  static bool shouldTranscode(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return false;

    // 不要对已经处理过的图像或外部 URL 进行转码
    if (imagePath.contains('/photo/:/transcode') ||
        imagePath.startsWith('http://') ||
        imagePath.startsWith('https://')) {
      return false;
    }

    return true;
  }

  /// 为舍入尺寸创建一致的缓存键
  static String generateCacheKey({
    required String originalPath,
    required int width,
    required int height,
    String? serverId,
  }) {
    final serverPrefix = serverId != null ? '${serverId}_' : '';
    return '${serverPrefix}transcode_${width}x${height}_${originalPath.hashCode}';
  }
}
