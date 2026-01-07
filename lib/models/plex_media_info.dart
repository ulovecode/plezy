import '../utils/codec_utils.dart';

class PlexMediaInfo {
  final String videoUrl;
  final List<PlexAudioTrack> audioTracks;
  final List<PlexSubtitleTrack> subtitleTracks;
  final List<PlexChapter> chapters;
  final int? partId;

  PlexMediaInfo({
    required this.videoUrl,
    required this.audioTracks,
    required this.subtitleTracks,
    required this.chapters,
    this.partId,
  });
  int? getPartId() => partId;
}

/// 用于以一致模式构建轨道标签的混入（Mixin）
mixin TrackLabelBuilder {
  int get id;
  int? get index;
  String? get displayTitle;
  String? get language;

  /// 根据给定的部分构建标签
  /// 如果存在 displayTitle，则返回它
  /// 否则，结合语言和其他部分
  String buildLabel(List<String> additionalParts) {
    if (displayTitle != null && displayTitle!.isNotEmpty) {
      return displayTitle!;
    }
    final parts = <String>[];
    if (language != null && language!.isNotEmpty) {
      parts.add(language!);
    }
    parts.addAll(additionalParts);
    return parts.isEmpty ? '轨道 ${index ?? id}' : parts.join(' · ');
  }
}

class PlexAudioTrack with TrackLabelBuilder {
  @override
  final int id;
  @override
  final int? index;
  final String? codec;
  @override
  final String? language;
  final String? languageCode;
  final String? title;
  @override
  final String? displayTitle;
  final int? channels;
  final bool selected;

  PlexAudioTrack({
    required this.id,
    this.index,
    this.codec,
    this.language,
    this.languageCode,
    this.title,
    this.displayTitle,
    this.channels,
    required this.selected,
  });

  String get label {
    final additionalParts = <String>[];
    if (codec != null) additionalParts.add(CodecUtils.formatAudioCodec(codec!));
    if (channels != null) additionalParts.add('${channels!}ch');
    return buildLabel(additionalParts);
  }
}

class PlexSubtitleTrack with TrackLabelBuilder {
  @override
  final int id;
  @override
  final int? index;
  final String? codec;
  @override
  final String? language;
  final String? languageCode;
  final String? title;
  @override
  final String? displayTitle;
  final bool selected;
  final bool forced;
  final String? key;

  PlexSubtitleTrack({
    required this.id,
    this.index,
    this.codec,
    this.language,
    this.languageCode,
    this.title,
    this.displayTitle,
    required this.selected,
    required this.forced,
    this.key,
  });

  String get label {
    final additionalParts = <String>[];
    if (forced) additionalParts.add('强制 (Forced)');
    return buildLabel(additionalParts);
  }

  /// 如果此字幕轨道是外部文件（外挂字幕），则返回 true
  /// 外部字幕具有指向 /library/streams/{id} 的 key 属性
  bool get isExternal => key != null && key!.isNotEmpty;

  /// 构建用于获取外部字幕文件的完整 URL
  /// 如果不是外部字幕，则返回 null
  String? getSubtitleUrl(String baseUrl, String token) {
    if (!isExternal) return null;

    // 根据编解码器确定文件扩展名
    final ext = CodecUtils.getSubtitleExtension(codec);

    // 构建带有身份验证令牌的 URL
    return '$baseUrl$key.$ext?X-Plex-Token=$token';
  }
}

class PlexChapter {
  final int id;
  final int? index;
  final int? startTimeOffset;
  final int? endTimeOffset;
  final String? title;
  final String? thumb;

  PlexChapter({required this.id, this.index, this.startTimeOffset, this.endTimeOffset, this.title, this.thumb});

  String get label => title ?? '章节 ${(index ?? 0) + 1}';

  Duration get startTime => Duration(milliseconds: startTimeOffset ?? 0);
  Duration? get endTime => endTimeOffset != null ? Duration(milliseconds: endTimeOffset!) : null;
}

class PlexMarker {
  final int id;
  final String type;
  final int startTimeOffset;
  final int endTimeOffset;

  PlexMarker({required this.id, required this.type, required this.startTimeOffset, required this.endTimeOffset});

  Duration get startTime => Duration(milliseconds: startTimeOffset);
  Duration get endTime => Duration(milliseconds: endTimeOffset);

  bool get isIntro => type == 'intro';
  bool get isCredits => type == 'credits';

  bool containsPosition(Duration position) {
    final posMs = position.inMilliseconds;
    return posMs >= startTimeOffset && posMs <= endTimeOffset;
  }
}

/// 在单次 API 调用中获取的合并章节和标记（Markers）
class PlaybackExtras {
  final List<PlexChapter> chapters;
  final List<PlexMarker> markers;

  PlaybackExtras({required this.chapters, required this.markers});
}
