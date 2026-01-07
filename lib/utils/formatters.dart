import 'package:duration/duration.dart';
import 'package:duration/locale.dart';
import '../i18n/strings.g.dart';

/// 使用前导零格式化具有最小位数的数字。
///
/// 示例：`padNumber(5, 3)` 返回 "005"
String padNumber(int number, int width) {
  return number.toString().padLeft(width, '0');
}

/// 用于格式化字节大小和速度的工具类
class ByteFormatter {
  ByteFormatter._();

  static const int _kb = 1024;
  static const int _mb = _kb * 1024;
  static const int _gb = _mb * 1024;

  /// 将字节格式化为人类可读的字符串（例如 "1.5 GB", "256.3 MB"）
  ///
  /// [bytes] 要格式化的字节数
  /// [decimals] 小数位数（默认值：KB/MB 为 1，GB 为 2）
  static String formatBytes(int bytes, {int? decimals}) {
    if (bytes < _kb) return '$bytes B';
    if (bytes < _mb) {
      return '${(bytes / _kb).toStringAsFixed(decimals ?? 1)} KB';
    }
    if (bytes < _gb) {
      return '${(bytes / _mb).toStringAsFixed(decimals ?? 1)} MB';
    }
    return '${(bytes / _gb).toStringAsFixed(decimals ?? 2)} GB';
  }

  /// 将每秒字节数的速度格式化为人类可读的字符串
  ///
  /// [bytesPerSecond] 每秒字节数的速度
  static String formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < _kb) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
    if (bytesPerSecond < _mb) {
      return '${(bytesPerSecond / _kb).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / _mb).toStringAsFixed(1)} MB/s';
  }

  /// 将以 kbps 为单位的比特率格式化为人类可读的字符串
  ///
  /// [kbps] 以千比特每秒为单位的比特率
  static String formatBitrate(int kbps) {
    if (kbps < 1000) return '$kbps kbps';
    return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
  }

  /// 将以 bps 为单位的比特率格式化为人类可读的字符串
  ///
  /// [bps] 以比特每秒为单位的比特率
  /// 返回格式化后的字符串，如 "8.5 Mbps"、"256 Kbps" 或 "128 bps"
  static String formatBitrateBps(int bps) {
    const kbps = 1000;
    const mbps = kbps * 1000;

    if (bps >= mbps) {
      return '${(bps / mbps).toStringAsFixed(2)} Mbps';
    } else if (bps >= kbps) {
      return '${(bps / kbps).toStringAsFixed(2)} Kbps';
    } else {
      return '$bps bps';
    }
  }
}

/// 将持续时间格式化为人类可读的文本格式（例如 "1h 23m" 或 "1 小时 23 分钟"）。
/// 根据当前应用程序区域设置使用本地化的单位名称。
/// 仅显示小时和分钟（不显示秒）。
///
/// 用于：媒体卡片、媒体详情、播放列表。
String formatDurationTextual(int milliseconds, {bool abbreviated = true}) {
  final duration = Duration(milliseconds: milliseconds);

  // 获取适用于 duration 包的区域设置
  final durationLocale = _getDurationLocale();

  // 使用缩写或完整单位（h、m）进行格式化，但不包含秒
  return prettyDuration(
    duration,
    abbreviated: abbreviated,
    locale: durationLocale,
    delimiter: abbreviated ? ' ' : ', ',
    spacer: '',
    // 配置为仅显示小时和分钟
    tersity: DurationTersity.minute,
  );
}

/// 将持续时间格式化为包含秒的人类可读文本格式（例如 "1h 23m 45s"）。
/// 根据当前应用程序区域设置使用本地化的单位名称。
/// 显示小时、分钟和秒。
///
/// 用于：睡眠定时器倒计时。
String formatDurationWithSeconds(Duration duration) {
  // 获取适用于 duration 包的区域设置
  final durationLocale = _getDurationLocale();

  // 使用包含秒的缩写单位（h、m、s）进行格式化
  return prettyDuration(
    duration,
    abbreviated: true,
    locale: durationLocale,
    delimiter: ' ',
    spacer: '',
    // 显示所有非零单位
    tersity: DurationTersity.second,
  );
}

/// 将持续时间格式化为时间戳格式（例如 "1:23:45" 或 "23:45"）。
/// 这种格式不是本地化的，因为它遵循通用的数字时钟约定。
/// 根据持续时间显示 H:MM:SS 或 M:SS。
///
/// 用于：视频控件、章节、剧集时长。
String formatDurationTimestamp(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  } else {
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 格式化带有符号指示器的毫秒同步偏移量（例如 "+150ms", "-250ms"）。
/// 此格式用于音频/字幕同步调整。
///
/// 用于：音频同步面板、同步偏移控件。
String formatSyncOffset(double offsetMs) {
  final sign = offsetMs >= 0 ? '+' : '';
  return '$sign${offsetMs.round()}ms';
}

/// 根据当前应用程序区域设置获取 duration 包的区域设置。
/// 如果 duration 包不支持该区域设置，则回退到英语。
DurationLocale _getDurationLocale() {
  // 从 slang 的 LocaleSettings 获取当前区域设置
  final appLocale = LocaleSettings.currentLocale;
  final languageCode = appLocale.languageCode;

  // 将支持的区域设置映射到 duration 包的区域设置
  // duration 包支持许多语言，但我们将重点关注我们应用程序支持的语言：en, de, it, nl, sv, zh
  try {
    return DurationLocale.fromLanguageCode(languageCode) ?? const EnglishDurationLocale();
  } catch (e) {
    // 如果不支持语言代码，则回退到英语
    return const EnglishDurationLocale();
  }
}
