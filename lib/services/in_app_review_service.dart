import 'dart:io' show Platform;
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// 管理应用内评分提示的服务
/// 仅在设置了 ENABLE_IN_APP_REVIEW 构建标志时启用
class InAppReviewService {
  static final InAppReviewService _instance = InAppReviewService._();
  static InAppReviewService get instance => _instance;

  InAppReviewService._();

  final InAppReview _inAppReview = InAppReview.instance;

  // SharedPreferences 键
  static const String _keyQualifyingSessionsCount = 'review_qualifying_sessions_count';
  static const String _keyLastPromptTime = 'review_last_prompt_time';

  // 配置
  static const int _requiredSessions = 6;
  static const Duration _minimumSessionDuration = Duration(minutes: 5);
  static const Duration _promptCooldown = Duration(days: 60);

  // 会话跟踪
  DateTime? _sessionStartTime;

  /// 检查是否通过构建标志启用了应用内评分
  /// 仅在移动平台 (iOS 和 Android) 上启用
  static bool get isEnabled {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }
    const enabled = bool.fromEnvironment('ENABLE_IN_APP_REVIEW', defaultValue: false);
    return enabled;
  }

  /// 开始跟踪新会话
  void startSession() {
    if (!isEnabled) return;
    _sessionStartTime = DateTime.now();
    appLogger.d('应用内评分：会话已开始');
  }

  /// 结束当前会话并检查其是否符合条件
  /// 当应用进入后台或关闭时调用此方法
  Future<void> endSession() async {
    if (!isEnabled || _sessionStartTime == null) return;

    final sessionDuration = DateTime.now().difference(_sessionStartTime!);
    _sessionStartTime = null;

    if (sessionDuration >= _minimumSessionDuration) {
      await _incrementQualifyingSessions();
      appLogger.d('应用内评分：符合条件的会话已结束 (${sessionDuration.inMinutes} 分钟)');
      await maybeRequestReview();
    } else {
      appLogger.d('应用内评分：会话过短 (${sessionDuration.inMinutes} 分钟)');
    }
  }

  /// 增加符合条件的会话计数器
  Future<void> _incrementQualifyingSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt(_keyQualifyingSessionsCount) ?? 0;
    await prefs.setInt(_keyQualifyingSessionsCount, currentCount + 1);
  }

  /// 获取当前符合条件的会话计数
  Future<int> _getQualifyingSessionsCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyQualifyingSessionsCount) ?? 0;
  }

  /// 根据会话计数和冷却时间检查是否应该请求评分
  Future<bool> _shouldRequestReview() async {
    final prefs = await SharedPreferences.getInstance();

    // 检查会话计数
    final sessionCount = await _getQualifyingSessionsCount();
    if (sessionCount < _requiredSessions) {
      appLogger.d('应用内评分：会话不足 ($sessionCount/$_requiredSessions)');
      return false;
    }

    // 检查冷却时间
    final lastPromptString = prefs.getString(_keyLastPromptTime);
    if (lastPromptString != null) {
      final lastPrompt = DateTime.parse(lastPromptString);
      final timeSinceLastPrompt = DateTime.now().difference(lastPrompt);
      if (timeSinceLastPrompt < _promptCooldown) {
        final daysRemaining = (_promptCooldown - timeSinceLastPrompt).inDays;
        appLogger.d('应用内评分：冷却中 (剩余 $daysRemaining 天)');
        return false;
      }
    }

    return true;
  }

  /// 如果满足条件，则请求评分
  Future<void> maybeRequestReview() async {
    if (!isEnabled) return;

    final shouldRequest = await _shouldRequestReview();
    if (!shouldRequest) return;

    try {
      // 检查此设备上是否可以使用应用内评分
      final isAvailable = await _inAppReview.isAvailable();
      if (!isAvailable) {
        appLogger.d('应用内评分：此设备上不可用');
        return;
      }

      // 请求评分
      await _inAppReview.requestReview();
      appLogger.i('应用内评分：评分提示已显示');

      // 记录我们已显示提示并重置会话计数
      await _recordPromptShown();
    } catch (e) {
      appLogger.e('应用内评分：请求评分时出错', error: e);
    }
  }

  /// 记录评分提示已显示
  Future<void> _recordPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastPromptTime, DateTime.now().toIso8601String());
    // 重置会话计数，以便用户在下次提示前需要更多地使用应用
    await prefs.setInt(_keyQualifyingSessionsCount, 0);
  }

  /// 获取有关当前状态的调试信息 (用于开发/测试)
  Future<Map<String, dynamic>> getDebugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionCount = prefs.getInt(_keyQualifyingSessionsCount) ?? 0;
    final lastPromptString = prefs.getString(_keyLastPromptTime);
    final isAvailable = await _inAppReview.isAvailable();

    return {
      'isEnabled': isEnabled,
      'isAvailable': isAvailable,
      'qualifyingSessions': sessionCount,
      'requiredSessions': _requiredSessions,
      'lastPromptTime': lastPromptString,
      'cooldownDays': _promptCooldown.inDays,
      'currentSessionStartTime': _sessionStartTime?.toIso8601String(),
    };
  }

  /// 重置所有存储的数据 (用于测试目的)
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyQualifyingSessionsCount);
    await prefs.remove(_keyLastPromptTime);
    _sessionStartTime = null;
    appLogger.d('应用内评分：状态已重置');
  }
}
