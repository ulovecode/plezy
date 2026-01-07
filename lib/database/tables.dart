import 'package:drift/drift.dart';

/// Plex API 响应的键值缓存表。
/// 用于离线支持 - 存储原始 JSON 响应。
class ApiCache extends Table {
  /// 复合键：serverId:endpoint (例如 "abc123:/library/metadata/12345")
  TextColumn get cacheKey => text()();

  /// JSON 响应数据
  TextColumn get data => text()();

  /// 此项目是否已固定以便离线访问
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// 用于缓存失效的时间戳 (可选的未来用途)
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {cacheKey};
}

@DataClassName('DownloadQueueItem')
class DownloadQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mediaGlobalKey => text().unique()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  IntColumn get addedAt => integer()();
  BoolColumn get downloadSubtitles => boolean().withDefault(const Constant(true))();
  BoolColumn get downloadArtwork => boolean().withDefault(const Constant(true))();
}

@DataClassName('DownloadedMediaItem')
class DownloadedMedia extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text()();
  TextColumn get ratingKey => text()();
  TextColumn get globalKey => text().unique()();
  TextColumn get type => text()();
  TextColumn get parentRatingKey => text().nullable()();
  TextColumn get grandparentRatingKey => text().nullable()();
  IntColumn get status => integer()();
  IntColumn get progress => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().nullable()();
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();
  TextColumn get videoFilePath => text().nullable()();
  TextColumn get thumbPath => text().nullable()();
  IntColumn get downloadedAt => integer().nullable()();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
}

/// 离线观看进度和手动观看操作队列。
///
/// 存储观看进度更新和手动已看/未看操作，
/// 这些操作需要在恢复在线时同步到 Plex 服务器。
@DataClassName('OfflineWatchProgressItem')
class OfflineWatchProgress extends Table {
  /// 自增主键
  IntColumn get id => integer().autoIncrement()();

  /// 此媒体所属的服务器 ID
  TextColumn get serverId => text()();

  /// 媒体项目的 Rating key
  TextColumn get ratingKey => text()();

  /// 用于快速查找的全局键 (serverId:ratingKey)
  TextColumn get globalKey => text()();

  /// 操作类型：'progress', 'watched', 'unwatched'
  TextColumn get actionType => text()();

  /// 当前播放位置，以毫秒为单位 (用于 'progress' 操作)
  IntColumn get viewOffset => integer().nullable()();

  /// 媒体时长，以毫秒为单位 (用于计算百分比)
  IntColumn get duration => integer().nullable()();

  /// 是否应将此项目标记为已看 (用于进度同步)
  /// 当 viewOffset >= duration 的 90% 时自动设置为 true
  BoolColumn get shouldMarkWatched => boolean().withDefault(const Constant(false))();

  /// 记录此操作的时间戳 (自纪元以来的毫秒数)
  IntColumn get createdAt => integer()();

  /// 上次更新此操作的时间戳 (用于合并进度更新)
  IntColumn get updatedAt => integer()();

  /// 同步尝试次数 (用于重试逻辑)
  IntColumn get syncAttempts => integer().withDefault(const Constant(0))();

  /// 上次同步错误消息
  TextColumn get lastError => text().nullable()();
}
