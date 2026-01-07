import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../models/plex_metadata.dart';
import '../utils/formatters.dart';
import 'settings_service.dart';
import 'saf_storage_service.dart';

class DownloadStorageService {
  static DownloadStorageService? _instance;
  static DownloadStorageService get instance => _instance ??= DownloadStorageService._();
  DownloadStorageService._();

  Directory? _baseDownloadsDir;
  String? _artworkDirectoryPath;

  // 自定义路径配置
  SettingsService? _settingsService;
  String? _customDownloadPath;
  String _customPathType = 'file';

  /// 检查当前是否使用 SAF 模式 (仅限 Android)
  bool get isUsingSaf => Platform.isAndroid && _customPathType == 'saf' && _customDownloadPath != null;

  /// 获取 SAF 基础 URI (仅在 isUsingSaf 为 true 时有效)
  String? get safBaseUri => isUsingSaf ? _customDownloadPath : null;

  /// 获取封面图目录路径 (缓存，首次调用后为同步)
  String? get artworkDirectoryPath => _artworkDirectoryPath;

  /// 使用设置服务初始化 (在应用启动期间调用)
  Future<void> initialize(SettingsService settingsService) async {
    _settingsService = settingsService;
    _customDownloadPath = settingsService.getCustomDownloadPath();
    _customPathType = settingsService.getCustomDownloadPathType();
    // 重置缓存的目录以强制重新计算
    _baseDownloadsDir = null;
    _artworkDirectoryPath = null;
  }

  /// 从设置中刷新自定义路径 (在设置更改时调用)
  Future<void> refreshCustomPath() async {
    if (_settingsService != null) {
      _customDownloadPath = _settingsService!.getCustomDownloadPath();
      _customPathType = _settingsService!.getCustomDownloadPathType();
      _baseDownloadsDir = null;
      _artworkDirectoryPath = null;
    }
  }

