import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用于在 GitHub 上检查新版本的服务
/// 仅当设置了 ENABLE_UPDATE_CHECK 构建标志时才启用
class UpdateService {
  static final Logger _logger = Logger();
  static const String _githubRepo = 'edde746/plezy';

  // SharedPreferences 键名
  static const String _keySkippedVersion = 'update_skipped_version';
  static const String _keyLastCheckTime = 'update_last_check_time';

  // 检查冷却时间：6 小时
  static const Duration _checkCooldown = Duration(hours: 6);

  /// 检查是否通过构建标志启用了更新检查
  static bool get isUpdateCheckEnabled {
    const enabled = bool.fromEnvironment('ENABLE_UPDATE_CHECK', defaultValue: false);
    return enabled;
  }

  /// 跳过特定版本
  static Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySkippedVersion, version);
  }

  /// 获取已跳过的版本
  static Future<String?> getSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySkippedVersion);
  }

  /// 清除已跳过的版本
  static Future<void> clearSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySkippedVersion);
  }

  /// 检查自上次检查以来是否已过冷却期
  static Future<bool> shouldCheckForUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckString = prefs.getString(_keyLastCheckTime);

    if (lastCheckString == null) return true;

    final lastCheck = DateTime.parse(lastCheckString);
    final now = DateTime.now();
    final timeSinceLastCheck = now.difference(lastCheck);

    return timeSinceLastCheck >= _checkCooldown;
  }

  /// 更新上次检查的时间戳
  static Future<void> _updateLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastCheckTime, DateTime.now().toIso8601String());
  }

  /// 执行实际更新检查的内部方法
  /// [respectCooldown] - 如果为 true，则检查冷却时间并更新上次检查时间
  static Future<Map<String, dynamic>?> _performUpdateCheck({required bool respectCooldown}) async {
    if (!isUpdateCheckEnabled) {
      return null;
    }

    // 如果要求，则检查冷却时间
    if (respectCooldown && !await shouldCheckForUpdates()) {
      return null;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final dio = Dio();
      final response = await dio.get(
        'https://api.github.com/repos/$_githubRepo/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final latestVersion = data['tag_name'] as String;

        // 如果存在 'v' 前缀，则将其移除
        final cleanVersion = latestVersion.startsWith('v') ? latestVersion.substring(1) : latestVersion;

        final hasUpdate = _isNewerVersion(cleanVersion, currentVersion);

        if (hasUpdate) {
          // 检查此版本是否已被跳过
          final skippedVersion = await getSkippedVersion();
          if (skippedVersion == cleanVersion) {
            // 即使跳过也更新上次检查时间 (如果考虑冷却时间)
            if (respectCooldown) {
              await _updateLastCheckTime();
            }
            return null;
          }

          // 成功时更新上次检查时间 (如果考虑冷却时间)
          if (respectCooldown) {
            await _updateLastCheckTime();
          }

          return {
            'hasUpdate': true,
            'currentVersion': currentVersion,
            'latestVersion': cleanVersion,
            'releaseUrl': data['html_url'] as String,
            'releaseName': data['name'] as String? ?? '版本 $cleanVersion',
            'releaseNotes': data['body'] as String? ?? '',
            'publishedAt': data['published_at'] as String,
          };
        }
      }

      // 即使没有更新也更新上次检查时间 (如果考虑冷却时间)
      if (respectCooldown) {
        await _updateLastCheckTime();
      }
    } catch (e) {
      _logger.e('检查更新失败: $e');
    }

    return null;
  }

  /// 在 GitHub 上检查更新 (手动检查，忽略冷却时间)
  /// 返回包含更新信息的 Map，如果没有更新或出错则返回 null
  static Future<Map<String, dynamic>?> checkForUpdates({bool silent = false}) async {
    return _performUpdateCheck(respectCooldown: false);
  }

  /// 启动时检查更新 (考虑冷却时间和已跳过的版本)
  /// 如果有可用更新则返回更新信息，否则返回 null
  static Future<Map<String, dynamic>?> checkForUpdatesOnStartup() async {
    return _performUpdateCheck(respectCooldown: true);
  }

  /// 将版本字符串解析为整数列表
  /// 通过仅获取数字部分来处理类似 "1.2.3+4" 的版本
  static List<int> _parseVersionParts(String version) {
    return version.split('.').map((p) {
      final numPart = p.split('+').first.split('-').first;
      return int.tryParse(numPart) ?? 0;
    }).toList();
  }

  /// 比较两个版本字符串
  /// 如果 newVersion 比 currentVersion 新，则返回 true
  static bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = _parseVersionParts(newVersion);
      final currentParts = _parseVersionParts(currentVersion);

      // 比较每个部分
      final maxLength = newParts.length > currentParts.length ? newParts.length : currentParts.length;

      for (int i = 0; i < maxLength; i++) {
        final newPart = i < newParts.length ? newParts[i] : 0;
        final currentPart = i < currentParts.length ? currentParts[i] : 0;

        if (newPart > currentPart) return true;
        if (newPart < currentPart) return false;
      }

      return false; // 版本相等
    } catch (e) {
      _logger.e('比较版本时出错: $e');
      return false;
    }
  }
}
