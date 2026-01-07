import '../utils/formatters.dart';
import '../utils/codec_utils.dart';

class PlexMediaVersion {
  final int id;
  final String? videoResolution;
  final String? videoCodec;
  final int? bitrate;
  final int? width;
  final int? height;
  final String? container;
  final String partKey;

  PlexMediaVersion({
    required this.id,
    this.videoResolution,
    this.videoCodec,
    this.bitrate,
    this.width,
    this.height,
    this.container,
    required this.partKey,
  });

  /// 从 Plex API 的 Media 对象创建 PlexMediaVersion
  factory PlexMediaVersion.fromJson(Map<String, dynamic> json) {
    // 获取用于播放的第一个 Part key
    final parts = json['Part'] as List<dynamic>?;
    final partKey = parts != null && parts.isNotEmpty ? parts[0]['key'] as String? ?? '' : '';

    return PlexMediaVersion(
      id: json['id'] as int? ?? 0,
      videoResolution: json['videoResolution'] as String?,
      videoCodec: json['videoCodec'] as String?,
      bitrate: json['bitrate'] as int?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      container: json['container'] as String?,
      partKey: partKey,
    );
  }

  /// 包含详细信息的显示标签：例如 "1080p H.264 MKV (8.5 Mbps)"
  String get displayLabel {
    final parts = <String>[];

    // 添加分辨率
    if (videoResolution != null && videoResolution!.isNotEmpty) {
      parts.add('${videoResolution}p');
    } else if (height != null) {
      parts.add('${height}p');
    }

    // 添加编解码器
    if (videoCodec != null && videoCodec!.isNotEmpty) {
      parts.add(CodecUtils.formatVideoCodec(videoCodec!));
    }

    // 添加容器格式
    if (container != null && container!.isNotEmpty) {
      parts.add(container!.toUpperCase());
    }

    // 构建主标签
    String label = parts.isNotEmpty ? parts.join(' ') : '未知';

    // 在括号中添加比特率
    if (bitrate != null && bitrate! > 0) {
      label += ' (${ByteFormatter.formatBitrate(bitrate!)})';
    }

    return label;
  }

  @override
  String toString() => displayLabel;
}
