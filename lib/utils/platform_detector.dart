import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

/// 用于检测应用程序是否在 Android TV 上运行的服务
class TvDetectionService {
  static TvDetectionService? _instance;
  bool _isTV = false;
  bool _initialized = false;

  TvDetectionService._();

  /// 获取单例实例，如果需要则进行初始化
  static Future<TvDetectionService> getInstance() async {
    if (_instance == null) {
      _instance = TvDetectionService._();
      await _instance!._detect();
    }
    return _instance!;
  }

  Future<void> _detect() async {
    if (_initialized) return;

    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      // 检查 android.software.leanback 功能（标准 Android TV 检测）
      _isTV = androidInfo.systemFeatures.contains('android.software.leanback');
    }
    _initialized = true;
  }

  bool get isTV => _isTV;

  /// 初始化后的同步访问（如果未初始化则返回 false）
  static bool isTVSync() => _instance?._isTV ?? false;
}

/// 平台检测工具类
class PlatformDetector {
  /// 检测是否在 Android TV 上运行（需要 TvDetectionService 已初始化）
  static bool isTV() {
    return TvDetectionService.isTVSync();
  }

  /// 检测应用程序是否应使用侧边导航（桌面或 TV）
  static bool shouldUseSideNavigation(BuildContext context) {
    return isDesktop(context) || isTV();
  }

  /// 检测是否在移动平台（iOS 或 Android）上运行
  /// 使用 Theme 以在整个应用程序中实现一致的平台检测
  static bool isMobile(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.android;
  }

  /// 检测是否在桌面平台（Windows、macOS 或 Linux）上运行
  static bool isDesktop(BuildContext context) {
    return !isMobile(context);
  }

  /// 根据屏幕尺寸检测设备是否可能是平板电脑
  /// 使用对角线屏幕尺寸来确定设备是否为平板电脑
  static bool isTablet(BuildContext context) {
    final data = MediaQuery.of(context);
    final size = data.size;
    final diagonal = sqrt(size.width * size.width + size.height * size.height);
    final devicePixelRatio = data.devicePixelRatio;

    // 将对角线从逻辑像素转换为英寸（假设 160 DPI 为基准）
    final diagonalInches = diagonal / (devicePixelRatio * 160 / 2.54);

    // 将对角线 >= 7 英寸的设备视为平板电脑
    return diagonalInches >= 7.0;
  }

  /// 检测设备是否为手机（移动平台但非平板电脑）
  static bool isPhone(BuildContext context) {
    return isMobile(context) && !isTablet(context);
  }
}
