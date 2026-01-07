import '../utils/formatters.dart';

enum DownloadStatus {
  queued, // 已加入队列
  downloading, // 正在下载
  paused, // 已暂停
  completed, // 已完成
  failed, // 失败
  cancelled, // 已取消
  partial, // 部分下载（适用于剧集/季，已下载部分集但未全部完成）
}

class DownloadProgress {
  final String globalKey;
  final DownloadStatus status;
  final int progress; // 进度 0-100
  final int downloadedBytes; // 已下载字节数
  final int totalBytes; // 总字节数
  final double speed; // 下载速度（字节/秒）
  final String? errorMessage; // 错误信息
  final String? currentFile; // 当前正在下载的文件（视频、字幕、封面图等）

  // 缩略图路径（在封面图下载完成后填充）
  final String? thumbPath;

  const DownloadProgress({
    required this.globalKey,
    required this.status,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speed = 0,
    this.errorMessage,
    this.currentFile,
    this.thumbPath,
  });

  double get progressPercent => progress / 100.0;

  String get speedFormatted => ByteFormatter.formatSpeed(speed);
  String get downloadedFormatted => ByteFormatter.formatBytes(downloadedBytes);
  String get totalFormatted => ByteFormatter.formatBytes(totalBytes);

  Duration? get estimatedTimeRemaining {
    if (speed <= 0 || totalBytes <= 0) return null;
    final remainingBytes = totalBytes - downloadedBytes;
    if (remainingBytes <= 0) return Duration.zero;
    return Duration(seconds: (remainingBytes / speed).round());
  }

  /// 检查此进度更新是否包含艺术图路径
  bool get hasArtworkPaths => thumbPath != null;

  DownloadProgress copyWith({
    String? globalKey,
    DownloadStatus? status,
    int? progress,
    int? downloadedBytes,
    int? totalBytes,
    double? speed,
    String? errorMessage,
    String? currentFile,
    String? thumbPath,
  }) {
    return DownloadProgress(
      globalKey: globalKey ?? this.globalKey,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speed: speed ?? this.speed,
      errorMessage: errorMessage ?? this.errorMessage,
      currentFile: currentFile ?? this.currentFile,
      thumbPath: thumbPath ?? this.thumbPath,
    );
  }
}

class DeletionProgress {
  final String globalKey;
  final String itemTitle;
  final int currentItem;
  final int totalItems;
  final String? currentOperation;

  const DeletionProgress({
    required this.globalKey,
    required this.itemTitle,
    required this.currentItem,
    required this.totalItems,
    this.currentOperation,
  });

  double get progressPercent => totalItems > 0 ? (currentItem / totalItems) : 0.0;

  int get progressPercentInt => (progressPercent * 100).round();

  bool get isComplete => currentItem >= totalItems;

  DeletionProgress copyWith({
    String? globalKey,
    String? itemTitle,
    int? currentItem,
    int? totalItems,
    String? currentOperation,
  }) {
    return DeletionProgress(
      globalKey: globalKey ?? this.globalKey,
      itemTitle: itemTitle ?? this.itemTitle,
      currentItem: currentItem ?? this.currentItem,
      totalItems: totalItems ?? this.totalItems,
      currentOperation: currentOperation ?? this.currentOperation,
    );
  }

  @override
  String toString() {
    return 'DeletionProgress(globalKey: $globalKey, itemTitle: $itemTitle, '
        'currentItem: $currentItem, totalItems: $totalItems, '
        'progressPercent: $progressPercentInt%)';
  }
}
