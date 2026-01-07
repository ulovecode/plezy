import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'platform_detector.dart';

/// 用于管理整个应用程序中设备方向偏好的辅助类。
class OrientationHelper {
  /// 根据设备类型恢复默认的方向偏好。
  ///
  /// 对于手机：锁定为仅纵向（向上和向下）
  /// 对于平板电脑/桌面设备：允许所有方向
  ///
  /// 在离开视频播放器等全屏体验时应调用此方法，以恢复应用程序的默认方向行为。
  static void restoreDefaultOrientations(BuildContext context) {
    final isPhone = PlatformDetector.isPhone(context);

    if (isPhone) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    } else {
      // 对于平板电脑和桌面设备，允许所有方向
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  /// 将方向设置为仅横向模式。
  ///
  /// 视频播放器在播放期间使用此方法强制横向。
  static void setLandscapeOrientation() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  /// 恢复全屏系统 UI 模式。
  ///
  /// 在退出全屏模式时应调用此方法。
  static void restoreSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
