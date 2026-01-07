import 'codec_utils.dart';

/// 用于构建音频和字幕轨道标签的工具类。
class TrackLabelBuilder {
  TrackLabelBuilder._();

  /// 构建音频轨道标签。
  ///
  /// 组合标题、语言、编解码器和声道数。
  static String buildAudioLabel({
    String? title,
    String? language,
    String? codec,
    int? channelsCount,
    required int index,
  }) {
    final parts = <String>[];
    if (title != null && title.isNotEmpty) {
      parts.add(title);
    }
    if (language != null && language.isNotEmpty) {
      parts.add(language.toUpperCase());
    }
    if (codec != null && codec.isNotEmpty) {
      parts.add(CodecUtils.formatAudioCodec(codec));
    }
    if (channelsCount != null) {
      parts.add('${channelsCount}ch');
    }
    return parts.isEmpty ? '音频轨道 ${index + 1}' : parts.join(' · ');
  }

  /// 构建字幕轨道标签。
  ///
  /// 组合标题、语言和编解码器（带有友好的编解码器名称）。
  static String buildSubtitleLabel({String? title, String? language, String? codec, required int index}) {
    final parts = <String>[];
    if (title != null && title.isNotEmpty) {
      parts.add(title);
    }
    if (language != null && language.isNotEmpty) {
      parts.add(language.toUpperCase());
    }
    if (codec != null && codec.isNotEmpty) {
      parts.add(CodecUtils.formatSubtitleCodec(codec));
    }
    return parts.isEmpty ? '轨道 ${index + 1}' : parts.join(' · ');
  }
}
