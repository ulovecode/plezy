import 'package:flutter/widgets.dart';

/// 整个应用程序中使用的布局和尺寸常量
/// 响应式设计的屏幕宽度断点
class ScreenBreakpoints {
  /// 移动设备的断点（< 600px）
  static const double mobile = 600;

  /// 宽屏平板电脑 / 小型桌面设备的断点（900px）
  /// 用于中间响应式布局
  static const double wideTablet = 900;

  /// 桌面设备的断点（1200px）
  static const double desktop = 1200;

  /// 大型桌面设备的断点（1600px）
  static const double largeDesktop = 1600;

  // 用于向后兼容的旧别名
  static const double tablet = mobile;

  /// 宽度是否为移动设备尺寸（< 600px）
  static bool isMobile(double width) => width < mobile;

  /// 宽度是否为平板电脑尺寸（600px - 1199px）
  static bool isTablet(double width) => width >= mobile && width < desktop;

  /// 宽度是否为宽屏平板电脑尺寸（900px - 1199px）
  /// 适用于需要比手机更多但比桌面设备更少列的布局
  static bool isWideTablet(double width) => width >= wideTablet && width < desktop;

  /// 宽度是否为桌面设备尺寸（1200px - 1599px）
  static bool isDesktop(double width) => width >= desktop && width < largeDesktop;

  /// 宽度是否为大型桌面设备尺寸（>= 1600px）
  static bool isLargeDesktop(double width) => width >= largeDesktop;

  /// 宽度是否为桌面设备或更大（>= 1200px）
  static bool isDesktopOrLarger(double width) => width >= desktop;

  /// 宽度是否为宽屏平板电脑或更大（>= 900px）
  static bool isWideTabletOrLarger(double width) => width >= wideTablet;
}

/// 网格布局常量
class GridLayoutConstants {
  /// 舒适密度模式下网格项目的最大交叉轴范围
  static const double comfortableDesktop = 280;
  static const double comfortableTablet = 240;
  static const double comfortableMobile = 200;

  /// 紧凑密度模式下网格项目的最大交叉轴范围
  static const double compactDesktop = 200;
  static const double compactTablet = 170;
  static const double compactMobile = 140;

  /// 标准密度模式下网格项目的最大交叉轴范围
  static const double normalDesktop = 240;
  static const double normalTablet = 200;
  static const double normalMobile = 170;

  /// 媒体卡片的默认宽高比（海报）
  static const double posterAspectRatio = 2 / 3.3;

  /// 网格间距（边到边卡片）
  static const double crossAxisSpacing = 0;
  static const double mainAxisSpacing = 0;

  /// 标准网格内边距
  static EdgeInsets get gridPadding => const EdgeInsets.fromLTRB(8, 0, 8, 8);
}
