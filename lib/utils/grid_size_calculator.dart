import 'package:flutter/material.dart';
import '../services/settings_service.dart' show LibraryDensity;
import 'layout_constants.dart';

/// 用于在整个应用程序中计算一致的网格尺寸的工具类
class GridSizeCalculator {
  /// 平板设备的屏幕宽度断点
  static const double tabletBreakpoint = ScreenBreakpoints.tablet;

  /// 桌面设备的屏幕宽度断点
  static const double desktopBreakpoint = ScreenBreakpoints.desktop;

  /// 根据屏幕尺寸和密度计算网格项目的最大交叉轴延伸范围（max cross-axis extent）
  static double getMaxCrossAxisExtent(BuildContext context, LibraryDensity density) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > desktopBreakpoint;
    final isTablet = screenWidth > tabletBreakpoint && screenWidth <= desktopBreakpoint;

    switch (density) {
      case LibraryDensity.comfortable:
        if (isDesktop) return GridLayoutConstants.comfortableDesktop;
        if (isTablet) return GridLayoutConstants.comfortableTablet;
        return GridLayoutConstants.comfortableMobile;
      case LibraryDensity.compact:
        if (isDesktop) return GridLayoutConstants.compactDesktop;
        if (isTablet) return GridLayoutConstants.compactTablet;
        return GridLayoutConstants.compactMobile;
      case LibraryDensity.normal:
        if (isDesktop) return GridLayoutConstants.normalDesktop;
        if (isTablet) return GridLayoutConstants.normalTablet;
        return GridLayoutConstants.normalMobile;
    }
  }

  /// 计算考虑外部边距后的最大交叉轴延伸范围。
  ///
  /// 使用响应式策略：
  /// - 宽屏幕 (>=900px)：基于除数的计算，具有最大项目宽度限制
  /// - 中等屏幕 (600-899px)：固定项目数量（根据密度为 4-6 个项目）
  /// - 小屏幕 (<600px)：固定项目数量（根据密度为 2-4 个项目）
  static double getMaxCrossAxisExtentWithPadding(
    BuildContext context,
    LibraryDensity density,
    double horizontalPadding,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - horizontalPadding;

    if (ScreenBreakpoints.isWideTabletOrLarger(screenWidth)) {
      // 宽屏幕（桌面/大平板横屏）：响应式划分
      double divisor;
      double maxItemWidth;

      switch (density) {
        case LibraryDensity.comfortable:
          divisor = 6.5;
          maxItemWidth = 280;
        case LibraryDensity.normal:
          divisor = 8.0;
          maxItemWidth = 200;
        case LibraryDensity.compact:
          divisor = 10.0;
          maxItemWidth = 160;
      }

      return (availableWidth / divisor).clamp(0, maxItemWidth);
    } else if (ScreenBreakpoints.isTablet(screenWidth)) {
      // 中等屏幕（平板）：固定 4-5-6 个项目
      int targetItemCount = switch (density) {
        LibraryDensity.comfortable => 4,
        LibraryDensity.normal => 5,
        LibraryDensity.compact => 6,
      };
      return availableWidth / targetItemCount;
    } else {
      // 小屏幕（手机）：固定 2-3-4 个项目
      int targetItemCount = switch (density) {
        LibraryDensity.comfortable => 2,
        LibraryDensity.normal => 3,
        LibraryDensity.compact => 4,
      };
      return availableWidth / targetItemCount;
    }
  }

  /// 返回当前屏幕是否为桌面级尺寸的屏幕
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width > desktopBreakpoint;
  }

  /// 返回当前屏幕是否为平板级尺寸的屏幕
  static bool isTablet(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth > tabletBreakpoint && screenWidth <= desktopBreakpoint;
  }

  /// 返回当前屏幕是否为手机级尺寸的屏幕
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width <= tabletBreakpoint;
  }
}
