import '../utils/formatters.dart';

class PlexFileInfo {
  // 媒体级别属性
  final String? container;
  final String? videoCodec;
  final String? videoResolution;
  final String? videoFrameRate;
  final String? videoProfile;
  final int? width;
  final int? height;
  final double? aspectRatio;
  final int? bitrate;
  final int? duration;
  final String? audioCodec;
  final String? audioProfile;
  final int? audioChannels;
  final bool? optimizedForStreaming;
  final bool? has64bitOffsets;

  // 文件级别属性
  final String? filePath;
  final int? fileSize;

  // 流级别属性（视频流详情）
  final String? colorSpace;
  final String? colorRange;
  final String? colorPrimaries;
  final String? colorTrc;
  final String? chromaSubsampling;
  final double? frameRate;
  final int? bitDepth;
  final String? audioChannelLayout;

  PlexFileInfo({
    this.container,
    this.videoCodec,
    this.videoResolution,
    this.videoFrameRate,
    this.videoProfile,
    this.width,
    this.height,
    this.aspectRatio,
    this.bitrate,
    this.duration,
    this.audioCodec,
    this.audioProfile,
    this.audioChannels,
    this.optimizedForStreaming,
    this.has64bitOffsets,
    this.filePath,
    this.fileSize,
    this.colorSpace,
    this.colorRange,
    this.colorPrimaries,
    this.colorTrc,
    this.chromaSubsampling,
    this.frameRate,
    this.bitDepth,
    this.audioChannelLayout,
  });

  /// 以人类可读的格式（GB, MB, KB, bytes）格式化文件大小
  String get fileSizeFormatted {
    if (fileSize == null) return '未知';
    return ByteFormatter.formatBytes(fileSize!, decimals: 2);
  }

  /// 以 HH:MM:SS 或 MM:SS 格式格式化时长
  String get durationFormatted {
    if (duration == null) return '未知';

    final seconds = duration! ~/ 1000;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours}小时 ${minutes}分 ${secs}秒';
    } else {
      return '${minutes}分 ${secs}秒';
    }
  }

  /// 以 Mbps 或 Kbps 格式化比特率
  String get bitrateFormatted {
    if (bitrate == null) return '未知';
    return ByteFormatter.formatBitrateBps(bitrate!);
  }

  /// 格式化分辨率为 宽度x高度
  String get resolutionFormatted {
    if (width != null && height != null) {
      return '${width}x$height';
    } else if (videoResolution != null) {
      return videoResolution!;
    }
    return '未知';
  }

  /// 格式化纵横比
  String get aspectRatioFormatted {
    if (aspectRatio != null) {
      return aspectRatio!.toStringAsFixed(2);
    }
    return '未知';
  }

  /// 格式化帧率
  String get frameRateFormatted {
    if (frameRate != null) {
      return '${frameRate!.toStringAsFixed(3)} fps';
    } else if (videoFrameRate != null) {
      return videoFrameRate!;
    }
    return '未知';
  }

  /// 格式化音频通道（例如 "2 channels (stereo)"）
  String get audioChannelsFormatted {
    if (audioChannels != null) {
      String channelText = '$audioChannels 通道';
      if (audioChannelLayout != null) {
        channelText += ' ($audioChannelLayout)';
      }
      return channelText;
    }
    return '未知';
  }
}