  /// 获取用于存储数据的应用基础目录。
  /// 移动端使用 ApplicationDocumentsDirectory，桌面端使用 ApplicationSupportDirectory。
  Future<Directory> _getBaseAppDir() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }
    return getApplicationSupportDirectory();
  }

  /// 格式化剧集文件名基础：S{XX}E{XX} - {标题}
  String _formatEpisodeFileName(PlexMetadata episode) {
    final season = padNumber(episode.parentIndex ?? 0, 2);
    final ep = padNumber(episode.index ?? 0, 2);
    final episodeName = _sanitizeFileName(episode.title);
    return 'S${season}E$ep - $episodeName';
  }

  /// 检查是否使用自定义下载路径
  bool isUsingCustomPath() => _customDownloadPath != null;

  /// 获取当前下载路径，用于在设置中显示
  Future<String> getCurrentDownloadPathDisplay() async {
    if (_customDownloadPath != null) {
      return _customDownloadPath!;
    }
    final dir = await getDownloadsDirectory();
    return dir.path;
  }

  /// 获取默认下载路径 (用于“重置为默认值”功能)
  Future<String> getDefaultDownloadPath() async {
    final baseDir = await _getBaseAppDir();
    return path.join(baseDir.path, 'downloads');
  }

  /// 检查目录是否可写
  Future<bool> isDirectoryWritable(Directory dir) async {
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // 使用临时文件测试写入权限
      final testFile = File(path.join(dir.path, '.write_test_${DateTime.now().millisecondsSinceEpoch}'));
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 初始化并获取基础下载目录
  Future<Directory> getDownloadsDirectory() async {
    if (_baseDownloadsDir != null) return _baseDownloadsDir!;

    // 首先检查自定义路径 (仅限文件类型 - SAF 处理方式不同)
    if (_customDownloadPath != null && _customPathType == 'file') {
      final customDir = Directory(_customDownloadPath!);
      if (await isDirectoryWritable(customDir)) {
        _baseDownloadsDir = customDir;
        return _baseDownloadsDir!;
      }
      // 如果自定义路径不可写，则回退到默认路径
    }

    // 默认路径逻辑
    final baseDir = await _getBaseAppDir();
    _baseDownloadsDir = await _ensureDirectoryExists(Directory(path.join(baseDir.path, 'downloads')));
    return _baseDownloadsDir!;
  }

  /// 获取用于离线封面图缓存的集中封面图目录
  /// 此目录存储具有哈希文件名的封面图文件，以便去重
  Future<Directory> getArtworkDirectory() async {
    // 如果设置了自定义下载路径，则将封面图放在下载目录旁边
    if (_customDownloadPath != null && _customPathType == 'file') {
      final customDir = Directory(_customDownloadPath!);
      final parent = customDir.parent;
      final artworkDir = Directory(path.join(parent.path, 'artwork'));
      try {
        // 验证自定义封面图路径的写入权限
        if (await isDirectoryWritable(artworkDir)) {
          _artworkDirectoryPath = artworkDir.path;
          return artworkDir;
        }
      } catch (e) {
        // 如果无法创建封面图目录，则回退到默认路径
      }
    }

    // 默认：直接获取应用基础目录 (不是下载目录)
    final baseDir = await _getBaseAppDir();
    final artworkDir = await _ensureDirectoryExists(Directory(path.join(baseDir.path, 'artwork')));
    // 缓存路径以进行同步访问
    _artworkDirectoryPath = artworkDir.path;
    return artworkDir;
  }

  /// 从 Plex 缩略图路径获取封面图文件路径 (同步版本，需要先初始化)
  /// 使用缩略图 URL 的哈希值返回缓存的封面图文件路径
  /// 示例：artwork/a1b2c3d4e5f6.jpg
  String getArtworkPathSync(String serverId, String thumbPath) {
    if (_artworkDirectoryPath == null) {
      throw StateError('封面图目录未初始化。请先调用 getArtworkDirectory()。');
    }
    // 从 serverId:thumbPath 创建哈希以进行去重
    final hash = _hashArtworkPath(serverId, thumbPath);
    return path.join(_artworkDirectoryPath!, '$hash.jpg');
  }

  /// 从 Plex 缩略图路径获取封面图文件路径 (异步版本)
  Future<String> getArtworkPathFromThumb(String serverId, String thumbPath) async {
    final artworkDir = await getArtworkDirectory();
    final hash = _hashArtworkPath(serverId, thumbPath);
    return path.join(artworkDir.path, '$hash.jpg');
  }

  /// 检查封面图是否已存在 (用于去重)
  Future<bool> artworkExists(String serverId, String thumbPath) async {
    final artworkPath = await getArtworkPathFromThumb(serverId, thumbPath);
    return File(artworkPath).exists();
  }

  /// 对封面图路径进行哈希处理以作为文件名，使用 MD5 以确保在应用重启后保持稳定
  String _hashArtworkPath(String serverId, String thumbPath) {
    final combined = '$serverId:$thumbPath';
    return md5.convert(utf8.encode(combined)).toString();
  }

  /// 获取特定媒体项目的目录
  Future<Directory> getMediaDirectory(String serverId, String ratingKey) async {
    final baseDir = await getDownloadsDirectory();
    return _ensureDirectoryExists(Directory(path.join(baseDir.path, serverId, ratingKey)));
  }

  /// 获取视频文件路径
  Future<String> getVideoFilePath(String serverId, String ratingKey, String extension) async {
    final mediaDir = await getMediaDirectory(serverId, ratingKey);
    return path.join(mediaDir.path, 'video.$extension');
  }

  /// 获取封面图文件路径 (海报、插图、缩略图)
  Future<String> getArtworkPath(String serverId, String ratingKey, String artworkType) async {
    final mediaDir = await getMediaDirectory(serverId, ratingKey);
    return path.join(mediaDir.path, '$artworkType.jpg');
  }

  /// 获取字幕目录
  Future<Directory> getSubtitlesDirectory(String serverId, String ratingKey) async {
    final mediaDir = await getMediaDirectory(serverId, ratingKey);
    final subtitlesDir = Directory(path.join(mediaDir.path, 'subtitles'));
    if (!await subtitlesDir.exists()) {
      await subtitlesDir.create(recursive: true);
    }
    return subtitlesDir;
  }

  /// 获取字幕文件路径
  Future<String> getSubtitlePath(String serverId, String ratingKey, int trackId, String extension) async {
    final subtitlesDir = await getSubtitlesDirectory(serverId, ratingKey);
    return path.join(subtitlesDir.path, '$trackId.$extension');
  }

  // ============================================================
  // 用户友好路径方法 (用于在文件应用中可见)
  // ============================================================

  /// 通过删除无效的文件系统字符来清理文件名
  String _sanitizeFileName(String name) {
    // 删除无效的文件系统字符: < > : " / \ | ? *
    // 同时删除首尾的空格和点
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').replaceAll(RegExp(r'^\.+|\.+$'), '').trim();
  }

  /// 确保目录存在，如果不存在则创建
  Future<Directory> _ensureDirectoryExists(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 格式化带有可选年份的媒体标题: "标题 (YYYY)" 或 "标题"
  String _formatTitleWithYear(String title, int? year) {
    final sanitized = _sanitizeFileName(title);
    return year != null ? '$sanitized ($year)' : sanitized;
  }

  /// 获取电影的文件夹名称: "电影名称 (YYYY)"
  String _getMovieFolderName(PlexMetadata movie) {
    return _formatTitleWithYear(movie.title, movie.year);
  }

  /// 获取电视剧的文件夹名称: "剧集名称 (YYYY)"
  /// [showYear]: 显式传递剧集年份 (单集年份可能与剧集年份不同)
  String _getShowFolderName(PlexMetadata metadata, {int? showYear}) {
    final title = metadata.grandparentTitle ?? metadata.title;
    final year = showYear ?? metadata.year;
    return _formatTitleWithYear(title, year);
  }

  /// 获取电影目录: downloads/Movies/{电影名称} ({年份})/
  Future<Directory> getMovieDirectory(PlexMetadata movie) async {
    final baseDir = await getDownloadsDirectory();
    final movieFolder = _getMovieFolderName(movie);
    return _ensureDirectoryExists(Directory(path.join(baseDir.path, 'Movies', movieFolder)));
  }

  /// 获取电影视频文件路径: .../电影名称 (YYYY)/电影名称 (YYYY).{ext}
  Future<String> getMovieVideoPath(PlexMetadata movie, String extension) async {
    final movieDir = await getMovieDirectory(movie);
    final fileName = _getMovieFolderName(movie);
    return path.join(movieDir.path, '$fileName.$extension');
  }

  /// 获取电影封面图路径: .../电影名称 (YYYY)/{artworkType}.jpg
  Future<String> getMovieArtworkPath(PlexMetadata movie, String artworkType) async {
    final movieDir = await getMovieDirectory(movie);
    return path.join(movieDir.path, '$artworkType.jpg');
  }

  /// 获取电视剧目录: downloads/TV Shows/{剧集名称} ({年份})/
  /// [showYear]: 显式传递剧集首播年份 (对于单集，单集的年份可能与剧集年份不同)。
  /// 如果未提供，则使用 metadata.year。
  Future<Directory> getShowDirectory(PlexMetadata metadata, {int? showYear}) async {
    final baseDir = await getDownloadsDirectory();
    final showFolder = _getShowFolderName(metadata, showYear: showYear);
    return _ensureDirectoryExists(Directory(path.join(baseDir.path, 'TV Shows', showFolder)));
  }

  /// 获取剧集封面图路径: downloads/TV Shows/{剧集}/poster.jpg
  Future<String> getShowArtworkPath(PlexMetadata metadata, String artworkType, {int? showYear}) async {
    final showDir = await getShowDirectory(metadata, showYear: showYear);
    return path.join(showDir.path, '$artworkType.jpg');
  }

  /// 获取季目录: .../TV Shows/{剧集}/Season {XX}/
  /// [showYear]: 传递剧集首播年份 (不是单集或季年份)
  Future<Directory> getSeasonDirectory(PlexMetadata metadata, {int? showYear}) async {
    final showDir = await getShowDirectory(metadata, showYear: showYear);
    final seasonNum = padNumber(metadata.parentIndex ?? 0, 2);
    return _ensureDirectoryExists(Directory(path.join(showDir.path, 'Season $seasonNum')));
  }

  /// 获取季封面图路径: .../Season XX/poster.jpg
  Future<String> getSeasonArtworkPath(PlexMetadata metadata, String artworkType, {int? showYear}) async {
    final seasonDir = await getSeasonDirectory(metadata, showYear: showYear);
    return path.join(seasonDir.path, '$artworkType.jpg');
  }

  /// 获取单集文件的基础路径信息 (季目录路径和格式化后的文件名)。
  /// [showYear]: 传递剧集首播年份 (不是单集年份)
  Future<({String seasonDirPath, String fileName})> _getEpisodeBasePath(PlexMetadata episode, {int? showYear}) async {
    final seasonDir = await getSeasonDirectory(episode, showYear: showYear);
    final fileName = _formatEpisodeFileName(episode);
    return (seasonDirPath: seasonDir.path, fileName: fileName);
  }

  /// 获取单集视频文件路径: .../Season XX/S{XX}E{XX} - {标题}.{ext}
  /// [showYear]: 传递剧集首播年份 (不是单集年份)
  Future<String> getEpisodeVideoPath(PlexMetadata episode, String extension, {int? showYear}) async {
    final base = await _getEpisodeBasePath(episode, showYear: showYear);
    return path.join(base.seasonDirPath, '${base.fileName}.$extension');
  }

  /// 获取单集缩略图路径: .../Season XX/S{XX}E{XX} - {标题}.jpg
  /// [showYear]: 传递剧集首播年份 (不是单集年份)
  Future<String> getEpisodeThumbnailPath(PlexMetadata episode, {int? showYear}) async {
    final base = await _getEpisodeBasePath(episode, showYear: showYear);
    return path.join(base.seasonDirPath, '${base.fileName}.jpg');
  }

  /// 获取单集字幕目录: .../Season XX/S{XX}E{XX} - {标题}_subs/
  /// [showYear]: 传递剧集首播年份 (不是单集年份)
  Future<Directory> getEpisodeSubtitlesDirectory(PlexMetadata episode, {int? showYear}) async {
    final base = await _getEpisodeBasePath(episode, showYear: showYear);
    return _ensureDirectoryExists(Directory(path.join(base.seasonDirPath, '${base.fileName}_subs')));
  }

  /// 获取单集字幕路径
  /// [showYear]: 传递剧集首播年份 (不是单集年份)
  Future<String> getEpisodeSubtitlePath(PlexMetadata episode, int trackId, String extension, {int? showYear}) async {
    final subsDir = await getEpisodeSubtitlesDirectory(episode, showYear: showYear);
    return path.join(subsDir.path, '$trackId.$extension');
  }

  /// 获取电影字幕目录
  Future<Directory> getMovieSubtitlesDirectory(PlexMetadata movie) async {
    final movieDir = await getMovieDirectory(movie);
    final baseName = _getMovieFolderName(movie);
    return _ensureDirectoryExists(Directory(path.join(movieDir.path, '${baseName}_subs')));
  }

  /// 获取电影字幕路径
  Future<String> getMovieSubtitlePath(PlexMetadata movie, int trackId, String extension) async {
    final subsDir = await getMovieSubtitlesDirectory(movie);
    return path.join(subsDir.path, '$trackId.$extension');
  }

  /// 删除媒体项目的所有文件
  Future<void> deleteMediaFiles(String serverId, String ratingKey) async {
    final mediaDir = await getMediaDirectory(serverId, ratingKey);
    if (await mediaDir.exists()) {
      await mediaDir.delete(recursive: true);
    }
  }

  /// 将绝对文件路径转换为相对路径 (用于数据库存储)
  /// 这可以确保路径在 iOS 上的应用重新安装时保持有效，因为 iOS 的容器 UUID 可能会更改。
  /// 返回相对于应用文档目录的路径。
  Future<String> toRelativePath(String absolutePath) async {
    final baseDir = await _getBaseAppDir();

    // 如果路径以基础目录开头，则将其剥离
    if (absolutePath.startsWith(baseDir.path)) {
      // 移除基础路径和任何前导分隔符
      var relative = absolutePath.substring(baseDir.path.length);
      if (relative.startsWith('/') || relative.startsWith('\\')) {
        relative = relative.substring(1);
      }
      return relative;
    }

    // 已经是相对路径或来自不同的基础目录 - 按原样返回
    return absolutePath;
  }

  /// 将相对文件路径转换为绝对路径 (用于文件操作)
  /// 使用当前应用文档目录重建完整路径。
  Future<String> toAbsolutePath(String relativePath) async {
    // 如果已经是绝对路径，则按原样返回
    if (path.isAbsolute(relativePath)) {
      return relativePath;
    }

    final baseDir = await _getBaseAppDir();
    return path.join(baseDir.path, relativePath);
  }

  /// 将可能存在的绝对路径 (来自旧数据库条目) 转换为绝对路径
  /// 这可以处理旧的绝对路径和新的相对路径
  Future<String> ensureAbsolutePath(String storedPath) async {
    if (path.isAbsolute(storedPath)) {
      // 已经是绝对路径 - 检查此路径下的文件是否存在
      if (await File(storedPath).exists()) {
        return storedPath;
      }
      // 文件在绝对路径下不存在 - 尝试重建
      // 提取相对部分 ( 'downloads/' 之后的所有内容)
      final downloadsIndex = storedPath.indexOf('downloads/');
      if (downloadsIndex != -1) {
        final relativePart = storedPath.substring(downloadsIndex);
        return await toAbsolutePath(relativePart);
      }
      // 无法重建，返回原始路径
      return storedPath;
    }
    // 相对路径 - 转换为绝对路径
    return await toAbsolutePath(storedPath);
  }

  /// 计算下载使用的总存储空间
  Future<int> getTotalStorageUsed() async {
    final baseDir = await getDownloadsDirectory();
    return _calculateDirectorySize(baseDir);
  }

  Future<int> _calculateDirectorySize(Directory dir) async {
    int size = 0;
    if (!await dir.exists()) return size;

    await for (var entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          size += await entity.length();
        } catch (_) {
          // 忽略读取文件大小时的错误
        }
      }
    }
    return size;
  }

  /// 将字节格式化为人类可读的字符串
  static String formatBytes(int bytes) => ByteFormatter.formatBytes(bytes);

  // ============================================================
  // 安卓 SAF (Storage Access Framework) 支持
  // ============================================================

  /// 获取初始下载的临时缓存目录
  /// 文件首先下载到这里，如果使用 SAF 模式，然后再复制到 SAF
  Future<Directory> getCacheDownloadDirectory() async {
    final cacheDir = await getApplicationDocumentsDirectory();
    return _ensureDirectoryExists(Directory(path.join(cacheDir.path, '.download_cache')));
  }

  /// 获取下载的临时文件路径 (在复制到 SAF 之前)
  Future<String> getTempDownloadPath(String fileName) async {
    final cacheDir = await getCacheDownloadDirectory();
    return path.join(cacheDir.path, fileName);
  }

  /// 将文件从临时缓存复制到 SAF 并返回 SAF URI
  /// 如果 SAF 不可用或复制失败，则返回 null
  /// 无论成功还是失败，始终清理临时文件
  Future<String?> copyToSaf(String tempFilePath, List<String> pathComponents, String fileName, String mimeType) async {
    if (!isUsingSaf || _customDownloadPath == null) return null;

    final safService = SafStorageService.instance;

    try {
      // 在 SAF 中创建嵌套目录结构
      final targetDirUri = await safService.createNestedDirectories(_customDownloadPath!, pathComponents);

      if (targetDirUri == null) {
        return null;
      }

      // 使用原生复制将文件复制到 SAF
      final safUri = await safService.copyFileToSaf(tempFilePath, targetDirUri, fileName, mimeType);

      return safUri;
    } finally {
      // 无论成功还是失败，始终清理临时文件
      try {
        final tempFile = File(tempFilePath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // 忽略清理错误
      }
    }
  }

  /// 获取文件扩展名的 MIME 类型
  String getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'mp4':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'm4v':
        return 'video/x-m4v';
      case 'avi':
        return 'video/x-msvideo';
      case 'ogv':
        return 'video/ogg';
      case 'webm':
        return 'video/webm';
      case 'srt':
        return 'application/x-subrip';
      case 'vtt':
        return 'text/vtt';
      case 'ass':
      case 'ssa':
        return 'text/x-ssa';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  /// 根据媒体类型获取 SAF 路径组件
  /// 返回在 SAF 基础路径下创建的目录名称列表
  List<String> getMovieSafPathComponents(PlexMetadata movie) {
    return ['Movies', _getMovieFolderName(movie)];
  }

  /// 获取单集 SAF 存储的路径组件
  List<String> getEpisodeSafPathComponents(PlexMetadata episode, {int? showYear}) {
    final showFolder = _getShowFolderName(episode, showYear: showYear);
    final seasonNum = padNumber(episode.parentIndex ?? 0, 2);
    return ['TV Shows', showFolder, 'Season $seasonNum'];
  }

  /// 获取电影的 SAF 文件名
  String getMovieSafFileName(PlexMetadata movie, String extension) {
    return '${_getMovieFolderName(movie)}.$extension';
  }

  /// 获取单集的 SAF 文件名
  String getEpisodeSafFileName(PlexMetadata episode, String extension) {
    final fileName = _formatEpisodeFileName(episode);
    return '$fileName.$extension';
  }

  /// 检查路径是否为 SAF 内容 URI
  bool isSafUri(String storedPath) {
    return storedPath.startsWith('content://');
  }

  /// 获取存储路径的可读路径 (处理 SAF URI 和文件路径)
  /// 对于 SAF URI，按原样返回 URI (content:// URI 可与媒体播放器配合使用)
  /// 对于文件路径，确保路径是绝对路径
  Future<String> getReadablePath(String storedPath) async {
    if (isSafUri(storedPath)) {
      // SAF content:// URI 已经可以被媒体播放器读取
      return storedPath;
    }
    return await ensureAbsolutePath(storedPath);
  }
}
