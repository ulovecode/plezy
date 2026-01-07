import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

/// 管理睡眠定时器功能的服务
/// 允许设置定时器以在指定时间后暂停/停止播放
class SleepTimerService extends ChangeNotifier {
  static final SleepTimerService _instance = SleepTimerService._internal();
  factory SleepTimerService() => _instance;
  SleepTimerService._internal();

  Timer? _timer;
  DateTime? _endTime;
  Duration? _duration;
  VoidCallback? _onTimerComplete;

  /// 定时器当前是否处于活跃状态
  bool get isActive => _timer != null && _timer!.isActive;

  /// 定时器将完成的时间
  DateTime? get endTime => _endTime;

  /// 定时器的原始时长
  Duration? get duration => _duration;

  /// 定时器剩余时间
  Duration? get remainingTime {
    if (_endTime == null) return null;
    final remaining = _endTime!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// 启动指定时长的睡眠定时器
  /// [duration] - 定时器完成前的时长
  /// [onComplete] - 定时器完成时执行的回调
  void startTimer(Duration duration, VoidCallback onComplete) {
    // 取消任何现有定时器
    cancelTimer();

    _duration = duration;
    _endTime = DateTime.now().add(duration);
    _onTimerComplete = onComplete;

    appLogger.d('睡眠定时器已启动: ${duration.inMinutes} 分钟');

    // 创建一个周期性定时器以更新剩余时间
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = remainingTime;

      if (remaining == null || remaining.inSeconds <= 0) {
        appLogger.d('睡眠定时器已完成');
        _executeCallback();
        cancelTimer();
      } else {
        // 通知监听器更新 UI
        notifyListeners();
      }
    });

    notifyListeners();
  }

  /// 取消当前活跃的定时器
  void cancelTimer() {
    if (_timer != null) {
      appLogger.d('睡眠定时器已取消');
      _timer?.cancel();
      _timer = null;
      _endTime = null;
      _duration = null;
      _onTimerComplete = null;
      notifyListeners();
    }
  }

  /// 将当前定时器延长指定的时长
  void extendTimer(Duration additionalTime) {
    if (_endTime != null) {
      _endTime = _endTime!.add(additionalTime);
      _duration = _duration != null ? _duration! + additionalTime : additionalTime;
      appLogger.d('睡眠定时器已延长 ${additionalTime.inMinutes} 分钟');
      notifyListeners();
    }
  }

  void _executeCallback() {
    if (_onTimerComplete != null) {
      try {
        _onTimerComplete!();
      } catch (e) {
        appLogger.e('执行睡眠定时器回调出错', error: e);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
