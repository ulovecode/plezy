/// 编解码器相关操作的工具类。
///
/// 提供中心化的编解码器名称映射、文件扩展名查询以及显示名称格式化。
class CodecUtils {
  CodecUtils._();

  /// 将 Plex 字幕编解码器名称映射到文件扩展名。
  ///
  /// 为给定的字幕编解码器返回相应的文件扩展名。
  /// 对于未知或 null 的编解码器，默认返回 'srt'。
  static String getSubtitleExtension(String? codec) {
    if (codec == null) return 'srt';

    switch (codec.toLowerCase()) {
      case 'subrip':
      case 'srt':
        return 'srt';
      case 'ass':
        return 'ass';
      case 'ssa':
        return 'ssa';
      case 'webvtt':
      case 'vtt':
        return 'vtt';
      case 'mov_text':
        return 'srt';
      case 'pgs':
      case 'hdmv_pgs_subtitle':
        return 'sup';
      case 'dvd_subtitle':
      case 'dvdsub':
        return 'sub';
      default:
        return 'srt';
    }
  }

  /// 将字幕编解码器名称格式化为用户友好的显示格式。
  ///
  /// 将内部编解码器名称（如 'SUBRIP'）转换为友好名称（如 'SRT'）。
  static String formatSubtitleCodec(String codec) {
    final upper = codec.toUpperCase();
    return switch (upper) {
      'SUBRIP' => 'SRT',
      'DVD_SUBTITLE' => 'DVD',
      'WEBVTT' => 'VTT',
      'HDMV_PGS_SUBTITLE' => 'PGS',
      'MOV_TEXT' => 'MOV',
      _ => upper,
    };
  }

  /// 将视频编解码器名称格式化为用户友好的显示格式。
  ///
  /// 将内部编解码器名称（如 'hevc'）转换为友好名称（如 'HEVC'）。
  static String formatVideoCodec(String codec) {
    final lower = codec.toLowerCase();
    return switch (lower) {
      'h264' || 'avc1' || 'avc' => 'H.264',
      'hevc' || 'h265' || 'hev1' => 'HEVC',
      'av1' => 'AV1',
      'vp8' => 'VP8',
      'vp9' => 'VP9',
      'mpeg2video' || 'mpeg2' => 'MPEG-2',
      'mpeg4' => 'MPEG-4',
      'vc1' => 'VC-1',
      _ => codec.toUpperCase(),
    };
  }

  /// 将音频编解码器名称格式化为用户友好的显示格式。
  static String formatAudioCodec(String codec) {
    final lower = codec.toLowerCase();
    return switch (lower) {
      'aac' => 'AAC',
      'ac3' => 'AC3',
      'eac3' || 'ec3' => 'E-AC3',
      'truehd' => 'TrueHD',
      'dts' => 'DTS',
      'dca' => 'DTS',
      'dtshd' || 'dts-hd' => 'DTS-HD',
      'flac' => 'FLAC',
      'mp3' || 'mp3float' => 'MP3',
      'opus' => 'Opus',
      'vorbis' => 'Vorbis',
      'pcm_s16le' || 'pcm_s24le' || 'pcm' => 'PCM',
      _ => codec.toUpperCase(),
    };
  }
}
